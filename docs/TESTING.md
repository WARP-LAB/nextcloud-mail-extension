# Testing

How changes get checked before they count as done. The parts of Mail's behaviour the design depends on can't be unit-tested, so besides linting and unit tests, some changes need a check in Mail itself.

## Linting

`scripts/lint.sh` runs four linters on every file git tracks or would track, so anything `.gitignore` excludes is skipped. `scripts/lint.sh --fix` applies the automatic fixes first. A linter whose kind of file doesn't exist yet is skipped. A linter that's missing makes the script fail, with the command to install it.

| Files | Linter | Config | Install |
| --- | --- | --- | --- |
| Swift, layout | swift-format | `.swift-format`: 4-space indentation, 120-character lines, default rules | Comes with Xcode, run as `xcrun swift-format` |
| Swift, code quality | SwiftLint | `.swiftlint.yml`: default rules with the layout ones off, `line_length` 120, plus `force_unwrapping` and `implicitly_unwrapped_optional` | `brew install swiftlint` |
| Bash | ShellCheck | Default checks | `brew install shellcheck` |
| Markdown | markdownlint-cli2 | `.markdownlint.json` | `brew install markdownlint-cli2` |

- **Layout versus code quality:** swift-format owns layout and SwiftLint owns code quality, so SwiftLint's overlapping layout rules are off. `trailing_comma` must stay off, because swift-format adds trailing commas that SwiftLint would reject. SwiftLint keeps `line_length`, because swift-format doesn't split or report long string literals.
- **The probe:** `probe/` is left out of the Swift linters. Its bash scripts and Markdown are linted like everything else.
- **After an Xcode update:** new swift-format findings with no code change are probably the tool, not the code (R20).

## Unit tests

