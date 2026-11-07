#!/usr/bin/env python3
"""Runs the Mail checks that need Mail's windows, through AppleScript and System Events (docs/TESTING.md).

Usage: python3 tests/mail-window-checks.py [check ...]     with no names, every check runs. --list lists them.

These are T5c's checks: an upload failure's alert (t7), Undo Send (t21), Send Later (t22), a pasted image (t30),
a reply's quote (t34), and Mail Drop's prompt with Try Sending in Email (t38) and Use Mail Drop (t39), and T6's: a
password typed in the toolbar popover (t36), kept through a reopened draft (t37), refused by the server's policy, and
required by the server, which password-required switches on for the check and off again (D18). They click
Mail's Send button, menus and alert buttons, so the terminal's app needs Accessibility, and Mail must be the app in
front whenever a key is pressed: each check makes sure of that first, and stops if it can't. "Don't ask again" in
the Mail Drop prompt is never ticked (R2). Messages go between the two accounts in .env, as tests/mail-checks.py's do,
and are saved in test-results/mail/<run>/.
"""

import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location('mail_checks', ROOT / 'tests' / 'mail-checks.py')
checks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(checks)


class CheckError(Exception):
    pass


def osa(script, *arguments, timeout=180):
    result = subprocess.run(['osascript', '-', *arguments], input=script, capture_output=True, text=True,
                            timeout=timeout)
    if result.returncode:
        raise CheckError(result.stderr.strip())
    return result.stdout.strip()


def in_mail(body, *arguments, timeout=180):
    """Runs AppleScript lines inside System Events' process "Mail", with argv for the arguments."""
    return osa('on run argv\ntell application "System Events" to tell process "Mail"\n' + body
               + '\nend tell\nend run', *arguments, timeout=timeout)


def mail_in_front():
    """Brings Mail to the front, or stops: keys must never go to another app."""
    osa('tell application "Mail" to activate')
    for _ in range(20):
        if osa('tell application "System Events" to get name of first process whose frontmost is true') == 'Mail':
            return
        time.sleep(0.25)
    raise CheckError('Mail did not come to the front, so no key was pressed')


def window_exists(name):
    return in_mail('return exists window (item 1 of argv)', name) == 'true'


def wait(condition, seconds, what):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return
        time.sleep(0.5)
    raise CheckError(f'{what} after {seconds} seconds')


def click_send(subject):
    mail_in_front()
    in_mail('perform action "AXRaise" of window (item 1 of argv)\n'
            'click (first button of toolbar 1 of window (item 1 of argv) whose description is "Send")', subject)


def sheet(subject):
    """The texts and buttons of the sheet on a window, or None, also when the window has closed meanwhile."""
    try:
        if in_mail('return count of sheets of window (item 1 of argv)', subject) == '0':
            return None
        texts = in_mail('return value of every static text of sheet 1 of window (item 1 of argv)', subject)
        buttons = in_mail('return name of every button of sheet 1 of window (item 1 of argv)', subject)
    except CheckError:
        if not window_exists(subject):
            return None
        raise
    return texts, [name.strip() for name in buttons.split(',')]


def click_sheet_button(subject, button):
    in_mail('click button (item 2 of argv) of sheet 1 of window (item 1 of argv)', subject, button)


def click_menu(*path):
    """Clicks a menu item, such as ("Message", "Send Later", "Send 21:00 Tonight")."""
    mail_in_front()
    reference = f'menu "{path[0]}" of menu bar 1'
    for name in path[1:-1]:
        reference = f'menu 1 of menu item "{name}" of {reference}'
    in_mail(f'click menu item "{path[-1]}" of {reference}')


def menu_items(*path):
    reference = f'menu "{path[0]}" of menu bar 1'
    for name in path[1:]:
        reference = f'menu 1 of menu item "{name}" of {reference}'
    return [name.strip() for name in in_mail(f'return name of every menu item of {reference}').split(',')]


def env():
    values = {}
    for line in (ROOT / '.env').read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            values[key] = value.strip().strip('"')
    return values


def folders_for(subject):
    """The names of the email folders on Nextcloud that end with the subject."""
    values = env()
    url = (f'{values["NCME_TEST_SERVER_URL"]}/remote.php/dav/files/{values["NCME_TEST_USERNAME"]}/'
           f'{urllib.parse.quote(values["NCME_TEST_DIRECTORY"])}/')
    listing = subprocess.run(['curl', '-sS', '-u', f'{values["NCME_TEST_USERNAME"]}:{values["NCME_TEST_PASSWORD"]}',
                              '-X', 'PROPFIND', '-H', 'Depth: 1', url], capture_output=True, text=True, check=True)
    names = [urllib.parse.unquote(href).rstrip('/').split('/')[-1] for href in re.findall(r'<d:href>([^<]*)</d:href>',
                                                                                         listing.stdout)]
    return [name for name in names if name.endswith(subject)]


def file_links(path):
    texts, attached = checks.parts(path.read_bytes())
    found, _, _ = checks.links('\n'.join(texts['plain']))
    return texts, attached, found


def downloads_match(found, name, data):
    link = found.get(name)
    return link is not None and checks.curl(link['download']) == data


def png(width=64, height=48):
    """A small PNG with a gradient, written without packages."""
    raw = b''.join(b'\x00' + b''.join(bytes((x * 4 % 256, y * 5 % 256, (x * y) % 256)) for x in range(width))
                   for y in range(height))

    def chunk(kind, data):
        return len(data).to_bytes(4, 'big') + kind + data + zlib.crc32(kind + data).to_bytes(4, 'big')
    header = width.to_bytes(4, 'big') + height.to_bytes(4, 'big') + bytes((8, 2, 0, 0, 0))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


