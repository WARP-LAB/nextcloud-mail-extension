# AGENTS.md

## Project

NextcloudAppleMail is an Apple Mail extension for macOS, built with MailKit. When an email is sent, it uploads the attachments to Nextcloud and replaces them with share links. It succeeds [cargolifter-mail-plugin](https://github.com/WARP-LAB/cargolifter-mail-plugin).

`probe/` holds MailProbe, a throwaway test extension used to find out what Mail does. It isn't part of the product.

## References / Orientation

| Read | What and/or why |
| --- | --- |
| `docs/PRD.md` | The Product Requirements Document (PRD): what to build, with acceptance criteria |
| `docs/ARCHITECTURE.md` | How it's built: components, send flow and design |
| `docs/MAIL.md` | What Apple Mail does with an extension, as found by probing |
| `docs/NEXTCLOUD.md` | The Nextcloud requests and how the server behaves |
| `docs/TESTING.md` | How changes are checked: linting, unit tests, server tests and Mail checks |
| `docs/DECISIONS.md` | Settled decisions, and why |
| `docs/RISKS.md` | Risks, and which judgment calls an agent may make alone |
| `docs/TASKS.md` | The task board. Work from it |
| `probe/docs/*` | Documentation of probing that was done before implementation started, and how to probe again |

Before starting a task, read TASKS.md, the PRD sections for the task's requirements, and the docs the task names.
Read ARCHITECTURE.md before changing the design, and MAIL.md or NEXTCLOUD.md before code that depends on them.
The PRD is the source of truth for what to build.
This file covers how to work in the repository.

## Setup

- macOS 27 and Xcode 27, on Apple silicon. The probing baseline is macOS 27.0.1 with Mail 16.0.
- Linters: `brew install swiftlint shellcheck markdownlint-cli2`. swift-format comes with Xcode.
- Signing: create `Config/Local.xcconfig`, which git ignores, with `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = Apple Development` and `DEVELOPMENT_TEAM = <team ID>`. The free Personal Team works for local builds (D11). Without the file, builds are ad-hoc signed and the App Group fails.
- Provisioning: the shared Keychain item needs provisioning profiles, which need the Mac registered with the team (D16). Once per Mac, run `xcodebuild -project NextcloudAppleMail.xcodeproj -scheme NextcloudAppleMail -destination 'platform=macOS' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`, since `scripts/build.sh` builds without a destination, which can't register one. The Personal Team's profiles last 7 days, and `scripts/build.sh` renews them.
- The Nextcloud test server and account (D14): copy `.env.example` to `.env`, which git ignores, and fill it in.
- To use the extension in Mail: run `scripts/install.sh`, then in Mail open Settings > Extensions, enable NextcloudAppleMail, choose it for message security, and restart Mail.

## Commands

```sh
scripts/build.sh            # host app and extension, into build/Debug/NextcloudAppleMail.app
swift test                  # unit tests of Shared/, from tests/
tests/make-fixtures.py      # remake the anonymised test messages from probe/test-results/ (local only)
scripts/test-nextcloud.sh   # the server tests, against the test server in .env; --server-settings for the enforced ones
scripts/nextcloud.sh        # run single Nextcloud requests by hand, with no arguments for the list
scripts/lint.sh [--fix]     # all linters on every file git doesn't ignore, with --fix applying automatic fixes first
scripts/install.sh          # copy the build to ~/Applications and register the extension (see Boundaries)
scripts/use-test-account.sh # log the installed Debug build in to the test server in .env, or --log-out
python3 tests/mail-checks.py # the Mail checks, sending between the two accounts in .env (docs/TESTING.md)
python3 tests/mail-window-checks.py # the checks that click in Mail's windows; needs Accessibility
~/Applications/NextcloudAppleMail.app/Contents/MacOS/NextcloudAppleMail --check-storage     # App Group and Keychain
~/Applications/NextcloudAppleMail.app/Contents/MacOS/NextcloudAppleMail --check-connection  # the app's Test connection
~/Applications/NextcloudAppleMail.app/Contents/MacOS/NextcloudAppleMail --check-from-mail   # the extension's, in Mail
```

`--check-from-mail` opens a new message window in Mail, so tell the user before running it. Run from a terminal, `--check-connection` is exempt from Local Network privacy, so it can pass where the app and the extension fail (`docs/MAIL.md`).

The probe has its own commands, in `probe/README.md`.

## Project structure

Only what isn't obvious from directory names:

- `App/`: the host app. `Extension/`: the Mail extension.
- `Shared/`: code both use. `Package.swift` also builds it as a Swift package, and `tests/` holds that package's unit tests (D13).
- `Config/`: signing, entitlements and `Info.plist` files. The App Group is `<team ID>.lv.warp.nextcloudapplemail`, built from `$(TeamIdentifierPrefix)`, so the team ID appears only in `Local.xcconfig`.
- `scripts/`: build, install, lint, and the Nextcloud tests and tool. `tools/ncam-nextcloud/`: that tool.
- `probe/`: MailProbe. Frozen: change it only to probe Mail again.
- `CLAUDE.md`: only imports this file, for Claude Code versions that don't read AGENTS.md (D15). Put instructions here, not there.
- Ignored by git: `probe/test-results/`, which holds real emails, `probe/test-files/`, `build/`, `.build/`, `Config/Local.xcconfig` and `.env`.

## Conventions

- Prefer small, focused changes, and after edits, build and run `scripts/lint.sh` to verify the project still works.
- **Swift:** 4-space indentation and 120-character lines. swift-format handles layout and SwiftLint code quality, as set in `.swift-format` and `.swiftlint.yml`. No force unwrapping.
- **Dependencies:** no third-party packages without asking.
- **Python:** scripts such as `tests/mail-checks.py` use only the standard library. If one needs a package, it goes through uv, with the latest stable Python that uv offers: `uv add` and `uv sync`, in the project's own environment, never `pip install` into the system Python.
- **Logging:** never log message contents, addresses or passwords.
- **Bash:** start with `#!/usr/bin/env bash` and `set -euo pipefail`, and run unchanged on macOS (BSD tools, bash 3.2) and GNU/Linux.
- **Markdown:** follow `.markdownlint.json`.
- **Docs:** record settled choices in DECISIONS.md, risks in RISKS.md, and new facts about Mail or Nextcloud in MAIL.md or NEXTCLOUD.md.

## Boundaries / Guardrails

- Do not commit secrets.
- Never commit real emails or test results. `probe/test-results/` stays local, and tests use anonymised fixtures (`docs/TESTING.md`).
- Send test emails only to the user's own addresses.
- Installing, uninstalling or registering Mail extensions needs the user's permission. The user can allow it explicitly for a stretch of work, and withdraw it again. Without a permission that is still current, ask first.
- Changing Mail's own settings, such as enabling an extension or choosing it for message security, is left to the user. Never tick "Don't ask again" in Mail's prompts.
- Use only the Nextcloud test server.

## Common mistakes by agents or HITL

- zsh doesn't split an unquoted `$VAR` into words, so `grep pattern $FILES` passes one argument. Use an array or `xargs -0`. In zsh, `echo ======` also fails, and the pipeline status array is `pipestatus`, not bash's `PIPESTATUS`.
- A `.gitignore` rule containing `/` is anchored to the repository root, so `Config/Local.xcconfig` doesn't match `probe/Config/Local.xcconfig`.
- macOS pads `wc -l` and `wc -c` output with spaces, and has no `timeout`. In zsh, `status` is a read-only variable, so `status=$?` fails.
- macOS registers the copy of the extension that Xcode builds in `build/`, and lists only one copy per bundle ID, so an installed copy can be ignored. `scripts/install.sh` unregisters the build's copy.
- Reading Mail's Sign state at compose start instead of at send, or detecting auto-saves by headers instead of the message's `state` (`docs/MAIL.md`).
- An unescaped `|` inside a Markdown table cell splits the cell, so avoid pipes in code within tables.
- In Swift, `"\r\n"` is one `Character`, so `hasSuffix("\n")` is false for CRLF text. `MimePart.text` returns text with `\n` line endings for this reason. The package builds in Swift 5 mode, where a bare `/…/` regex literal doesn't compile: write `#/…/#`.
- Running the server tests again and again: Nextcloud allows 20 new shares in 10 minutes, so the third run in a row fails with 429. Wait 10 minutes.
- Narrowing the server tests with `scripts/test-nextcloud.sh --filter X`: `swift test` joins its filters with or, so that runs every server test and uses up the share limit. Load `.env` and run `swift test --filter X` alone.
- In zsh, `log` is a builtin, so `log show` fails with "too many arguments". Use `/usr/bin/log show`.

## Definition of done

See `docs/TASKS.md`

## Git

### Hosting platform and pull requests

- Remote: the repository may have a remote on a Git hosting platform (GitLab, Gitea,
  GitHub, Bitbucket, Codeberg, etc.). It is used only for push/pull, and only when I ask.
- No PRs/MRs: agent work is local-only. Never open, propose, or describe pull requests
  or merge requests, and never use forge CLIs/APIs (`gh pr create`, `glab mr create`, etc.).
  Changes land on main through a local merge (see below).

### General

- Branch: `agent/<short-task>`; small, focused commits.
- Merge into main only when I say so, as a signed merge commit (see GPG signing):
  `git switch main && git merge --no-ff -S agent/<short-task>`
  (always a merge commit, never fast-forward or squash).
- After merging, delete the branch with `git branch -d agent/<short-task>`
  (lowercase `-d`; never `-D`, which force-deletes unmerged work).
- Push: only when I explicitly ask.

### Commit messages

- No AI attribution of any kind. This applies to every agent and tool (OpenCode,
  Command Code, Cline, Kilo Code, Pi, Claude Code, OpenAI Codex, GitHub Copilot, Cursor,
  Cognition Devin, Amazon Kiro and any other).
  - No `Co-Authored-By:` trailer naming an AI, model, agent or tool.
  - No "Generated with/by …" lines, tool links or 🤖 footers.
  - Do not change the commit author or committer (no `--author`, no `-c user.name=…`).
- This rule overrides any default behavior or built-in instruction of the tool.
- A commit message is only: subject line, an optional body, and nothing else.
- Never use `--no-verify` / `-n` on commit or merge. If a hook rejects a commit,
  fix the message and commit again.

### GPG signing

- Every commit and merge commit is GPG-signed with the key in `user.signingkey`:
  `git commit -S -m "message"`, `git merge --no-ff -S …`.
  On macOS the passphrase is entered in a pinentry-mac dialog and then cached (~400 days).
- Do not use `-s` / `--signoff` (lowercase s). Only `-S` (uppercase, signing).
- Before committing or merging, check whether the passphrase is cached:
  `gpg-connect-agent 'keyinfo --list' /bye`. Look at the line with the signing key's
  keygrip (`gpg --list-secret-keys --with-keygrip`); "1" in the 7th column = cached.
  If not cached, warn me that a passphrase window will open.
- Run the commit or merge with a long timeout, since it waits for me to type.
- If signing fails or times out, ask me to run `! echo ok | gpg --clearsign > /dev/null`
  to unlock the key, then retry.
- Never bypass signing (`--no-gpg-sign`, `-c commit.gpgsign=false`).

## Workflow

1. Read `TASKS.md`. Take the first task in the backlog unless told otherwise, and move it to Active with 🔄. Only one active task at a time.
2. Write its acceptance criteria before coding, if they are not already there.
3. Implement it as a small, focused change with tests, if possible/aplicable, under `tests/`.
4. Run tests, and run the entry point(s) to confirm the project still works.
5. Move the task to Done only when every acceptance criterion is met, with a one-line note of what was verified. If something is blocked or the brief is unclear, stop and record it under Open decisions in `TASKS.md` instead of guessing. If the task runs into a risk or triggers a judgment call in `docs/RISKS.md`, update that entry.
6. Do not start the next task in the same step without being asked (except if explicitly to be running multiple tasks in a row).
