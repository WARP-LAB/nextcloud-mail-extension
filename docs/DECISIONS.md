# Decisions

Settled decisions, and why they were made. The current design is in [ARCHITECTURE.md](ARCHITECTURE.md). Questions still open are under Open Decisions in [TASKS.md](TASKS.md). Add new decisions at the end, and when one replaces another, say so in both.

## D1: Replace attachments in a message security extension (2026-11-05)

- **Decision:** the extension's `encode()` uploads the files and returns the message with links, with Mail's Sign button as the upload switch.
- **Why:** it's the only route that can change the outgoing message ([MAIL.md](MAIL.md#the-sign-button)).
- **Rejected:** the compose API, which can read but not change the body. AppleScript, which saw no outgoing messages. Dropping files on the toolbar popover, which works but doesn't meet FR1 or FR3, and loses the files when a draft is reopened.

## D2: Probe Mail first, with a throwaway extension (2026-11-05)

- **Decision:** MailProbe, a test extension with no Nextcloud code, checked what Mail does before any real code was written. It lives in `probe/` with its own docs, and isn't part of the product.
- **Why:** Mail's behaviour with extensions is mostly undocumented, and the probe can be rerun after Mail updates.

## D3: Detect auto-saves by the message state (2026-11-05)

- **Decision:** an `encode()` call is a draft auto-save when the message's `state` is 1, whatever its headers say.
- **Why:** `X-Apple-Auto-Saved` was missing on 7 of 30 auto-saves, and a header that marks every draft might also appear on a Mail Drop send.

## D4: Where the links go (2026-11-05)

- **Decision:** each file's links go where the file was in the text. If that can't be found, they go in a list after the user's own text, above any quoted messages, never at the top. FR9's links go after the user's own text too.
- **Why:** the user's choice. Recipients see each link where the sender put the file.

## D5: One folder per email (2026-11-05)

- **Decision:** each email's files go in their own subfolder of the configured directory.
- **Why:** the user's choice, so that file names in different emails can't clash, and all of an email's files can be downloaded as one folder (FR9).

## D6: Pasted and signature images (2026-11-05)

- **Decision:** pasted images follow the FR3 rule by default, with a setting to keep them in the email. Signature images never become links.
- **Why:** the user's choice.

## D7: Warn when Sign is off, rather than block (2026-11-05)

- **Decision:** FR5 is a warning with Cancel and Send Anyway, behind a setting that's on by default.
- **Why:** Mail lets the send check warn but not block ([MAIL.md](MAIL.md#errors-and-alerts)), and the user wanted the choice.

## D8: Respect Mail Drop (2026-11-05)

- **Decision:** if the user chooses Use Mail Drop, the email goes out with Mail Drop's link, and the extension deletes what it had uploaded for it. The setup help tells users to choose Try Sending in Email and tick "Don't ask again".
- **Why:** the user's choice. The extension can't prevent the prompt, and only notices Mail Drop after its first upload. The "Don't ask again" advice rests on an untested assumption (R2).

## D9: Bash scripts run on macOS and Linux (2026-11-06)

- **Decision:** bash scripts start with `#!/usr/bin/env bash`, and by default use only features and command options that work on both macOS (BSD tools, bash 3.2) and GNU/Linux.
- **Why:** the user's rule.

## D10: Linters (2026-11-06)

- **Decision:** swift-format for Swift layout, SwiftLint for Swift code quality with its layout rules off, ShellCheck for bash, and markdownlint-cli2 with the existing `.markdownlint.json`. `scripts/lint.sh` runs them all on the files git doesn't ignore. The probe is left out of the Swift linters.
- **Why:** each tool owns one job, so their rules don't contradict each other. Testing on the probe code showed that `trailing_comma` was the only real conflict. swift-format comes with Xcode, and the rest come from Homebrew. Details are in [TESTING.md](TESTING.md#linting).

## D11: Sign local builds with the free Personal Team (2026-11-06)

- **Decision:** local builds are signed with the user's free Apple Personal Team, set in the git-ignored `Config/Local.xcconfig`. The paid Apple Developer Program membership has expired, and is renewed before distributing.
- **Why:** the probe showed that Mail loads an ad-hoc signed extension, so local builds don't need a paid team. A team gives a stable signing identity and a team ID for the App Group. Developer ID signing and notarization for other Macs do need the paid membership (OD3).

## D12: Minimum versions (2026-11-06)

- **Decision:** macOS 27 or later, which means Apple silicon only, since macOS 26 was the last version for Intel Macs. Nextcloud 34 or later, or 35 if 34 turns out to block something.
- **Why:** the user's choice. macOS 27 is the probed baseline. Nextcloud 34's source has every behaviour in [NEXTCLOUD.md](NEXTCLOUD.md), checked on 2026-11-06.

## D13: Shared code as a Swift package (2026-11-06)

- **Decision:** code that the host app and the extension both use lives in `Shared/`. The Xcode project compiles it into both targets, and `Package.swift` also builds it as a Swift package, with its unit tests in `tests/`. The App Group's identifier reaches the code through an `Info.plist` key built from `$(TeamIdentifierPrefix)`, so the team ID stays out of tracked files.
- **Why:** `swift test` then runs the unit tests from the command line, with no Xcode window and no signing, and the shared code can't depend on Mail or the app.

## D14: The Nextcloud test server (2026-11-06)

- **Decision:** Nextcloud tests run against the test server and account the user gave, which resolves OD2. Its URL, login, password and upload directory are in the git-ignored `.env`, with `.env.example` as the template. Tests upload only into that directory, each run in its own folder, and delete what they made. They log in with an app password made from the account password, and revoke it at the end.
- **Why:** the user's choice. A file outside the repository keeps the credentials out of git, and an app password per run means the account password isn't used for the requests themselves.
