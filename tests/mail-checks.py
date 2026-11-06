#!/usr/bin/env python3
"""Runs the send flow's Mail checks between the two accounts in .env, through scripts/mail.sh (docs/TESTING.md).

Usage: python3 tests/mail-checks.py [check ...]     with no names, every check runs. --list lists them.

Each check sets the app's settings, sends a message with files from account A to account B, waits for it in B's
inbox and A's Sent mailbox, and checks what arrived: which files stayed attached and which became links, that each
link downloads the original bytes, that the all-files links give a zip of exactly the linked files, and that the
Sent copy matches. Files and messages go in test-results/mail/<run>/, which git ignores. The settings are put back
at the end. Needs the installed Debug build, Sign on in Mail, and the permissions in docs/TESTING.md.
"""

import email
import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import unicodedata
import zipfile
from email import policy

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIL = str(ROOT / 'scripts' / 'mail.sh')

# name: settings, files as (name, size) with None for the same file again, the files expected to stay attached,
# whether A's signature is kept, and what the all-files links should be.
CHECKS = {
    'folder-in-place': dict(files=[('notes.txt', 20_000), ('data.bin', 300_000)]),
    'folder-only': dict(settings={'placement': 'folderLinksOnly'}, files=[('a.txt', 8_000), ('b.bin', 50_000)],
                        folder_links=True),
    'each-file': dict(settings={'sharing': 'eachFile', 'folderLinks': True},
                      files=[('first.bin', 30_000), ('second.bin', 40_000)], folder_links=True),
    'download-only': dict(settings={'linkStyle': 'downloadOnly'}, files=[('report.bin', 25_000)]),
    'size-rule': dict(settings={'onlyLargeFiles': True, 'sizeLimitMegabytes': 0.2},
                      files=[('small.txt', 50_000), ('large.bin', 400_000)], kept=['small.txt']),
    'odd-names': dict(files=[('Pārskats #1 100%.txt', 5_000), ('a&b+c [1].txt', 5_000)]),
    'same-file-twice': dict(files=[('twice.bin', 10_000), None]),
    'signature': dict(files=[('with-signature.bin', 10_000)], signature=True),
    'large': dict(files=[('large-12MB.bin', 12_000_000)]),
    # B replies to A's message with a new file (t34). The file goes after the quote, where AppleScript adds it.
    'reply': dict(respond='reply', files=[('reply.bin', 20_000)]),
    # B forwards A's message, whose small file stayed attached under the size rule, with every file becoming a
    # link (t20). The forward's file is the original's.
    'forward': dict(respond='forward', original_settings={'onlyLargeFiles': True, 'sizeLimitMegabytes': 0.2},
                    files=[('forwarded.txt', 30_000)]),
}

DEFAULTS = {'sharing': 'folder', 'placement': 'whereEachFileWas', 'linkStyle': 'viewAndDownload',
            'folderLinks': False, 'onlyLargeFiles': False, 'pastedImagesBecomeLinks': True, 'warningPhrases': []}


def mail(*arguments, capture=False):
    result = subprocess.run([MAIL, *arguments], check=True, capture_output=capture, text=True)
    return result.stdout


def app_settings(changes=None):
    arguments = ['app', '--settings'] + ([json.dumps(changes)] if changes is not None else [])
    return json.loads(mail(*arguments, capture=True))


def curl(url, *options):
    return subprocess.run(['curl', '-sS', '-L', *options, url], check=True, capture_output=True).stdout


def status(url):
    return int(curl(url, '-o', '/dev/null', '-w', '%{http_code}'))


def folder_name(name):
    """The name a file gets in a shared folder (NextcloudNames.folderShareName)."""
    return re.sub(r'[#%?]', '_', name)