- **Where:** in `tests/`, as the unit tests of the Swift package in `Package.swift`, which builds `Shared/`. `swift test` runs them without Xcode's window or signing (D13).
- **What:**
  - the rewriter, for every message structure in [MAIL.md](MAIL.md#message-structures)
  - `LinkPolicy` and `TextCheck`
  - expiry dates and folder names
  - the upload ledger, and the send flow and `Sender` against a fake Nextcloud in memory: both send calls, failures and retries, Mail Drop, signature images, and each sharing setting
- **Fixtures:** anonymised copies of the probe's saved messages, in `tests/NextcloudAppleMailSharedTests/Fixtures/`. `tests/make-fixtures.py` makes them from the git-ignored `probe/test-results/`. It replaces names, addresses, server headers, message IDs and dates, keeps the structure, boundaries and Content-IDs, and shrinks each file to 1/1000 of its size, so a test's size limit of 5000 bytes stands for 5 MB. The shrunk bytes come from a hash of the original file, so a file is the same in a message's first and second call, as it is in Mail (t15). It then checks that no personal strings are left. Never commit anything from `probe/test-results/` itself.

## Nextcloud tests

Run against the test server and account only (D14), whose credentials are in the git-ignored `.env`. `scripts/test-nextcloud.sh` loads it and runs `tests/NextcloudServerTests`, which `swift test` alone skips. Each test makes its own app password and its own folder inside `NCAM_TEST_DIRECTORY`, and deletes both. The deleted folders stay in the account's trash bin. They cover every request in [NEXTCLOUD.md](NEXTCLOUD.md):

- the browser login's start, the app password, and revoking it
- folders and uploads, including the refusal to overwrite an existing file
- shares with and without a password, and their view and download links
- expiry dates, and a password the policy rejects
- the password page, and the zip from a folder share
- with `--server-settings` only: an enforced expiry maximum and enforced passwords. They change the whole server's sharing settings for the test, so that option runs nothing else, and puts the settings back at the end, even after a failure (D18)

One run creates 8 shares, and the `--server-settings` run tries 5, while Nextcloud allows 20 in 10 minutes, so a third run within 10 minutes fails with 429 ([NEXTCLOUD.md](NEXTCLOUD.md#rate-limit)). `scripts/nextcloud.sh` runs single requests by hand with the same `.env`. Record what the server really did in NEXTCLOUD.md (R19).

`scripts/use-test-account.sh` logs the installed Debug build in to the test server with an app password, instead of the browser login, and sets the upload directory to `NCAM_TEST_DIRECTORY`, so the extension in Mail uploads there. `--log-out` revokes it. The app's `--check-connection` and `--check-from-mail` options then run the two checks from the command line.

## Mail checks

Build and install the extension, keep Sign on, and send each test to your own addresses only. The probe tests in [probe/docs/TESTS.md](../probe/docs/TESTS.md) are the model. Run the ones for what the change touches, against the real extension:

| The change touches | Checks |
| --- | --- |
| Send flow, ledger or rewriter | t5, t7, t9, t15–t22, t27–t30, t34, t38, t39 |
| Send warnings | t23, t33, t34, t35 |
| Password popover | t36, t37 |
| Settings or login | Test connection and Test from Mail in the host app, then t5 |

- **Recipients' mail clients:** when the link layout changes, check the delivered messages in Apple Mail, Gmail on the web and Outlook (R16).
- **Recording:** list the checks that were run in the task's Done note.
- **Never** tick "Don't ask again" in Mail's prompts (R2).

### Driving Mail from the command line

An agent can run Mail checks itself through AppleScript: Mail builds and sends a message with files between two of the user's own accounts, and reads what arrived and the Sent copy. The two accounts, A and B, are in the git-ignored `.env` as `NCAM_MAIL_A_ACCOUNT` and `NCAM_MAIL_A_ADDRESS`, and the same for B (`.env.example`). Their names and addresses never go into tracked files. Messages saved by the checks go in the git-ignored `test-results/`.

macOS asks for these permissions, for the app that runs the terminal, such as Visual Studio Code or Terminal. Each appears in System Settings > Privacy & Security once it's been asked for, and the user can turn it off there again.

| Permission | Section in Privacy & Security | Asked for when | Needed for |
| --- | --- | --- | --- |
| Automation of Mail | Automation, under the terminal's app | The first AppleScript sent to Mail | Sending, and reading mailboxes and messages |
| Automation of System Events | Automation, under the terminal's app | The first AppleScript sent to System Events | Reading Mail's alerts and clicking their buttons |
| Accessibility | Accessibility | Not asked for: System Events fails at once with "osascript is not allowed assistive access", and the user turns the terminal's app on in the list by hand | Alerts, Undo Send, Send Later and the Mail Drop prompt |
| Screen Recording | Screen & System Audio Recording | The first `screencapture` | Screenshots of Mail's windows, to see an alert or a layout |
| Local Network, for NextcloudAppleMail | Local Network | The app's first request to a server on the local network, opened normally rather than from a terminal | The extension's uploads to such a server ([MAIL.md](MAIL.md#network)) |

Mail itself needs the extension turned on and chosen for message security, and Sign on, which AppleScript can't read or change. After `scripts/install.sh` replaces a build, quit and reopen Mail. Until then, sends stop with Mail's own alert, "An error occurred while trying to encrypt your message", because Mail can't reach the replaced extension.

Without Accessibility, the checks that need Mail's windows stay with the user: Undo Send, Send Later, the Mail Drop prompt, the send warnings and the toolbar popover.

- **Running them:** `python3 tests/mail-checks.py [check …]`, with `--list` for the checks. Each sets the app's settings, sends a message with files from A to B, fetches what arrived and the Sent copy, downloads every link and compares it with the original file, and puts the settings back at the end. It uses `scripts/mail.sh`, which sends, fetches by subject, and runs the installed Debug build's options.
- **Debug options:** the Debug build's `--render-window` draws the settings window off screen and prints it as a PNG in base64, which needs no Screen Recording, and its `--settings [<json>]` prints and changes the settings, and `--debug-dumps on|off|take` keeps copies of what Mail passes `encode()` for messages whose subject has `[ncam`, so a check can see each call's structure. Turn the dumps off afterwards.
- **What AppleScript can't make:** its messages have the text first and the files after it, with no pasted images, and its replies have no quote, so those structures still come from the fixtures and from the user.
- **Signature check:** `NCAM_MAIL_SIGNATURE` in `.env` names a signature with an image, which the check chooses, since Mail's default can change.
- **Leftover windows:** a send that fails leaves its message window open, and AppleScript can't close it. With Accessibility, its close button and then Don’t Save, with a curly apostrophe, close it.
- **Window checks:** `python3 tests/mail-window-checks.py [check …]` runs T5c's checks through System Events: an upload failure's alert (t7), Undo Send (t21), Send Later (t22), a pasted image (t30), a reply's quote (t34), and Mail Drop with Try Sending in Email (t38) and Use Mail Drop (t39). It brings Mail to the front, and checks that it is, before every key press, so keys never reach another app. It never ticks "Don't ask again". Send Later schedules the email for 21:00, when Mail sends it. The clipboard is used for pasting and put back afterwards, when it held text.
- **Pasting into a message:** a click on the body doesn't reliably move the keyboard focus there. Setting the body's web area `AXFocused` through Accessibility does.

## After a macOS or Mail update

Run the quick regression set in [probe/docs/PROBE.md](../probe/docs/PROBE.md), then update [MAIL.md](MAIL.md) and [RISKS.md](RISKS.md) with any change.
