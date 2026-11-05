#!/usr/bin/env python3
"""Prints the MIME structure of messages: part types, dispositions, file names, Content-IDs and
the markers the real extension relies on. Files that match one in probe/test-files/ are named.

Usage: python3 probe/scripts/mime_tree.py <message.eml> [...] [--snippet N]

For each text part it counts <img src="cid:">, <object data="cid:">, quoted blocks
(type="cite"), U+FFFC placeholders and signature IDs, and shows the first N characters.
"""

import argparse
import email
import email.policy
import hashlib
import pathlib
import re

TEST_FILES = pathlib.Path(__file__).resolve().parents[1] / 'test-files'
KNOWN = {hashlib.sha256(p.read_bytes()).hexdigest(): p.name for p in TEST_FILES.glob('*') if p.is_file()}


def short(text, limit):
    text = re.sub(r'\s+', ' ', text)
    return text[:limit] + (' …' if len(text) > limit else '')


def show(path, snippet):
    data = path.read_bytes()
    message = email.message_from_bytes(data, policy=email.policy.default)
    defects = len(message.defects) + sum(len(p.defects) for p in message.walk())
    print(f'== {path.name}  {len(data)} bytes  defects={defects}  X-MailProbe={message["X-MailProbe"]!r}')

    def walk(part, depth):
        indent = '  ' * depth
        bits = [part.get_content_type()]
        if part.get_content_disposition():
            bits.append(f'[{part.get_content_disposition()}]')
        if part.get_filename():
            bits.append(f'file={part.get_filename()!r}')
        if part.get('Content-Id'):
            bits.append(f'cid={part["Content-Id"][:14]}…')
        if part.is_multipart():
            print(indent + ' '.join(bits))
            for child in part.iter_parts():
                walk(child, depth + 1)
            return
        payload = part.get_payload(decode=True) or b''
        if part.get_content_maintype() == 'text' and not part.get_filename():
            text = payload.decode(part.get_content_charset() or 'utf-8', 'replace')
            markers = {
                'chars': len(text),
                'img-cid': len(re.findall(r'<img[^>]*src="cid:', text)),
                'object-cid': len(re.findall(r'<object[^>]*cid:', text)),
                'cite': text.count('type="cite"'),
                'fffc': text.count('￼'),
                'signature': re.findall(r'(?:class|id)="[^"]*[Ss]ignature[^"]*"', text)[:3],
            }
            print(indent + ' '.join(bits), markers)
            if snippet:
                print(indent + '   > ' + short(text, snippet))
        else:
            digest = hashlib.sha256(payload).hexdigest()
            match = f'matches {KNOWN[digest]}' if digest in KNOWN else f'sha256 {digest[:10]}'
            print(indent + ' '.join(bits), f'{len(payload)}B', match)

    walk(message, 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('messages', nargs='+', type=pathlib.Path)
    parser.add_argument('--snippet', type=int, default=160, help='characters of each text part to show, 0 for none')
    args = parser.parse_args()
    for path in args.messages:
        show(path, args.snippet)


if __name__ == '__main__':
    main()
