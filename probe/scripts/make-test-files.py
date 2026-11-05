#!/usr/bin/env python3
"""Creates dummy mail attachments in test-files/.

Content is deterministic, so rerunning the script gives byte-identical files.
Sizes are decimal megabytes, matching what Finder and Mail display.

The .bin files are plain attachments. The PDF and PNG are valid documents because
Mail shows those inline, which gives the message a different MIME structure.
"""

import hashlib
import pathlib
import struct
import zlib

MB = 1_000_000
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / "test-files"


def noise(label, size):
    return hashlib.shake_256(label.encode()).digest(size)


def png_chunk(kind, payload):
    crc = zlib.crc32(kind + payload)
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def make_png(size):
    side = 560
    row_bytes = side * 3
    pixels = noise("png", row_bytes * side)
    rows = b"".join(b"\x00" + pixels[i : i + row_bytes] for i in range(0, len(pixels), row_bytes))
    head = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 2, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(rows, 1))
    )
    tail = png_chunk(b"IEND", b"")
    keyword = b"Comment\x00"
    padding = size - len(head) - len(tail) - 12 - len(keyword)
    if padding < 0:
        raise ValueError(f"PNG base is larger than {size} bytes")
    return head + png_chunk(b"tEXt", keyword + b"x" * padding) + tail


def build_pdf(padding):
    text = b"BT /F1 24 Tf 72 720 Td (MailProbe dummy PDF) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        b"/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>",
        b"<< /Length %d >>\nstream\n%s\nendstream" % (len(text), text),
        b"<< /Length %d >>\nstream\n%s\nendstream" % (padding, noise("pdf", padding)),
    ]
    output = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(output))
        output += b"%d 0 obj\n%s\nendobj\n" % (number, body)
    xref = len(output)
    output += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        output += b"%010d 00000 n \n" % offset
    output += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    return bytes(output)


def make_pdf(size):
    padding = 0
    while True:
        document = build_pdf(padding)
        if len(document) == size:
            return document
        padding += size - len(document)


def main():
    OUTPUT.mkdir(exist_ok=True)
    files = {
        "dummy-1MB.bin": noise("bin-1", 1 * MB),
        "dummy-5MB.bin": noise("bin-5", 5 * MB),
        "dummy-10MB.bin": noise("bin-10", 10 * MB),
        "dummy-30MB.bin": noise("bin-30", 30 * MB),
        "dummy-1MB.pdf": make_pdf(1 * MB),
        "dummy-5MB.pdf": make_pdf(5 * MB),
        "dummy-10MB.pdf": make_pdf(10 * MB),
        "dummy-1MB.png": make_png(1 * MB),
        "dummy-5MB.png": make_png(5 * MB),
        "dummy-10MB.png": make_png(10 * MB),
    }
    for name, content in files.items():
        (OUTPUT / name).write_bytes(content)
        print(f"{name:16} {len(content):>10} bytes  sha256 {hashlib.sha256(content).hexdigest()[:16]}")


if __name__ == "__main__":
    main()
