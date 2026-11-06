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

None. T6 is next. T5c waits for the user, or for Accessibility.

## ❓ Open Decisions (human to resolve)

Agents: do not guess these. Record questions here and stop.
Judgment calls and known risks are tracked separately in `docs/RISKS.md`.

- **OD3: Distribution.** How the app is distributed: Developer ID, the Mac App Store, or local builds only. Both of the first two need the renewed paid membership (D11). The supported versions are decided (D12).
- **OD4: Defaults chosen by an agent.** Confirm or change: the upload directory "Mail attachments" (FR2), all attachments becoming links (FR3), links expiring in a month (FR4), FR5's warning on, FR6's phrase list empty, FR8's view and download links, FR9's all-files links off, the list of file names above the folder's links when FR8 gives only those (D17), the email saying that links need a password (FR7).
- **OD5: Proposed requirements.** Confirm or change the non-functional requirements and the out-of-scope list in the PRD.
- **OD6: Testing "Don't ask again".** Whether to test it in Mail's Mail Drop prompt, knowing it changes the account's behaviour and may be hard to undo (R2).

- **OD10: View links for one file in a shared folder.** Nextcloud 35 can't open one file of a folder share in its viewer from a link: the public page opens the viewer only for a share of a single file, and takes no file from the URL (checked in its source, apps/files_sharing/src/init-public.ts). With one link for the email's folder, each file's View link therefore opens the folder's page. Options:
  - **(a) Keep it,** and the recipient clicks the file in the folder's page.
  - **(b) A share of its own for each file a browser or Nextcloud can show,** such as text, images, PDFs and office documents, used only for View. That opens Nextcloud's viewer, at the cost of a share each, so an email with many images can reach the limit of 20 new shares in 10 minutes (R21).
  - **(c) View shows the file itself in the browser,** from the folder share's WebDAV address, which Nextcloud serves without forcing a download. That's the browser's own display, not Nextcloud's viewer, it doesn't work for every type, and on a share with a password the browser asks for a user name, "anonymous", and the password.
  - Recommendation: (b) for shares without a password and (a) with one, if the share limit is acceptable, or (a) alone.

## ✔️ Shared Definition of Done (every task)

- `scripts/lint.sh` passes.
- The project builds with no new warnings, and the unit tests pass.
- The PRD's acceptance criteria for the task's requirements are met.
- If the task touches sending, the matching Mail checks in `docs/TESTING.md` pass, and the Done note lists them.
- The docs say what changed: ARCHITECTURE.md for the design, MAIL.md or NEXTCLOUD.md for new facts, RISKS.md for risks touched, and DECISIONS.md for settled choices.
- Nothing secret or personal is committed. Test results stay in ignored folders.
- Signed commits on `agent/<short-task>`, merged into main only when the user says so.

## 📋 Backlog (To Be Done)

- **T5c: The rest of T5's Mail checks (needs the user, or Accessibility for the agent).** What AppleScript alone can't do (docs/TESTING.md): an upload failure's alert (t7), Undo Send and sending again (t21), Send Later (t22), an email over the account's size limit with Try Sending in Email (t38) and with Use Mail Drop (t39), a pasted image (t30), a reply's links above its quote (t34, since AppleScript replies have no quote), and the delivered emails in Gmail on the web and Outlook, clicking each link.
  - **Acceptance:** FR1's failure case, FR8's display in the three clients and FR10's criteria hold, and nothing uploaded for the Mail Drop email is left on Nextcloud.
- **T6: Password popover (FR7).** The popover's password field, kept per message in memory and the Keychain (R8).
  - **Acceptance:** the password Mail checks pass, and the links need the password.
- **T7: Send warnings (FR5, FR6).** Both warnings in the send check (R10).
  - **Acceptance:** the send-warning Mail checks pass.
- **T8: Progress display.** A notification when uploads start and finish, or the host app's window (R3).
  - **Acceptance:** a slow upload shows progress, and its end, without the user having to watch Mail.
