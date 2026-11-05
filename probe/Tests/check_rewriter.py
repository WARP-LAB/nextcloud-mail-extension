#!/usr/bin/env python3
"""Checks the MIME rewriter without Mail: Apple Mail shaped fixtures in, stdlib email parser out.

Run from anywhere: python3 Tests/check_rewriter.py
"""

import base64
import email
import email.policy
import json
import pathlib
import quopri
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAYLOAD = base64.encodebytes(bytes(range(256)) * 400).decode()

MAIL_HEADERS = """Content-Type: {content_type}
Mime-Version: 1.0 (Mac OS X Mail 16.0 \\(3826.200.121\\))
Subject: [probe ff] fixture
X-Universally-Unique-Identifier: 11111111-2222-3333-4444-555555555555
Message-Id: <fixture@example.test>
From: Sender <sender@example.test>
To: Recipient <recipient@example.test>

"""

HTML_WITH_ATTACHMENT = MAIL_HEADERS.format(content_type='multipart/alternative; boundary="Apple-Mail=_A"') + f"""--Apple-Mail=_A
Content-Transfer-Encoding: 7bit
Content-Type: text/plain; charset=us-ascii

Text before the file.

Text after the file.

--Apple-Mail=_A
Content-Type: multipart/mixed; boundary="Apple-Mail=_A-inner"

--Apple-Mail=_A-inner
Content-Transfer-Encoding: 7bit
Content-Type: text/html; charset=us-ascii

<html><head><meta charset="us-ascii"></head><body style="overflow-wrap: break-word;">Text before the file.<br></body></html>
--Apple-Mail=_A-inner
Content-Disposition: attachment; filename=dummy-1MB.bin
Content-Type: application/octet-stream; name="dummy-1MB.bin"
Content-Transfer-Encoding: base64

{PAYLOAD}
--Apple-Mail=_A-inner
Content-Transfer-Encoding: 7bit
Content-Type: text/html; charset=us-ascii

<html><body>Text after the file.</body></html>
--Apple-Mail=_A-inner--

--Apple-Mail=_A--
"""

PLAIN_WITH_INLINE_IMAGE = MAIL_HEADERS.format(content_type='multipart/mixed; boundary="B"') + f"""--B
Content-Transfer-Encoding: quoted-printable
Content-Type: text/plain; charset=utf-8

Caf=C3=A9 before.

--B
Content-Disposition: inline; filename*=utf-8''caf%C3%A9%20photo.png
Content-Type: image/png
Content-Transfer-Encoding: base64

{PAYLOAD}
--B
Content-Disposition: attachment; filename="second.pdf"
Content-Type: application/pdf
Content-Transfer-Encoding: base64

{PAYLOAD}
--B--
"""

BASE64_TEXT = MAIL_HEADERS.format(content_type='multipart/mixed; boundary="C"') + f"""--C
Content-Transfer-Encoding: base64
Content-Type: text/plain; charset=utf-8

{base64.encodebytes("Base64 body text.".encode()).decode()}
--C
Content-Disposition: attachment; filename=file.bin
Content-Type: application/octet-stream
Content-Transfer-Encoding: base64

{PAYLOAD}
--C--
"""

ONLY_ATTACHMENT = MAIL_HEADERS.format(content_type='application/pdf; name="only.pdf"').replace(
    "Mime-Version", 'Content-Disposition: attachment; filename="only.pdf"\nContent-Transfer-Encoding: base64\nMime-Version'
) + PAYLOAD

NO_ATTACHMENT = MAIL_HEADERS.format(content_type="text/plain; charset=us-ascii") + "Just text.\n"