def make_files(folder, files):
    """Writes the check's files, random bytes or for .txt random text, and returns (name, path) for each."""
    folder.mkdir(parents=True, exist_ok=True)
    made = []
    for item in files:
        if item is None:
            made.append(made[-1])
            continue
        name, size = item
        path = folder / name
        data = os.urandom(size)
        if name.endswith('.txt'):
            data = data.hex().encode()[:size]
        path.write_bytes(data)
        made.append((name, path))
    return made


def parts(raw):
    message = email.message_from_bytes(raw, policy=policy.default)
    texts = {'plain': [], 'html': []}
    attached = {}
    for part in message.walk():
        if part.get_filename():
            attached[nfc(part.get_filename())] = part.get_payload(decode=True) or b''
        elif part.get_content_type() == 'text/plain':
            texts['plain'].append(part.get_content())
        elif part.get_content_type() == 'text/html':
            texts['html'].append(part.get_content())
    return texts, attached


def nfc(name):
    """Names compared as composed Unicode: Mail sends a file's name as macOS stores it, often decomposed (NFD)."""
    return unicodedata.normalize('NFC', name)


def links(plain):
    """Each file's links in the plain text, the files listed without links, and the all-files links."""
    plain = nfc(plain)
    found = {}
    for match in re.finditer(r'^([^\n]+) \([^()\n]*\)\nView: (https://\S+)\nDownload: (https://\S+)$', plain, re.M):
        found[match[1]] = {'view': match[2], 'download': match[3]}
    for match in re.finditer(r'^([^\n]+) \([^()\n]*\): (https://\S+)$', plain, re.M):
        found[match[1]] = {'download': match[2]}
    listed = [match[1] for match in re.finditer(r'^([^\n:]+) \([^()\n]*link expires[^()\n]*\)$', plain, re.M)]
    listed += [match[1] for match in re.finditer(r'^([^\n:]+) \(\d[^()\n]*(?:bytes?|KB|MB|GB)\)$', plain, re.M)]
    folder = {}
    for label, key in (('View all files in email', 'view'), ('Download all files in email', 'download')):
        match = re.search(rf'^{label}: (https://\S+)$', plain, re.M)
        if match:
            folder[key] = match[1]
    return found, [name for name in listed if name not in found], folder


