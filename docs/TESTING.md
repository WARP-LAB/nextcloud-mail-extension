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

- **Where:** in `tests/`, as the Xcode project's test target, from task T1.
- **What:**
  - the rewriter, for every message structure in [MAIL.md](MAIL.md#message-structures)
  - `LinkPolicy` and `TextCheck`
  - expiry dates and folder names
  - the upload ledger
- **Fixtures:** anonymised copies of the probe's saved messages. Replace names, addresses, server headers, message IDs and dates, but keep the structure, boundaries, Content-IDs and file contents. The files can be the dummy files from `probe/scripts/make-test-files.py`. Never commit anything from `probe/test-results/`.

## Nextcloud tests

Run against the test server and account only (open decision OD2), with credentials kept outside the repo, for example in environment variables or the Keychain. Cover every request in [NEXTCLOUD.md](NEXTCLOUD.md):

- login and the app password
- folders and uploads, including the refusal to overwrite an existing file
- shares with and without a password, and their view and download links
- an enforced expiry maximum, enforced passwords, and a password the policy rejects
- the password page, and the zip from a folder share

Record what the server really did in NEXTCLOUD.md (R19).

## Mail checks

Build and install the extension, keep Sign on, and send each test to your own addresses only. The probe tests in [probe/docs/TESTS.md](../probe/docs/TESTS.md) are the model. Run the ones for what the change touches, against the real extension:

| The change touches | Checks |
| --- | --- |
| Send flow, ledger or rewriter | t5, t7, t9, t15–t22, t27–t30, t34, t38, t39 |
| Send warnings | t23, t33, t34, t35 |
| Password popover | t36, t37 |
| Settings or login | "Test connection" in the host app, then t5 |

- **Recipients' mail clients:** when the link layout changes, check the delivered messages in Apple Mail, Gmail on the web and Outlook (R16).
- **Recording:** list the checks that were run in the task's Done note.
- **Never** tick "Don't ask again" in Mail's prompts (R2).

## After a macOS or Mail update

Run the quick regression set in [probe/docs/PROBE.md](../probe/docs/PROBE.md), then update [MAIL.md](MAIL.md) and [RISKS.md](RISKS.md) with any change.
