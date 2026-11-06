#!/usr/bin/env python3
"""Makes the unit tests' message fixtures from messages the probe saved in probe/test-results/.

Usage: python3 tests/make-fixtures.py

The probe's messages hold real names, addresses and attachments, so they stay local. This script copies the ones
listed in FIXTURES and anonymises them:

- Names and addresses are replaced everywhere, including in quoted text. They are taken from each message's own
  From, To, Cc and Bcc headers, so none are written into this script.
- Message IDs, dates and other identifying headers get fixed values.
- Each attachment is replaced by deterministic bytes of 1/1000 of its size, at least 100 bytes, so sizes keep their
  proportions. Structure, boundaries, Content-IDs and the text stay exactly as Mail wrote them.

It fails if any name, name part or address is still there afterwards.
"""

import base64
import email
import email.header
import email.policy
import email.utils
import hashlib
import pathlib
import quopri
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / 'probe' / 'test-results'
OUTPUT = ROOT / 'tests' / 'NextcloudAppleMailSharedTests' / 'Fixtures'

# Fixture name: the probe's saved message (see probe/docs/TESTS.md).
FIXTURES = {
    't15-first': '20261105-170130/54458-0020-call2-in.eml',
    't15-second': '20261105-170130/54458-0021-call3-in.eml',
    't20-first': '20261105-170130/54458-0042-call3-in.eml',
    't20-second': '20261105-170130/54458-0043-call4-in.eml',
    't27-second': '20261105-230344/67122-0004-call4-in.eml',
    't28-second': '20261105-230344/67122-0009-call5-in.eml',
    't29-first': '20261105-230344/67122-0012-call3-in.eml',
    't29-second': '20261105-230344/67122-0013-call4-in.eml',
    't30-first': '20261105-230344/67122-0017-call4-in.eml',
    't30-second': '20261105-230344/67122-0018-call5-in.eml',
    't34-first': '20261105-230344/67122-0026-call2-in.eml',
    't34-second': '20261105-230344/67122-0027-call3-in.eml',
}

ADDRESS_HEADERS = {'from', 'to', 'cc', 'bcc', 'reply-to', 'sender'}
FIXED_HEADERS = {
    'message-id': '<fixture@example.test>',
    'x-universally-unique-identifier': '00000000-0000-4000-8000-000000000001',
    'date': 'Thu, 5 Nov 2026 12:00:00 +0200',
    'x-apple-base-url': 'x-msg://1/',
    'x-apple-mail-signature': 'FIXTURE-SIGNATURE',
}
SENDER = ('Test Sender', 'sender@example.test')
RECIPIENT = ('Test Recipient', 'recipient@example.test')


def people(raw):
    """The names and addresses in a message's address headers, as (name, address) pairs."""
    message = email.message_from_bytes(raw, policy=email.policy.compat32)
    found = []
    for header in ADDRESS_HEADERS:
        for value in message.get_all(header, []):
            decoded = str(email.header.make_header(email.header.decode_header(value)))
            found += [(name, address) for name, address in email.utils.getaddresses([decoded]) if address]
    return found


def replacements(found):
    """Every spelling of each name and address that may appear in the raw message, mapped to its replacement."""
    names, addresses = {}, {}
    for name, address in found:
        sender = address == found[0][1]
        fake_name, fake_address = SENDER if sender else RECIPIENT
        addresses[address] = fake_address
        if name:
            names[name] = fake_name
    pairs = {}
    for real, fake in {**names, **addresses}.items():
        encoded = real.encode('utf-8')
        variants = {
            real,
            encoded.decode('latin-1'),
            quopri.encodestring(encoded).decode('ascii'),
            quopri.encodestring(encoded, header=True).decode('ascii'),
        }
        for variant in variants:
            pairs[variant] = fake
    return dict(sorted(pairs.items(), key=lambda item: -len(item[0])))


def payload(label, size):
    return hashlib.shake_256(label.encode()).digest(size)


def spanning_soft_breaks(text):
    """A pattern matching text even where quoted-printable soft line breaks split it."""
    return re.compile(''.join(re.escape(character) + r'(?:=\r?\n)?' for character in text))