- **T9b: Check AGENTS.md in each agent tool (needs the user, optional).** At the end of the project, if at all (the user's choice). Open the repository once in each tool you use, ask what the repository's instructions say about commits, and note any tool that doesn't know. Claude Code 2.1.310 is checked, because this session loaded AGENTS.md. For Copilot in VS Code, `chat.useAgentsMdFile` must be on.
  - **Acceptance:** each tool you use answers from AGENTS.md, or D15 records what it needs.

## ✅ Completed Tasks (Done)

- **Probing Mail with MailProbe (2026-11-05).** Four rounds of tests found what Mail does with an extension. See `probe/docs/` and `docs/MAIL.md`.
- **T5b: Check T5 in Mail (2026-11-06).** Run by the agent through AppleScript, with `tests/mail-checks.py` between the two accounts in `.env`. All 11 checks passed on the final build: the folder's links where each file was, only the folder's links with the zip, a link for each file with the all-files links and zip, download links only, the size rule keeping a small file byte for byte, names with `#`, `%`, accents and `&`, a file attached twice uploaded once, a signature image staying, a 12 MB file arriving 27 seconds after sending, a reply and a forward. Each link downloaded the original bytes and each Sent copy matched what arrived. The checks found and fixed four faults: a new build's first local network request is refused (retried now), signature images lose their Content-IDs in the second call when there's another file (known by their bytes now), files next to each other ran their links together in the plain text, and AppleScript's text counted as a quote. What needs Mail's windows moved to T5c.
- **T2b: Check T2 in Mail (2026-11-06).** Done by the user: allowed NextcloudAppleMail's local network access when macOS asked, Test from Mail passed, and the browser login stored the account. The app's check afterwards showed the browser login's account on the test server.
- **T5: Send flow (2026-11-06).** Verified: `swift test` passes 106 unit tests. Against a fake Nextcloud, they cover both send calls uploading once, auto-saves, messages without files, not being logged in, a failure repeated for the next call only and forgotten after a minute, a retry uploading only what failed, Mail Drop's two signals, signature images carried from the first call, two calls for one message at once, each sharing setting, the server's password and expiry rules, taken names, and a file attached twice. `scripts/test-nextcloud.sh` passes 9 server tests, now with one file of a password-protected folder share. That test found that Nextcloud's redirect breaks names with `#`, `%` or `?`, which folder shares now replace (NEXTCLOUD.md). The fixtures now keep a file the same in both calls, as Mail does. The build has no warnings and lint is clean. The Mail checks moved to T5b, and the build isn't installed.
- **T3b: Enforced server settings (2026-11-06).** Verified: `scripts/test-nextcloud.sh --server-settings` passes 2 tests on the test server. With a 7-day maximum enforced, the capabilities report it, "no expiry" becomes the maximum, a later date gets 404 with the server's reason, and `LinkExpiry` shortens a year to the maximum, which the server accepts. With passwords enforced, the capabilities report it, a share without one gets 403 with the server's reason, and one with a password works. The settings were put back, checked by listing the server's keys, and `scripts/test-nextcloud.sh` still passes 8 tests. NEXTCLOUD.md has the keys and the HTTP statuses.
- **T2: Settings and login (2026-11-06).** Verified: `swift test` passes 79 unit tests, covering the settings' defaults, stored settings that are old, partial or unreadable, the upload directory, the server address check, Test from Mail's request and answer, and the offline error. `scripts/test-nextcloud.sh` passes 8 server tests, now with the connection check. The build has no warnings and lint is clean. With the installed Debug build, `scripts/use-test-account.sh` stored the test account in the shared Keychain item, and `--check-connection` read it back and reached Nextcloud 35.0.2. `--check-from-mail` got the extension's answer from Mail, with the settings and app password the extension read itself, but Local Network privacy had blocked its request to the test server ([MAIL.md](MAIL.md#network), R18). The host app now declares `NSLocalNetworkUsageDescription`. The window, the browser login and Test from Mail with Local Network allowed moved to T2b.
- **T1b: Check T1 in Mail (2026-11-06).** The user enabled the extension in Mail, chose it for message security, and checked that Sign is offered and that the popover shows the values the host app wrote. Verified: with this Mac registered with the Personal Team (D16) and `keychain-access-groups` added to both targets, `--check-storage` passes for the container, the settings and the Keychain item. The extension's read of the Keychain item is checked by T2's Test connection.
- **T9: AGENTS.md in every agent tool (2026-11-06).** Verified from each tool's docs that all eleven read a root `AGENTS.md`, recorded in D15. `CLAUDE.md` imports it for older Claude Code versions. Claude Code 2.1.310 loaded AGENTS.md in this session. The check in the other tools moved to T9b.
- **T3: Nextcloud client (2026-11-06).** Verified: `scripts/test-nextcloud.sh` passes 7 server tests on the test server, Nextcloud 35.0.2. They cover the browser login's start, app passwords and revoking them, folders, uploads that refuse to overwrite, shares with working view and download links, expiry dates, share passwords and the policy's refusal, password pages, the folder zip, one file from a folder share, and deletes. `swift test` passes 63 unit tests, lint is clean, the build has no warnings, and `scripts/nextcloud.sh` runs requests by hand. NEXTCLOUD.md records what the server did, including the limit of 20 new shares in 10 minutes (R21, D17). The enforced settings moved to T3b.
- **T4: Rewriter and link policy (2026-11-06).** Verified: `swift test` passes 46 tests over 12 anonymised fixtures. They cover every structure in MAIL.md: links in place in plain, rich, forwarded and first-call messages, the fallback list, folder links and the password notice above quotes, the size rule keeping other files byte for byte, signature and pasted images, accented names, and a message that is only a file. Unchanged messages come out byte for byte the same. Rewritten fixtures parse without defects in Python's `email` package. Lint is clean, the build has no warnings, and the storage check is unchanged.
- **T1: Project skeleton (2026-11-06).** Verified: `scripts/build.sh` builds both targets signed with the Personal Team, with no warnings. `swift test` passes 4 tests, `scripts/lint.sh` is clean, and `scripts/install.sh` installs and registers the extension. The storage check passes for the App Group's container and settings, but not for the shared Keychain item, which needs OD7. The checks in Mail moved to T1b.