# Attachment first, as Mail sometimes sends it, so a kept text file comes before the message text.
MIXED_SIZES = MAIL_HEADERS.format(content_type='multipart/mixed; boundary="D"') + f"""--D
Content-Disposition: attachment; filename=notes.txt
Content-Type: text/plain; charset=us-ascii; name="notes.txt"
Content-Transfer-Encoding: 7bit

Attached notes.

--D
Content-Transfer-Encoding: 7bit
Content-Type: text/plain; charset=us-ascii

Body text.

--D
Content-Disposition: attachment; filename=small.bin
Content-Type: application/octet-stream; name="small.bin"
Content-Transfer-Encoding: base64

{base64.encodebytes(b"small file").decode()}
--D
Content-Disposition: attachment; filename=large.bin
Content-Type: application/octet-stream; name="large.bin"
Content-Transfer-Encoding: base64

{PAYLOAD}
--D--
"""
LARGE_BYTES = 256 * 400


def text_parts(message, subtype):
    parts = []
    for part in message.walk():
        if part.get_content_type() == f"text/{subtype}":
            parts.append(part.get_payload(decode=True).decode("utf-8"))
    return parts


def attachment_names(message):
    return [part.get_filename() for part in message.walk() if part.get_filename()]


def main():
    failures = []

    def check(condition, label):
        print(("ok    " if condition else "FAIL  ") + label)
        if not condition:
            failures.append(label)

    with tempfile.TemporaryDirectory() as temp:
        temp = pathlib.Path(temp)
        tool = temp / "rewriter-check"
        subprocess.run(
            [
                "xcrun", "swiftc", "-o", str(tool),
                str(ROOT / "MailProbeExtension/MimeRewriter.swift"),
                str(ROOT / "MailProbeExtension/ProbeDirective.swift"),
                str(ROOT / "Tests/RewriterCheck/main.swift"),
            ],
            check=True,
        )

        def rewrite(source, crlf, limit=None):
            raw = source.replace("\n", "\r\n") if crlf else source
            (temp / "in.eml").write_bytes(raw.encode())
            command = [str(tool), "rewrite", str(temp / "in.eml"), str(temp / "out.eml")]
            if limit is not None:
                command.append(str(limit))
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            output = (temp / "out.eml").read_bytes()
            return json.loads(result.stdout), output, email.message_from_bytes(output, policy=email.policy.default)

        def directive(subject):
            result = subprocess.run([str(tool), "directive", subject], check=True, capture_output=True, text=True)
            return json.loads(result.stdout)

        for crlf in (True, False):
            tag = "CRLF" if crlf else "LF"

            info, output, message = rewrite(HTML_WITH_ATTACHMENT, crlf)
            check(info["usesCRLF"] == crlf, f"{tag} html: line endings detected")
            check(info["stripped"] == ["dummy-1MB.bin"], f"{tag} html: attachment reported")
            check(attachment_names(message) == [], f"{tag} html: attachment removed")
            check(not message.defects and not any(p.defects for p in message.walk()), f"{tag} html: output has no MIME defects")
            check(message["X-MailProbe"] == "ff call=2; stripped=1", f"{tag} html: header added")
            check(message["Subject"] == "[probe ff] fixture", f"{tag} html: original headers kept")
            check("Text before the file." in text_parts(message, "plain")[0], f"{tag} html: plain body kept")
            check(text_parts(message, "plain")[0].startswith("[MAILPROBE] ff call=2 stripped=1"), f"{tag} html: plain note added")
            html = text_parts(message, "html")
            check(len(html) == 2 and "Text after the file." in html[1], f"{tag} html: both html fragments kept")
            check('<body style="overflow-wrap: break-word;"><div><b>[MAILPROBE]' in html[0].replace("\r\n", "\n"), f"{tag} html: note placed inside body")
            check("[MAILPROBE]" not in html[1], f"{tag} html: note added only once")
            check(b"--Apple-Mail=_A--" in output and b"--Apple-Mail=_A-inner--" in output, f"{tag} html: prefixed boundaries both closed")
            if crlf:
                check(b"\n" not in output.replace(b"\r\n", b""), f"{tag} html: no bare LF in output")

            info, _, message = rewrite(PLAIN_WITH_INLINE_IMAGE, crlf)
            check(info["stripped"] == ["café photo.png", "second.pdf"], f"{tag} inline: encoded filename and second file found")
            check(attachment_names(message) == [], f"{tag} inline: both removed")
            plain = text_parts(message, "plain")[0]
            check("Café before." in plain and "[MAILPROBE] ff call=2" in plain, f"{tag} inline: quoted-printable body intact with note")
            check("caf? photo.png" in plain, f"{tag} inline: non-ASCII name made safe in note")

            info, _, message = rewrite(BASE64_TEXT, crlf)
            plain = text_parts(message, "plain")[0]
            check(plain.startswith("[MAILPROBE]") and "Base64 body text." in plain, f"{tag} base64 text: note added and body kept")

            info, output, message = rewrite(ONLY_ATTACHMENT, crlf)
            check(info["stripped"] == [] and b"only-attachment" in output, f"{tag} only attachment: left in place and flagged")
            check(attachment_names(message) == ["only.pdf"], f"{tag} only attachment: file still present")

            info, _, message = rewrite(NO_ATTACHMENT, crlf)
            check(info["stripped"] == [], f"{tag} no attachment: nothing stripped")
            check("Just text." in text_parts(message, "plain")[0], f"{tag} no attachment: body kept")
            check(text_parts(message, "plain")[0].startswith("[MAILPROBE] ff call=2"), f"{tag} no attachment: note added")

            info, _, message = rewrite(MIXED_SIZES, crlf, limit=1000)
            check(info["stripped"] == ["large.bin"], f"{tag} size limit: only the large file removed")
            check(attachment_names(message) == ["notes.txt", "small.bin"], f"{tag} size limit: small files kept")
            check(not message.defects and not any(p.defects for p in message.walk()), f"{tag} size limit: output has no MIME defects")
            small = [p for p in message.walk() if p.get_filename() == "small.bin"][0]
            check(small.get_payload(decode=True) == b"small file", f"{tag} size limit: kept file unchanged")
            notes, body = text_parts(message, "plain")
            check("[MAILPROBE]" not in notes and "Attached notes." in notes, f"{tag} size limit: note not written into a kept text file")
            check(body.startswith("[MAILPROBE]") and "Body text." in body, f"{tag} size limit: note added to the message text")

            info, _, _ = rewrite(MIXED_SIZES, crlf, limit=LARGE_BYTES)
            check(info["stripped"] == [], f"{tag} size limit: a file exactly at the limit stays")
            info, _, _ = rewrite(MIXED_SIZES, crlf, limit=LARGE_BYTES - 1)
            check(info["stripped"] == ["large.bin"], f"{tag} size limit: a file one byte over is removed")
            info, _, message = rewrite(MIXED_SIZES, crlf)
            check(info["stripped"] == ["notes.txt", "small.bin", "large.bin"] and attachment_names(message) == [], f"{tag} no limit: all files removed")

        check(directive("hello")["marked"] is False, "directive: normal subject is unmarked")
        check(directive("Re: probe the [probes] thing")["marked"] is False, "directive: similar words do not match")
        parsed = directive("[probe ff delay=30] t1")
        check(parsed["delay"] == 30 and "isSigned: false, isEncrypted: false" in parsed["action"], "directive: flags and delay")
        check("isSigned: true, isEncrypted: false" in directive("Fwd: [PROBE TF] t")["action"], "directive: case-insensitive, signed flag")
        check(directive("[probe erre]")["action"] == "failEncryption", "directive: encryption failure")
        check(directive("[probe ff nostatus]")["noStatus"] is True, "directive: nostatus")
        check(directive("[probe block] t")["blocksSend"] is True, "directive: block")
        check(directive("[probe ff] t")["blocksSend"] is False, "directive: no block by default")
        check(directive("[probe ff min=5] t")["removalLimit"] == 5_000_000, "directive: size limit in decimal MB")
        check(directive("[probe ff] t")["removalLimit"] == -1, "directive: no size limit by default")
        check(directive("[probe]")["action"] == "logOnly", "directive: bare marker only logs")

    print(f"\n{len(failures)} failure(s)" if failures else "\nAll checks passed")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