def shrunk(encoded_lines, encoding, label, eol):
    """New body lines for an attachment: deterministic bytes of 1/1000 of its size, in the same encoding."""
    if encoding == 'base64':
        size = max(100, len(base64.b64decode(''.join(encoded_lines))) // 1000)
        return base64.encodebytes(payload(label, size)).decode('ascii').rstrip('\n').split('\n')
    size = max(100, len(quopri.decodestring(eol.join(encoded_lines).encode('latin-1'))) // 1000)
    return quopri.encodestring(payload(label, size)).decode('latin-1').rstrip('\n').split('\n')


def anonymise(raw, label, found):
    pairs = replacements(found)
    eol = '\r\n' if b'\r\n' in raw[:2000] else '\n'
    text = raw.decode('latin-1')
    lines = text.split(eol)
    # A quoted-printable body can have lines starting with "--", so only real boundaries end a part.
    boundaries = set(re.findall(r'boundary="?([^";\s]+)"?', text, re.IGNORECASE))
    delimiters = {f'--{b}' for b in boundaries} | {f'--{b}--' for b in boundaries}
    out = []
    in_headers = True
    is_top = True
    part_headers = []
    skipping = None
    index = 0
    while index < len(lines):
        line = lines[index]
        if in_headers:
            if line == '':
                in_headers = False
                is_top = False
                out.append(line)
                index += 1
                headers = ' '.join(part_headers).lower()
                named = 'filename' in headers or 'name=' in headers or 'name*' in headers
                encoding = 'base64' if 'base64' in headers else 'quoted-printable' if 'quoted-printable' in headers else None
                if named and encoding:
                    encoded = []
                    while index < len(lines) and lines[index].rstrip() not in delimiters:
                        encoded.append(lines[index])
                        index += 1
                    while encoded and encoded[-1] == '':
                        encoded.pop()
                    out += shrunk(encoded, encoding, f'{label}-{len(out)}', eol)
                    out.append('')
                part_headers = []
                continue
            name = line.split(':', 1)[0].lower() if not line[:1] in (' ', '\t') else None
            if name is not None:
                skipping = None
                part_headers.append(line)
                if is_top and name in FIXED_HEADERS:
                    out.append(f'{line.split(":", 1)[0]}: {FIXED_HEADERS[name]}')
                    skipping = name
                elif is_top and name in ADDRESS_HEADERS:
                    fake_name, fake_address = SENDER if name in ('from', 'sender', 'reply-to') else RECIPIENT
                    out.append(f'{line.split(":", 1)[0]}: {fake_name} <{fake_address}>')
                    skipping = name
                else:
                    out.append(line)
            elif skipping is None:
                part_headers.append(line)
                out.append(line)
            index += 1
            continue
        if line.rstrip() in delimiters and not line.rstrip().endswith('--'):
            in_headers = True
            part_headers = []
        out.append(line)
        index += 1
    result = eol.join(out)
    for real, fake in pairs.items():
        result = spanning_soft_breaks(real).sub(fake, result)
    result = re.sub(r'[A-Za-z0-9._%+-]+@(?!example\.test)[A-Za-z0-9.-]+\.[A-Za-z]{2,}', RECIPIENT[1], result)
    return result.encode('latin-1')


def leftovers(data, found):
    """Any real name, name part of four letters or more, or address still in the decoded message."""
    message = email.message_from_bytes(data, policy=email.policy.default)
    texts = [data.decode('latin-1')]
    for part in message.walk():
        if part.get_content_maintype() == 'text':
            texts.append(part.get_content())
    words = set()
    for name, address in found:
        words.add(address.lower())
        words.update(w.lower() for w in re.split(r'\W+', name) if len(w) >= 4)
    joined = '\n'.join(texts).lower()
    return sorted(word for word in words if word in joined)


def structure(data):
    message = email.message_from_bytes(data, policy=email.policy.default)
    return [(part.get_content_type(), part.get_filename(), part.get('Content-ID')) for part in message.walk()]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Quoted messages carry the names of earlier messages, so collect the people of every source first.
    sources = {label: (RESULTS / source).read_bytes() for label, source in FIXTURES.items()}
    found = []
    for raw in sources.values():
        found += [person for person in people(raw) if person not in found]
    failed = False
    for label, raw in sources.items():
        data = anonymise(raw, label, found)
        left = leftovers(data, found)
        same = structure(data) == structure(raw)
        (OUTPUT / f'{label}.eml').write_bytes(data)
        status = 'ok' if not left and same else 'FAILED'
        failed = failed or status != 'ok'
        print(f'{status:6} {label}.eml  {len(data):>7} bytes  structure kept: {same}  left over: {left or "none"}')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