def run_check(name, check, run_folder, stamp):
    results = []

    def expect(what, ok, detail=''):
        results.append((what, bool(ok), detail))

    folder = run_folder / name
    settings = dict(DEFAULTS, **check.get('settings', {}))
    files = make_files(folder / 'files', check['files'])
    subject = f'[ncam check] {name} {stamp}'
    respond = check.get('respond')
    if respond:
        # The original: with the forward's file attached, kept by its own settings, and none for a reply.
        app_settings(dict(DEFAULTS, **check.get('original_settings', {})))
        original_files = [str(path) for _, path in files] if respond == 'forward' else []
        mail('send', 'A', 'B', subject, f'Check {name}: the original.', 'none', *original_files)
        mail('fetch', 'inbox', subject, str(folder / 'original.eml'), '300')
        app_settings(settings)
        started = time.time()
        added = [] if respond == 'forward' else [str(path) for _, path in files]
        mail('respond', respond, subject, 'A', *added)
        subject = ('Fwd: ' if respond == 'forward' else 'Re: ') + subject
    else:
        app_settings(settings)
        started = time.time()
        mail('send', 'A', 'B', subject, f'Check {name}: text above the files.',
             'signature' if check.get('signature') else 'none', *[str(path) for _, path in files])
    received_path, sent_path = folder / 'received.eml', folder / 'sent.eml'
    mail('fetch', 'inbox', subject, str(received_path), '300')
    took = time.time() - started
    mail('fetch', 'sent', subject, str(sent_path), '120')
    received, sent = received_path.read_bytes(), sent_path.read_bytes()
    texts, attached = parts(received)
    sent_texts, sent_attached = parts(sent)
    plain = '\n'.join(texts['plain'])
    file_links, listed, folder_links = links(plain)
    kept = set(check.get('kept', []))
    each_file = settings['sharing'] == 'eachFile'
    only_folder = settings['sharing'] == 'folder' and settings['placement'] == 'folderLinksOnly'

    expect('arrived', True, f'{took:.0f} s after sending')
    unique = {original: path for original, path in files}
    expected_attached = set(kept) | ({'Screenshot 2026-11-05 at 22.00.04.png'} if check.get('signature') else set())
    expect('the right files stayed attached', set(attached) == expected_attached, f'attached: {sorted(attached)}')
    for original in kept:
        expect(f'{original} stayed byte for byte', attached.get(original) == unique[original].read_bytes())
    linked = [original for original in unique if original not in kept]
    for original in linked:
        shown = original if each_file else folder_name(original)
        data = unique[original].read_bytes()
        if only_folder:
            expect(f'{shown} is listed without links', shown in listed and shown not in file_links, f'listed: {listed}')
            continue
        link = file_links.get(shown)
        expect(f'{shown} has its links', link is not None, f'links for: {sorted(file_links)}')
        if not link:
            continue
        got = curl(link['download'])
        expect(f'{shown} downloads the same bytes', got == data, f'{len(got)} of {len(data)} bytes')
        if 'view' in link:
            expect(f'{shown} view link opens', status(link['view']) == 200)
    if not only_folder and len(linked) > 1 and settings['linkStyle'] == 'viewAndDownload':
        views = {file_links[name]['view'] for name in file_links}
        expect('view links: one per file' if each_file else 'view links: all the folder\'s page',
               len(views) == (len(linked) if each_file else 1), f'{len(views)} different')
    if check.get('folder_links'):
        expect('all-files links are there', set(folder_links) == {'view', 'download'}, f'found: {sorted(folder_links)}')
        if 'download' in folder_links:
            archive = zipfile.ZipFile(io.BytesIO(curl(folder_links['download'])))
            names = sorted(nfc(pathlib.PurePosixPath(entry).name) for entry in archive.namelist()
                           if not entry.endswith('/'))
            wanted = sorted(original if each_file else folder_name(original) for original in linked)
            expect('the zip holds exactly the linked files', names == wanted, f'zip: {names}')
    else:
        expect('no all-files links', not folder_links, f'found: {sorted(folder_links)}')
    if name == 'same-file-twice':
        downloads = [link['download'] for link in file_links.values()]
        expect('one upload for the file attached twice', len(set(downloads)) == 1, f'{len(set(downloads))} uploads')
    expect('the Sent copy shows the same text', [t.strip() for t in sent_texts['plain']] == [t.strip() for t in texts['plain']])
    expect('the Sent copy has the same files', {k: hashlib.sha256(v).hexdigest() for k, v in sent_attached.items()}
           == {k: hashlib.sha256(v).hexdigest() for k, v in attached.items()})
    return results


def main():
    if '--list' in sys.argv:
        print('\n'.join(CHECKS))
        return 0
    names = [name for name in sys.argv[1:]] or list(CHECKS)
    unknown = [name for name in names if name not in CHECKS]
    if unknown:
        print(f'unknown checks: {", ".join(unknown)}. --list lists them.', file=sys.stderr)
        return 2
    stamp = time.strftime('%H%M%S')
    run_folder = ROOT / 'test-results' / 'mail' / time.strftime('%Y%m%d-%H%M%S')
    original = app_settings()
    failed = 0
    try:
        for name in names:
            print(f'== {name}', flush=True)
            try:
                results = run_check(name, CHECKS[name], run_folder, stamp)
            except subprocess.CalledProcessError as error:
                results = [('ran', False, (error.stderr or str(error)).strip())]
            for what, ok, detail in results:
                failed += not ok
                print(f'  {"ok  " if ok else "FAIL"} {what}' + (f' ({detail})' if detail and not ok or what == 'arrived' else ''),
                      flush=True)
    finally:
        app_settings(original)
    print(f'{"all passed" if not failed else f"{failed} failed"}. Messages are in {run_folder.relative_to(ROOT)}/')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
