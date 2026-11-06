# Project Roadmap & Task Board

See References / Orientation files mentioned in `AGENTS.md`.
Source of truth for scope: `docs/PRD.md`.
Architecture: `docs/ARCHITECTURE.md`.
Risk register: `docs/RISKS.md`.

## 🎯 Current Sprint / Milestone

**M1: a first real link.** The host app has settings and a Nextcloud login, and a file in a real email is replaced by a working Nextcloud link. Tasks T1–T5.

## ⏳ Active Tasks (In Progress)

> Rules for Agent:
> - Only work on ONE active task at a time.
> - Mark with 🔄 when analyzing or executing.
> - Write Acceptance Criteria or a explicit Definition of Done
> - Take tasks in order unless told otherwise. Do not start the next task without being asked.

None. T2 is next.

## ❓ Open Decisions (human to resolve)

Agents: do not guess these. Record questions here and stop.
Judgment calls and known risks are tracked separately in `docs/RISKS.md`.

- **OD3: Distribution.** How the app is distributed: Developer ID, the Mac App Store, or local builds only. Both of the first two need the renewed paid membership (D11). The supported versions are decided (D12).
- **OD4: Defaults chosen by an agent.** Confirm or change: FR5's warning on, FR6's phrase list empty, FR8's view and download links, FR9's all-files links off, the email saying that links need a password (FR7), and folder names `<yyyy-MM-dd> <subject>` ([ARCHITECTURE.md](ARCHITECTURE.md#using-nextcloud)).
- **OD5: Proposed requirements.** Confirm or change the non-functional requirements and the out-of-scope list in the PRD.
- **OD6: Testing "Don't ask again".** Whether to test it in Mail's Mail Drop prompt, knowing it changes the account's behaviour and may be hard to undo (R2).
- **OD8: Changing the test server's sharing settings.** The test account is an admin. Testing an enforced expiry maximum and enforced passwords means switching those on for the whole test server for a few minutes, through Nextcloud's admin API, and back off afterwards. Allowed or not? Without it, those two tests stay untested (R19).
- **OD9: Staying within Nextcloud's share limit.** Nextcloud allows each user 20 new shares in 10 minutes (R21). With a share per file and one for the folder, an email with 20 files, or a few emails in a row, can't be sent. Options:
  - **(a) A share per file, as now.** FR8's View links show each file. Emails with many files fail, so the setup help tells admins to raise the limit.
  - **(b) One folder share per email.** Each file's Download link is the folder's `/download?files=<name>`, and its View link opens the folder's page, which lists the files. One share per email allows 20 emails in 10 minutes, and FR9's links come for free. Whether a View link can open the one file in that page, and whether `?files=` survives the password page, is still to test.
  - **(c) A share per file while an email has few files, and the folder share alone above that.** It doesn't help with several emails in a row, because the server doesn't say how many shares are left.
  - Recommendation: (b), with the admin setting in the setup help for (a)'s users. T5 needs this decided.

## ✔️ Shared Definition of Done (every task)

- `scripts/lint.sh` passes.
- The project builds with no new warnings, and the unit tests pass.
- The PRD's acceptance criteria for the task's requirements are met.
- If the task touches sending, the matching Mail checks in `docs/TESTING.md` pass, and the Done note lists them.
- The docs say what changed: ARCHITECTURE.md for the design, MAIL.md or NEXTCLOUD.md for new facts, RISKS.md for risks touched, and DECISIONS.md for settled choices.
- Nothing secret or personal is committed. Test results stay in ignored folders.
- Signed commits on `agent/<short-task>`, merged into main only when the user says so.

## 📋 Backlog (To Be Done)

- **T2: Settings and login (FR2).** The host app's settings UI, Nextcloud's browser login, the app password in the Keychain, and settings shared through the App Group. A "Test connection" button that makes the extension itself reach the server (R17, R18).
  - **Acceptance:** the extension reads the settings and the app password, and reaches the server.
- **T9b: Check AGENTS.md in each agent tool (needs the user).** Open the repository once in each tool you use, ask what the repository's instructions say about commits, and note any tool that doesn't know. Claude Code 2.1.310 is checked, because this session loaded AGENTS.md. For Copilot in VS Code, `chat.useAgentsMdFile` must be on.
  - **Acceptance:** each tool you use answers from AGENTS.md, or D15 records what it needs.
- **T3b: Enforced server settings (needs OD8).** Server tests with an enforced expiry maximum and enforced passwords, switched on for the test run and off again (R19).
  - **Acceptance:** both behave as NEXTCLOUD.md says, or NEXTCLOUD.md is corrected, and the test server's settings are back as they were.
- **T5: Send flow (FR1, FR10).** `encode()` with the upload ledger, the failure memo and the Mail Drop clean-up, with files decoded to temporary files (R5). Needs OD9. Deleted files go to the trash bin, where they still count against the quota (NEXTCLOUD.md).
  - **Acceptance:** the send-flow Mail checks pass, and the delivered links work in Apple Mail, Gmail and Outlook.
- **T6: Password popover (FR7).** The popover's password field, kept per message in memory and the Keychain (R8).
  - **Acceptance:** the password Mail checks pass, and the links need the password.
- **T7: Send warnings (FR5, FR6).** Both warnings in the send check (R10).
  - **Acceptance:** the send-warning Mail checks pass.
- **T8: Progress display.** A notification when uploads start and finish, or the host app's window (R3).
  - **Acceptance:** a slow upload shows progress, and its end, without the user having to watch Mail.

## ✅ Completed Tasks (Done)

- **Probing Mail with MailProbe (2026-11-05).** Four rounds of tests found what Mail does with an extension. See `probe/docs/` and `docs/MAIL.md`.
- **T1b: Check T1 in Mail (2026-11-06).** The user enabled the extension in Mail, chose it for message security, and checked that Sign is offered and that the popover shows the values the host app wrote. Verified: with this Mac registered with the Personal Team (D16) and `keychain-access-groups` added to both targets, `--check-storage` passes for the container, the settings and the Keychain item. The extension's read of the Keychain item is checked by T2's Test connection.
- **T9: AGENTS.md in every agent tool (2026-11-06).** Verified from each tool's docs that all eleven read a root `AGENTS.md`, recorded in D15. `CLAUDE.md` imports it for older Claude Code versions. Claude Code 2.1.310 loaded AGENTS.md in this session. The check in the other tools moved to T9b.
- **T3: Nextcloud client (2026-11-06).** Verified: `scripts/test-nextcloud.sh` passes 7 server tests on the test server, Nextcloud 35.0.2. They cover the browser login's start, app passwords and revoking them, folders, uploads that refuse to overwrite, shares with working view and download links, expiry dates, share passwords and the policy's refusal, password pages, the folder zip, one file from a folder share, and deletes. `swift test` passes 63 unit tests, lint is clean, the build has no warnings, and `scripts/nextcloud.sh` runs requests by hand. NEXTCLOUD.md records what the server did, including the limit of 20 new shares in 10 minutes (OD9, R21). The enforced settings moved to T3b.
- **T4: Rewriter and link policy (2026-11-06).** Verified: `swift test` passes 46 tests over 12 anonymised fixtures. They cover every structure in MAIL.md: links in place in plain, rich, forwarded and first-call messages, the fallback list, folder links and the password notice above quotes, the size rule keeping other files byte for byte, signature and pasted images, accented names, and a message that is only a file. Unchanged messages come out byte for byte the same. Rewritten fixtures parse without defects in Python's `email` package. Lint is clean, the build has no warnings, and the storage check is unchanged.
- **T1: Project skeleton (2026-11-06).** Verified: `scripts/build.sh` builds both targets signed with the Personal Team, with no warnings. `swift test` passes 4 tests, `scripts/lint.sh` is clean, and `scripts/install.sh` installs and registers the extension. The storage check passes for the App Group's container and settings, but not for the shared Keychain item, which needs OD7. The checks in Mail moved to T1b.