class Run:
    def __init__(self):
        self.stamp = time.strftime('%H%M%S')
        self.folder = ROOT / 'test-results' / 'mail' / time.strftime('%Y%m%d-%H%M%S-windows')
        self.folder.mkdir(parents=True, exist_ok=True)
        self.original = checks.app_settings()
        self.results = []

    def expect(self, what, ok, detail=''):
        self.results.append((what, bool(ok), detail))

    def subject(self, name):
        return f'[ncme check] {name} {self.stamp}'

    def file(self, name, size):
        path = self.folder / name
        path.write_bytes(os.urandom(size))
        return path

    def fetch(self, subject, name, seconds=300):
        path = self.folder / name
        checks.mail('fetch', 'inbox', subject, str(path), str(seconds))
        return path


def check_t7(run):
    """An upload failure: the alert has the server's reason, the window keeps its file, and sending again works."""
    subject = run.subject('t7-failure')
    data_path = run.file('t7.bin', 4000)
    checks.app_settings(dict(checks.DEFAULTS, directory=run.original['directory'] + '/.htaccess'))
    checks.mail('compose', 'A', 'B', subject, 'Check t7: the first send stops.', 'none', str(data_path))
    click_send(subject)
    wait(lambda: sheet(subject) is not None, 90, 'no alert')
    texts, buttons = sheet(subject)
    run.expect('the alert names the failure and the server\'s reason', 'couldn\'t' in texts and 'Nextcloud:' in texts,
               texts)
    click_sheet_button(subject, 'OK')
    time.sleep(1)
    run.expect('the window stays open', window_exists(subject))
    checks.app_settings(dict(checks.DEFAULTS, directory=run.original['directory']))
    click_send(subject)
    _, attached, found = file_links(run.fetch(subject, 't7-received.eml'))
    run.expect('sending again uploads and links the file', downloads_match(found, 't7.bin', data_path.read_bytes())
               and not attached, f'links for: {sorted(found)}')


def undo_send():
    """Clicks Edit > Undo Send once Mail offers it. Opening the menu makes Mail update its items."""
    for _ in range(16):
        mail_in_front()
        name = in_mail('click menu bar item "Edit" of menu bar 1\ndelay 0.3\n'
                       'set first_ to name of menu item 1 of menu "Edit" of menu bar item "Edit" of menu bar 1\n'
                       'if first_ starts with "Undo Send" then\n'
                       'click menu item 1 of menu "Edit" of menu bar item "Edit" of menu bar 1\nelse\nkey code 53\n'
                       'end if\nreturn first_')
        if name.startswith('Undo Send'):
            return True
        time.sleep(0.5)
    return False


def check_t21(run):
    """Undo Send: the window comes back with its file, and sending again reuses the upload."""
    subject = run.subject('t21-undo')
    data_path = run.file('t21.bin', 6000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check t21: undone, then sent again.', 'none', str(data_path))
    click_send(subject)
    wait(lambda: not window_exists(subject), 90, 'the window didn\'t close after Send')
    undone = undo_send()
    run.expect('Mail offered Undo Send', undone)
    if not undone:
        return
    wait(lambda: window_exists(subject), 15, 'the window didn\'t come back after Undo Send')
    run.expect('the window came back', True)
    click_send(subject)
    _, attached, found = file_links(run.fetch(subject, 't21-received.eml'))
    run.expect('the email arrived once sent again, with working links',
               downloads_match(found, 't21.bin', data_path.read_bytes()) and not attached)
    folders = folders_for(subject)
    run.expect('one folder on Nextcloud for both sends', len(folders) == 1, f'folders: {folders}')


def check_t22(run):
    """Send Later: the files are uploaded when the email is scheduled, and the scheduled copy has the links."""
    subject = run.subject('t22-send-later')
    data_path = run.file('t22.bin', 5000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check t22: sent later, tonight.', 'none', str(data_path))
    mail_in_front()
    in_mail('perform action "AXRaise" of window (item 1 of argv)', subject)
    tonight = [item for item in menu_items('Message', 'Send Later') if 'Tonight' in item]
    run.expect('Mail offers to send tonight', tonight, f'items: {menu_items("Message", "Send Later")}')
    if not tonight:
        return
    click_menu('Message', 'Send Later', tonight[0])
    # The first time, Mail confirms with a sheet that the message goes out at the scheduled time.
    wait(lambda: not window_exists(subject) or sheet(subject) is not None, 90, 'nothing after Send Later')
    confirmation = sheet(subject)
    if confirmation and 'OK' in confirmation[1]:
        click_sheet_button(subject, 'OK')
    wait(lambda: not window_exists(subject), 90, 'the window didn\'t close after Send Later')
    folders = folders_for(subject)
    run.expect('the file was uploaded when the email was scheduled', len(folders) == 1, f'folders: {folders}')
    source = osa('on run argv\ntell application "Mail"\nset found to (messages of mailbox "SendLater" '
                 'whose subject is (item 1 of argv))\nif (count of found) > 0 then return source of item 1 of found\n'
                 'return ""\nend tell\nend run', subject)
    if source:
        path = run.folder / 't22-scheduled.eml'
        path.write_text(source)
        _, attached, found = file_links(path)
        run.expect('the scheduled copy has working links', downloads_match(found, 't22.bin', data_path.read_bytes())
                   and not attached, f'links for: {sorted(found)}')
    else:
        run.expect('the scheduled copy was found in a mailbox', False, 'not found; it goes out tonight')


FOCUS_WEB_AREA = """
on walk(element, depth)
    tell application "System Events"
        set kids to {}
        try
            set kids to UI elements of element
        end try
        repeat with kid in kids
            set r to ""
            try
                set r to role of kid
            end try
            if r is "AXWebArea" then return kid
            if depth < 6 then
                set found to my walk(kid, depth + 1)
                if found is not missing value then return found
            end if
        end repeat
    end tell
    return missing value
end walk

on run argv
    tell application "System Events" to tell process "Mail" to set target to window (item 1 of argv)
    set area to my walk(target, 1)
    tell application "System Events" to set value of attribute "AXFocused" of area to true
end run
"""


def paste_into_body(subject, at_end):
    """Pastes the clipboard into the message body, at its end or where the caret starts, which in a reply is above
    the quote. A click doesn't move the keyboard focus there reliably, so Accessibility gives the body the focus."""
    mail_in_front()
    in_mail('perform action "AXRaise" of window (item 1 of argv)', subject)
    osa(FOCUS_WEB_AREA, subject, timeout=300)
    mail_in_front()
    if at_end:
        osa('tell application "System Events" to key code 125 using command down')
    osa('tell application "System Events" to keystroke "v" using command down')
    time.sleep(2)


def close_test_windows():
    """Closes test messages left open by an earlier check, without saving them."""
    names = [name.strip() for name in in_mail('return name of every window').split(',')]
    for name in names:
        if '[ncme check]' not in name:
            continue
        mail_in_front()
        try:
            in_mail('set w to window (item 1 of argv)\nperform action "AXRaise" of w\n'
                    'click (first button of w whose subrole is "AXCloseButton")\ndelay 1.5\n'
                    'if (count of sheets of w) > 0 then click button "Don’t Save" of sheet 1 of w', name)
        except CheckError:
            continue  # gone already


def check_t30(run):
    """A pasted image: with the pasted-images setting on, it becomes links, named as Mail names it."""
    subject = run.subject('t30-pasted')
    image = run.folder / 'pasted.png'
    image.write_bytes(png())
    checks.app_settings(checks.DEFAULTS)
    saved = subprocess.run(['pbpaste'], capture_output=True).stdout
    try:
        checks.mail('compose', 'A', 'B', subject, 'Check t30: an image pasted below.', 'none')
        osa('on run argv\nset the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)\nend run',
            str(image))
        paste_into_body(subject, at_end=True)
        click_send(subject)
    finally:
        subprocess.run(['pbcopy'], input=saved)
    texts, attached, found = file_links(run.fetch(subject, 't30-received.eml'))
    pasted = [name for name in found if name.startswith('PastedGraphic')]
    run.expect('the pasted image became links', pasted and not attached,
               f'links for: {sorted(found)}, attached: {sorted(attached)}')
    if pasted:
        run.expect('its link downloads a PNG', checks.curl(found[pasted[0]]['download']).startswith(b'\x89PNG'))


def check_t34(run):
    """A reply made in Mail's window keeps its quote, and a file added above the quote gets its links there."""
    subject = run.subject('t34-reply')
    checks.app_settings(checks.DEFAULTS)
    checks.mail('send', 'A', 'B', subject, 'Check t34: the original, to be quoted.', 'none')
    run.fetch(subject, 't34-original.eml')
    osa('on run argv\ntell application "Mail"\nset m to first message of inbox whose subject is (item 1 of argv)\n'
        'set selected mailboxes of message viewer 1 to {mailbox of m}\ndelay 1\n'
        'set selected messages of message viewer 1 to {m}\nend tell\nend run', subject)
    mail_in_front()
    in_mail('perform action "AXRaise" of (first window whose name starts with "Inbox")')
    click_menu('Message', 'Reply')
    reply = 'Re: ' + subject
    wait(lambda: window_exists(reply), 30, 'no reply window')
    data_path = run.file('t34.bin', 7000)
    # AppleScript can't reach a reply made in Mail's window, so the file is pasted above the quote instead.
    saved = subprocess.run(['pbpaste'], capture_output=True).stdout
    try:
        osa('on run argv\nset the clipboard to (POSIX file (item 1 of argv))\nend run', str(data_path))
        paste_into_body(reply, at_end=False)
        click_send(reply)
    finally:
        subprocess.run(['pbcopy'], input=saved)
    texts, attached, found = file_links(run.fetch(reply, 't34-received.eml'))
    plain = '\n'.join(texts['plain'])
    run.expect('the reply has its quote', 'Check t34: the original' in plain and '>' in plain)
    link = plain.find('t34.bin (')
    quote = plain.find('\n>')
    run.expect('the links are above the quote', 0 <= link < quote, f'link at {link}, quote at {quote}')
    run.expect('the links work', downloads_match(found, 't34.bin', data_path.read_bytes()) and not attached)


def mail_drop(run, name, button):
    subject = run.subject(name)
    data_path = run.file(f'{name}.bin', 30_000_000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, f'Check {name}: over the size limit.', 'none', str(data_path))
    click_send(subject)
    wait(lambda: sheet(subject) is not None, 120, 'no Mail Drop prompt')
    texts, buttons = sheet(subject)
    run.expect('Mail asked about Mail Drop', button in buttons, f'buttons: {buttons}')
    ticked = in_mail('return value of every checkbox of sheet 1 of window (item 1 of argv)', subject)
    run.expect('"Don\'t ask again" is not ticked', '1' not in ticked.split(', '), f'checkboxes: {ticked}')
    if button not in buttons or '1' in ticked.split(', '):
        return subject, data_path, None
    click_sheet_button(subject, button)
    return subject, data_path, run.fetch(subject, f'{name}-received.eml', 900)


def check_t38(run):
    """Try Sending in Email: the extension uploads as usual, and the email is small."""
    subject, data_path, received = mail_drop(run, 't38-try-in-email', 'Try Sending in Email')
    if received:
        _, attached, found = file_links(received)
        run.expect('the 30 MB file became working links', downloads_match(found, 't38-try-in-email.bin',
                                                                           data_path.read_bytes()) and not attached)
        run.expect('the email is small', received.stat().st_size < 100_000, f'{received.stat().st_size} bytes')


def check_t39(run):
    """Use Mail Drop: the email has Mail Drop's link, and what was uploaded for it is deleted from Nextcloud."""
    subject, _, received = mail_drop(run, 't39-mail-drop', 'Use Mail Drop')
    if received:
        raw = received.read_bytes()
        server = env()['NCME_TEST_SERVER_URL'].encode()
        run.expect('the email has Mail Drop\'s link', b'Remote-Attachment-Url' in raw or b'icloud.com' in raw)
        run.expect('the email has no Nextcloud links', server not in raw)
        time.sleep(10)
        run.expect('nothing uploaded for it is left on Nextcloud', not folders_for(subject),
                   f'folders: {folders_for(subject)}')


# MARK: Passwords (FR7, T6)

def type_password(subject, password):
    """Types the email's password in the toolbar popover, replacing what's there, and closes the popover."""
    mail_in_front()
    in_mail('click (first button of toolbar 1 of window (item 1 of argv) whose description is "NextcloudMailExtension")',
            subject)
    field = ('text field 1 of group 1 of pop over 1 of (first button of toolbar 1 of window (item 1 of argv) '
             'whose description is "NextcloudMailExtension")')
    wait(lambda: in_mail(f'return exists {field}', subject) == 'true', 15, 'no password field in the popover')
    in_mail(f'set value of attribute "AXFocused" of {field} to true', subject)
    mail_in_front()
    osa('tell application "System Events" to keystroke "a" using command down')
    osa('tell application "System Events" to key code 51')
    if password:
        osa('on run argv\ntell application "System Events" to keystroke (item 1 of argv)\nend run', password)
    time.sleep(0.5)
    osa('tell application "System Events" to key code 53')
    time.sleep(0.5)


def password_protected(received, name, data, password):
    """Whether the file's download link shows the password page, and the file comes with the password."""
    _, attached, found = file_links(received)
    link = found.get(name)
    if not link or attached:
        return False, f'links for: {sorted(found)}, attached: {sorted(attached)}'
    page = checks.curl(link['download'])
    token = re.search(r'/s/([^/?]+)', link['download'])[1]
    server = env()['NCME_TEST_SERVER_URL']
    dav = f'{server}/public.php/dav/files/{token}/{urllib.parse.quote(name)}'
    if '?files=' not in link['download']:
        dav = f'{server}/public.php/dav/files/{token}'
    with_password = checks.curl(dav, '-u', f'anonymous:{password}')
    return page != data and b'<html' in page.lower() and with_password == data, (
        f'without: {len(page)} bytes of {"HTML" if b"<html" in page.lower() else "data"}, with: {len(with_password)}')


def check_t36(run):
    """A password typed in the popover protects every link, and the email doesn't contain it (t36)."""
    subject = run.subject('t36-password')
    password = 'ncme-' + os.urandom(6).hex()
    data_path = run.file('t36.bin', 5000)
    checks.app_settings(dict(checks.DEFAULTS, folderLinks=True))
    second = run.file('t36-second.bin', 3000)
    checks.mail('compose', 'A', 'B', subject, 'Check t36: links with a password.', 'none', str(data_path),
                str(second))
    type_password(subject, password)
    click_send(subject)
    received = run.fetch(subject, 't36-received.eml')
    ok, detail = password_protected(received, 't36.bin', data_path.read_bytes(), password)
    run.expect('the file\'s link needs the password, and works with it', ok, detail)
    texts, _, _ = file_links(received)
    body = '\n'.join(texts['plain'] + texts['html'])
    _, _, folder = checks.links('\n'.join(texts['plain']))
    run.expect('the all-files link needs the password too',
               'download' in folder and b'<html' in checks.curl(folder['download']).lower())
    run.expect('the email says a password is needed', 'The links need a password' in body)
    run.expect('the email doesn\'t contain the password', password not in body and password.encode() not in
               received.read_bytes())


OPEN_ROW = """
on rowTexts(element)
    tell application "System Events"
        set found to ""
        set kids to {}
        try
            set kids to UI elements of element
        end try
        repeat with kid in kids
            try
                if role of kid is "AXStaticText" then set found to found & (value of kid as text) & " "
            end try
            set found to found & my rowTexts(kid)
        end repeat
        return found
    end tell
end rowTexts

on findRow(element, subject, depth)
    tell application "System Events"
        set kids to {}
        try
            set kids to UI elements of element
        end try
        repeat with kid in kids
            set r to ""
            try
                set r to role of kid
            end try
            if r is "AXRow" then
                if my rowTexts(kid) contains subject then return kid
            else if depth < 8 then
                set found to my findRow(kid, subject, depth + 1)
                if found is not missing value then return found
            end if
        end repeat
    end tell
    return missing value
end findRow

on run argv
    tell application "System Events" to tell process "Mail" to set w to (first window whose name starts with "Drafts")
    set target to my findRow(w, item 1 of argv, 1)
    if target is missing value then error "No row for the draft."
    tell application "System Events"
        set value of attribute "AXSelected" of target to true
        delay 1
        tell process "Mail" to click (first menu item of menu "File" of menu bar 1 whose name contains "Open")
    end tell
end run
"""


def reopen_draft(subject, account):
    """Opens a saved draft again for editing, as a person would: its row in the Drafts list, then File > Open.
    Selecting it through AppleScript alone doesn't reliably select the row Mail opens."""
    osa('on run argv\ntell application "Mail"\nset selected mailboxes of message viewer 1 to '
        '{mailbox "Drafts" of account (item 1 of argv)}\nend tell\nend run', account)
    time.sleep(2)
    mail_in_front()
    osa(OPEN_ROW, subject, timeout=300)
    wait(lambda: window_exists(subject), 30, 'the draft didn\'t open')


def restart_mail():
    """Quits Mail, which also ends the extension's process, and opens it again."""
    osa('tell application "Mail" to quit')
    wait(lambda: subprocess.run(['pgrep', '-x', 'Mail'], capture_output=True).returncode != 0, 60,
         'Mail didn\'t quit')
    time.sleep(3)
    subprocess.run(['open', '-a', 'Mail'], check=True)
    wait(lambda: osa('tell application "Mail" to return count of accounts') not in ('', '0'), 60,
         'Mail didn\'t start')
    time.sleep(5)


def check_t37_restart(run):
    """The password survives Mail restarting between typing it and sending: only the Keychain copy has it (R8)."""
    check_t37(run, restart=True)


def check_t37(run, restart=False):
    """The password survives closing and reopening the draft (t37)."""
    subject = run.subject('t37-restart' if restart else 't37-draft-password')
    password = 'ncme-' + os.urandom(6).hex()
    data_path = run.file('t37.bin', 5000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check t37: a password kept through the draft.', 'none',
                str(data_path))
    type_password(subject, password)
    # Closing with Save stores the draft, which makes an auto-save call that links the password to the message.
    mail_in_front()
    in_mail('set w to window (item 1 of argv)\nperform action "AXRaise" of w\n'
            'click (first button of w whose subrole is "AXCloseButton")\ndelay 1.5\n'
            'if (count of sheets of w) > 0 then click button "Save" of sheet 1 of w', subject)
    wait(lambda: not window_exists(subject), 30, 'the draft window didn\'t close')
    time.sleep(5)
    if restart:
        restart_mail()
    reopen_draft(subject, env()['NCME_MAIL_A_ACCOUNT'])
    run.expect('the draft opened again', True)
    click_send(subject)
    ok, detail = password_protected(run.fetch(subject, 't37-received.eml'), 't37.bin', data_path.read_bytes(),
                                    password)
    run.expect('the links still need the password', ok, detail)


def check_password_refused(run):
    """A password the server's policy refuses stops the send with the server's reason (FR7)."""
    subject = run.subject('t6-policy')
    data_path = run.file('t6-policy.bin', 4000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check FR7: a password the policy refuses.', 'none', str(data_path))
    type_password(subject, 'short')
    click_send(subject)
    wait(lambda: sheet(subject) is not None, 90, 'no alert')
    texts, _ = sheet(subject)
    run.expect('the alert gives the policy\'s reason', 'Password' in texts and 'Nextcloud:' in texts, texts)
    click_sheet_button(subject, 'OK')
    time.sleep(1)
    run.expect('the window stays open', window_exists(subject))
    password = 'ncme-' + os.urandom(6).hex()
    type_password(subject, password)
    click_send(subject)
    ok, detail = password_protected(run.fetch(subject, 't6-policy-received.eml'), 't6-policy.bin',
                                    data_path.read_bytes(), password)
    run.expect('with a valid password it sends, and the links need it', ok, detail)


def server_setting(key, value):
    """Sets or, with None, deletes a key of the test server's core app config (D18)."""
    values = env()
    url = f'{values["NCME_TEST_SERVER_URL"]}/ocs/v2.php/apps/provisioning_api/api/v1/config/apps/core/{key}'
    command = ['curl', '-sS', '-u', f'{values["NCME_TEST_USERNAME"]}:{values["NCME_TEST_PASSWORD"]}',
               '-H', 'OCS-APIRequest: true', '-H', 'Accept: application/json']
    if value is None:
        command += ['-X', 'DELETE', url]
    else:
        command += ['-X', 'POST', '--data-urlencode', f'value={value}', url]
    answer = subprocess.run(command, capture_output=True, text=True, check=True).stdout
    if '"statuscode":200' not in answer:
        raise CheckError(f'the server setting {key} couldn\'t be changed')


def check_password_required(run):
    """When the server requires passwords and none is set, the send stops and asks for one (FR7)."""
    subject = run.subject('t6-required')
    data_path = run.file('t6-required.bin', 4000)
    checks.app_settings(checks.DEFAULTS)
    server_setting('shareapi_enforce_links_password', 'yes')
    try:
        checks.mail('compose', 'A', 'B', subject, 'Check FR7: the server requires a password.', 'none',
                    str(data_path))
        click_send(subject)
        wait(lambda: sheet(subject) is not None, 90, 'no alert')
        texts, _ = sheet(subject)
        run.expect('the alert asks for a password', 'requires a password' in texts, texts)
        click_sheet_button(subject, 'OK')
        time.sleep(1)
        password = 'ncme-' + os.urandom(6).hex()
        type_password(subject, password)
        click_send(subject)
        received = run.fetch(subject, 't6-required-received.eml')
    finally:
        server_setting('shareapi_enforce_links_password', None)
    ok, detail = password_protected(received, 't6-required.bin', data_path.read_bytes(), password)
    run.expect('with a password it sends, and the links need it', ok, detail)


# MARK: Send warnings (FR5, FR6, T7)

SIGN = 'first checkbox of (first group of window (item 1 of argv) whose description is "digitally sign")'


def sign_on(subject):
    return in_mail(f'return value of {SIGN}', subject) == '1'


def set_sign(subject, on):
    """Turns the window's Sign button on or off. Mail keeps that state for later messages."""
    if sign_on(subject) != on:
        mail_in_front()
        in_mail(f'click {SIGN}', subject)
        time.sleep(0.5)
    if sign_on(subject) != on:
        raise CheckError('Sign didn\'t change')


def restore_sign():
    """Turns Sign back on for later messages, through a window that's closed again without saving."""
    subject = '[ncme check] restoring Sign ' + time.strftime('%H%M%S')
    checks.mail('compose', 'A', 'B', subject, 'Restoring Sign.', 'none')
    try:
        set_sign(subject, True)
    finally:
        close_test_windows()


def send_check_alert(subject):
    """Clicks Send and waits for the send check's alert, which has Cancel and Send Anyway."""
    click_send(subject)
    wait(lambda: sheet(subject) is not None or not window_exists(subject), 90, 'no alert and no send')
    return sheet(subject)


def check_t33(run):
    """FR5: with Sign off, the alert names the file; Cancel keeps it, and with Sign on it goes out as links."""
    subject = run.subject('t33-sign-off')
    data_path = run.file('t33.bin', 5000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check t33: Sign off, then on.', 'none', str(data_path))
    try:
        set_sign(subject, False)
        alert = send_check_alert(subject)
        run.expect('the alert names the file and says to turn on Sign', alert and '“t33.bin”' in alert[0]
                   and 'turn on Sign' in alert[0] and 'Send Anyway' in alert[1], alert)
        if not alert:
            return
        click_sheet_button(subject, 'Cancel')
        time.sleep(1)
        run.expect('Cancel keeps the window open', window_exists(subject))
        set_sign(subject, True)
        click_send(subject)
    finally:
        restore_sign()
    _, attached, found = file_links(run.fetch(subject, 't33-received.eml'))
    run.expect('with Sign on, the file goes out as links', downloads_match(found, 't33.bin', data_path.read_bytes())
               and not attached)


def check_t23(run):
    """FR5: Send Anyway sends the file attached, and nothing is uploaded."""
    subject = run.subject('t23-send-anyway')
    data_path = run.file('t23.bin', 5000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check t23: Sign off, sent anyway.', 'none', str(data_path))
    try:
        set_sign(subject, False)
        alert = send_check_alert(subject)
        run.expect('the alert appears', alert and 'Send Anyway' in alert[1], alert)
        if not alert:
            return
        click_sheet_button(subject, 'Send Anyway')
        received = run.fetch(subject, 't23-received.eml')
    finally:
        restore_sign()
    _, attached, found = file_links(received)
    run.expect('the file arrives attached, byte for byte', attached.get('t23.bin') == data_path.read_bytes()
               and not found)
    run.expect('nothing was uploaded', not folders_for(subject), f'folders: {folders_for(subject)}')


def phrase_check(run, name, sign):
    """FR6: the text mentions an attachment and there's none, with Sign on or off."""
    subject = run.subject(name)
    checks.app_settings(dict(checks.DEFAULTS, warningPhrases=['see attach']))
    checks.mail('compose', 'A', 'B', subject, 'Please see attached, as promised.', 'none')
    try:
        set_sign(subject, sign)
        alert = send_check_alert(subject)
        run.expect('the alert names the phrase', alert and '“see attach”' in alert[0], alert)
        if not alert:
            return
        click_sheet_button(subject, 'Cancel')
        time.sleep(1)
        run.expect('Cancel keeps the window open', window_exists(subject))
        alert = send_check_alert(subject)
        run.expect('sending again warns again', alert is not None)
        if alert:
            click_sheet_button(subject, 'Send Anyway')
        received = run.fetch(subject, f'{name}-received.eml')
    finally:
        if not sign:
            restore_sign()
    texts, attached, found = file_links(received)
    run.expect('Send Anyway sends it as written', 'see attached' in '\n'.join(texts['plain']) and not found
               and not attached)


def check_t34_phrase(run):
    phrase_check(run, 't34-phrase-sign-on', True)


def check_t35_phrase(run):
    phrase_check(run, 't35-phrase-sign-off', False)


def check_phrase_elsewhere(run):
    """FR6 leaves out the subject and quoted text: a phrase only there gives no alert."""
    checks.app_settings(dict(checks.DEFAULTS, warningPhrases=['see attach']))
    subject = run.subject('see attached in the subject only')
    checks.mail('compose', 'A', 'B', subject, 'Nothing to mention here.', 'none')
    alert = send_check_alert(subject)
    run.expect('no alert for the subject', alert is None, alert)
    if alert:
        click_sheet_button(subject, 'Cancel')
        return
    run.fetch(subject, 'phrase-subject-received.eml')
    original = run.subject('phrase-quote')
    checks.app_settings(checks.DEFAULTS)
    checks.mail('send', 'A', 'B', original, 'The original says: see attached.', 'none')
    run.fetch(original, 'phrase-quote-original.eml')
    checks.app_settings(dict(checks.DEFAULTS, warningPhrases=['see attach']))
    osa('on run argv\ntell application "Mail"\nset m to first message of inbox whose subject is (item 1 of argv)\n'
        'set selected mailboxes of message viewer 1 to {mailbox of m}\ndelay 1\n'
        'set selected messages of message viewer 1 to {m}\nend tell\nend run', original)
    mail_in_front()
    in_mail('perform action "AXRaise" of (first window whose name starts with "Inbox")')
    click_menu('Message', 'Reply')
    reply = 'Re: ' + original
    wait(lambda: window_exists(reply), 30, 'no reply window')
    alert = send_check_alert(reply)
    run.expect('no alert for a phrase only in the quote', alert is None, alert)
    if alert:
        click_sheet_button(reply, 'Cancel')
        return
    run.fetch(reply, 'phrase-quote-reply.eml')


# MARK: Progress (R3, T8)

NOTIFICATION_TEXTS = """
on walk(element, depth, found)
    tell application "System Events"
        set kids to {}
        try
            set kids to UI elements of element
        end try
        repeat with kid in kids
            try
                if role of kid is "AXStaticText" then set found to found & (value of kid as text) & linefeed
            end try
            if depth < 8 then set found to my walk(kid, depth + 1, found)
        end repeat
    end tell
    return found
end walk

tell application "System Events" to tell process "NotificationCenter" to set ws to every window
set found to ""
repeat with w in ws
    set found to my walk(w, 1, found)
end repeat
return found
"""


def notification_texts():
    """The texts of the notifications on screen."""
    return osa(NOTIFICATION_TEXTS, timeout=60)


def notifications_allowed():
    """Whether macOS lets NextcloudMailExtension notify, as the installed Debug build reports it."""
    return checks.mail('app', '--notification-status', capture=True).strip() == 'allowed'



def check_t8(run):
    """A slow upload shows a notification while it runs, and another when it's done (R3)."""
    if not notifications_allowed():
        raise CheckError('NextcloudMailExtension may not notify yet: allow it when macOS asks')
    subject = run.subject('t8-progress')
    data_path = run.file('t8.bin', 30_000_000)
    checks.app_settings(checks.DEFAULTS)
    checks.mail('compose', 'A', 'B', subject, 'Check t8: a slow upload.', 'none', str(data_path))
    click_send(subject)
    # 30 MB is over the account's size limit, so Mail asks about Mail Drop first.
    wait(lambda: sheet(subject) is not None or not window_exists(subject), 120, 'neither a prompt nor a send')
    prompt = sheet(subject)
    if prompt and 'Try Sending in Email' in prompt[1]:
        ticked = in_mail('return value of every checkbox of sheet 1 of window (item 1 of argv)', subject)
        if '1' in ticked.split(', '):
            raise CheckError('"Don\'t ask again" is ticked, which this check never does')
        click_sheet_button(subject, 'Try Sending in Email')
    seen = {'Uploading 1 file (30 MB) to Nextcloud…': False, 'Uploaded 1 file (30 MB) in': False}
    end = time.time() + 240
    while time.time() < end and not all(seen.values()):
        texts = notification_texts()
        for text in seen:
            seen[text] = seen[text] or text in texts
        time.sleep(0.5)
    run.expect('a notification while the upload runs', seen['Uploading 1 file (30 MB) to Nextcloud…'])
    run.expect('a notification when it\'s done', seen['Uploaded 1 file (30 MB) in'])
    _, attached, found = file_links(run.fetch(subject, 't8-received.eml', 900))
    run.expect('the email arrived with the file as links', downloads_match(found, 't8.bin', data_path.read_bytes())
               and not attached)


# MARK: The popover's link choice, expiry and settings button

POPOVER = ('group 1 of pop over 1 of (first button of toolbar 1 of window (item 1 of argv) '
           'whose description is "NextcloudMailExtension")')


def open_popover(subject):
    mail_in_front()
    in_mail('click (first button of toolbar 1 of window (item 1 of argv) whose description is "NextcloudMailExtension")',
            subject)
    wait(lambda: in_mail(f'return exists {POPOVER}', subject) == 'true', 15, 'the popover didn\'t open')


def check_own_expiry(run):
    """The popover gives this email its own link expiry, in a year where the settings say a week (FR4)."""
    subject = run.subject('own-expiry')
    data_path = run.file('own-expiry.bin', 4000)
    checks.app_settings(dict(checks.DEFAULTS, expiry={'after': {'years': 0, 'months': 0, 'days': 7, 'hours': 0}}))
    checks.mail('compose', 'A', 'B', subject, 'Check: this email\'s own link expiry.', 'none', str(data_path))
    open_popover(subject)
    # SwiftUI's controls have no names here, so they're found by kind: the checkbox, then the picker it shows, after
    # the link choice's.
    in_mail(f'click checkbox 1 of {POPOVER}', subject)
    picker = f'pop up button 2 of {POPOVER}'
    wait(lambda: in_mail(f'return exists {picker}', subject) == 'true', 10, 'no expiry picker')
    in_mail(f'click {picker}', subject)
    time.sleep(0.5)
    in_mail(f'click menu item "In a year" of menu 1 of {picker}', subject)
    time.sleep(0.5)
    osa('tell application "System Events" to key code 53')
    click_send(subject)
    texts, attached, found = file_links(run.fetch(subject, 'own-expiry-received.eml'))
    year = time.localtime()
    expected = time.strftime('%-d %b ', year) + str(year.tm_year + 1)
    plain = '\n'.join(texts['plain'])
    run.expect('the link expires in a year, not a week', f'link expires {expected}' in plain,
               re.findall(r'link expires [^)]*', plain))
    run.expect('the link works', downloads_match(found, 'own-expiry.bin', data_path.read_bytes()) and not attached)


def choose_links(subject, choice):
    """Picks this email's link choice, such as "All files via Nextcloud", in the popover's first pop-up menu."""
    open_popover(subject)
    menu = f'pop up button 1 of {POPOVER}'
    wait(lambda: in_mail(f'return exists {menu}', subject) == 'true', 10, 'no link choice in the popover')
    in_mail(f'click {menu}', subject)
    time.sleep(0.5)
    in_mail(f'click menu item (item 2 of argv) of menu 1 of {menu}', subject, choice)
    time.sleep(0.5)
    mail_in_front()
    osa('tell application "System Events" to key code 53')


def check_keep_attached(run):
    """The popover keeps this email's file attached, where the settings would make it a link (FR3)."""
    subject = run.subject('keep-attached')
    data_path = run.file('kept.bin', 40_000)
    checks.app_settings(dict(checks.DEFAULTS))
    checks.mail('compose', 'A', 'B', subject, 'Check: this email keeps its files attached.', 'none', str(data_path))
    choose_links(subject, 'All files kept as attachments')
    click_send(subject)
    _, attached, found = file_links(run.fetch(subject, 'keep-attached-received.eml'))
    run.expect('the file arrived attached, byte for byte', attached.get('kept.bin') == data_path.read_bytes(),
               f'attached: {sorted(attached)}')
    run.expect('no links', not found, f'links for: {sorted(found)}')


def check_all_files(run):
    """The popover makes this email's small file a link, where the settings' size limit would keep it (FR3)."""
    subject = run.subject('all-files')
    data_path = run.file('small.bin', 4000)
    checks.app_settings(dict(checks.DEFAULTS, onlyLargeFiles=True, sizeLimitMegabytes=0.2))
    checks.mail('compose', 'A', 'B', subject, 'Check: all of this email\'s files become links.', 'none',
                str(data_path))
    choose_links(subject, 'All files via Nextcloud')
    click_send(subject)
    _, attached, found = file_links(run.fetch(subject, 'all-files-received.eml'))
    run.expect('the small file became a link that downloads it', downloads_match(found, 'small.bin',
                                                                                 data_path.read_bytes()),
               f'links for: {sorted(found)}')
    run.expect('nothing attached', not attached, f'attached: {sorted(attached)}')


def check_password_advice(run):
    """The popover gives the server's reason for a weak password, generates one it accepts, and copies it (T16)."""
    subject = run.subject('password-advice')
    checks.mail('compose', 'A', 'B', subject, 'Check: the password buttons.', 'none')
    open_popover(subject)
    field = f'text field 1 of {POPOVER}'
    wait(lambda: in_mail(f'return exists {field}', subject) == 'true', 15, 'no password field in the popover')
    in_mail(f'set value of attribute "AXFocused" of {field} to true', subject)
    mail_in_front()
    osa('tell application "System Events" to keystroke "short"')

    def texts():
        return in_mail(f'return value of every static text of {POPOVER}', subject)

    wait(lambda: 'at least' in texts(), 15, 'no reason for the short password')
    run.expect('a short password shows the server\'s reason', True)
    # The buttons have no names, only their tooltips (T16).
    in_mail(f'click (first button of {POPOVER} whose help is "Generate a password that Nextcloud accepts")',
            subject)
    wait(lambda: 'at least' not in texts(), 15, 'the reason stayed after generating')
    generated = in_mail(f'return value of {field}', subject)
    run.expect('Generate fills in a password the server accepts', len(generated) >= 10, f'{len(generated)} characters')
    in_mail(f'click (first button of {POPOVER} whose help is "Copy the password to give to the recipients")',
            subject)
    time.sleep(0.5)
    copied = subprocess.run(['pbpaste'], capture_output=True, text=True).stdout
    run.expect('Copy puts it on the clipboard', copied == generated)
    mail_in_front()
    osa('tell application "System Events" to key code 53')
    close_test_windows()


def check_open_settings(run):
    """The popover's Settings… button opens the NextcloudMailExtension app."""
    osa('tell application id "lv.warp.nextcloudmailextension" to if it is running then quit')
    wait(lambda: subprocess.run(['pgrep', '-f', 'NextcloudMailExtension.app/Contents/MacOS/NextcloudMailExtension$'],
                                capture_output=True).returncode != 0, 30, 'the app didn\'t quit')
    subject = run.subject('open-settings')
    checks.mail('compose', 'A', 'B', subject, 'Check: the Settings button.', 'none')
    open_popover(subject)
    # The button has no name here, only its tooltip.
    in_mail(f'click (first button of {POPOVER} whose help is "Open NextcloudMailExtension\'s settings")', subject)
    wait(lambda: osa('tell application "System Events" to return exists (first process whose bundle identifier '
                     'is "lv.warp.nextcloudmailextension")') == 'true', 30, 'the app didn\'t open')
    run.expect('the app opened', True)
    close_test_windows()


CHECKS = {'t7': check_t7, 't21': check_t21, 't22': check_t22, 't30': check_t30, 't34': check_t34,
          't38': check_t38, 't39': check_t39, 't36': check_t36, 't37': check_t37,
          't37-restart': check_t37_restart, 'password-refused': check_password_refused,
          'password-required': check_password_required, 't33': check_t33, 't23': check_t23,
          't34-phrase': check_t34_phrase, 't35-phrase': check_t35_phrase, 'phrase-elsewhere': check_phrase_elsewhere,
          't8': check_t8, 'own-expiry': check_own_expiry, 'open-settings': check_open_settings,
          'keep-attached': check_keep_attached, 'all-files': check_all_files,
          'password-advice': check_password_advice}


def main():
    if '--list' in sys.argv:
        print('\n'.join(CHECKS))
        return 0
    names = sys.argv[1:] or list(CHECKS)
    unknown = [name for name in names if name not in CHECKS]
    if unknown:
        print(f'unknown checks: {", ".join(unknown)}. --list lists them.', file=sys.stderr)
        return 2
    run = Run()
    failed = 0
    try:
        for name in names:
            print(f'== {name}', flush=True)
            run.results = []
            try:
                close_test_windows()
                CHECKS[name](run)
            except (CheckError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                run.expect('ran', False, str(getattr(error, 'stderr', '') or error).strip())
            for what, ok, detail in run.results:
                failed += not ok
                print(f'  {"ok  " if ok else "FAIL"} {what}' + (f' ({detail})' if detail and not ok else ''), flush=True)
    finally:
        checks.app_settings(run.original)
    print(f'{"all passed" if not failed else f"{failed} failed"}. Messages are in {run.folder.relative_to(ROOT)}/')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
