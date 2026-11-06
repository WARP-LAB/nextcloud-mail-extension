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

None. T1b waits for the user, and T2 and T3 for the Nextcloud test server (OD2).

## ❓ Open Decisions (human to resolve)

Agents: do not guess these. Record questions here and stop.
Judgment calls and known risks are tracked separately in `docs/RISKS.md`.

- **OD2: Nextcloud test server and account.** Needed for T2 and T3.
- **OD3: Distribution.** How the app is distributed: Developer ID, the Mac App Store, or local builds only. Both of the first two need the renewed paid membership (D11). The supported versions are decided (D12).
- **OD4: Defaults chosen by an agent.** Confirm or change: FR5's warning on, FR6's phrase list empty, FR8's view and download links, FR9's all-files links off, the email saying that links need a password (FR7), and folder names `<yyyy-MM-dd> <subject>` ([ARCHITECTURE.md](ARCHITECTURE.md#using-nextcloud)).
- **OD5: Proposed requirements.** Confirm or change the non-functional requirements and the out-of-scope list in the PRD.
- **OD6: Testing "Don't ask again".** Whether to test it in Mail's Mail Drop prompt, knowing it changes the account's behaviour and may be hard to undo (R2).
- **OD7: Registering this Mac with the Personal Team.** The shared Keychain item for the app password needs a provisioning profile, which Xcode can only create once this Mac is registered as a device with the team: by building once in Xcode's window, or with `xcodebuild -allowProvisioningDeviceRegistration` (R17). The alternative is the fallback in R17. Needed for T1b and T2.

## ✔️ Shared Definition of Done (every task)

- `scripts/lint.sh` passes.
- The project builds with no new warnings, and the unit tests pass.
- The PRD's acceptance criteria for the task's requirements are met.
- If the task touches sending, the matching Mail checks in `docs/TESTING.md` pass, and the Done note lists them.
- The docs say what changed: ARCHITECTURE.md for the design, MAIL.md or NEXTCLOUD.md for new facts, RISKS.md for risks touched, and DECISIONS.md for settled choices.
- Nothing secret or personal is committed. Test results stay in ignored folders.
- Signed commits on `agent/<short-task>`, merged into main only when the user says so.

## 📋 Backlog (To Be Done)

- **T1b: Check T1 in Mail (needs the user).** Enable NextcloudAppleMail in Mail's Settings > Extensions, choose it for message security, and restart Mail. Once OD7 is settled, add the `keychain-access-groups` entitlement back and rerun the storage check.
  - **Acceptance:** Mail lists the extension, Sign is offered while the extension reports `canSign: true` and `canEncrypt: false` (R9), the toolbar popover shows the container and settings values the host app wrote, and the storage check passes, or the Keychain fallback is recorded in DECISIONS.md.
- **T2: Settings and login (FR2).** The host app's settings UI, Nextcloud's browser login, the app password in the Keychain, and settings shared through the App Group. A "Test connection" button that makes the extension itself reach the server (R17, R18).
  - **Acceptance:** the extension reads the settings and the app password, and reaches the server.
- **T3: Nextcloud client (FR1, FR2, FR4, FR7, FR9).** Every request in `docs/NEXTCLOUD.md`, with a small command-line tool to run them, tested against the test server (OD2, R19).
  - **Acceptance:** the Nextcloud tests in `docs/TESTING.md` pass, and NEXTCLOUD.md records what the server really did.
- **T4: Rewriter and link policy (FR3, FR8, FR9).** Links in place, the fallback list, folder links, and `LinkPolicy` with the pasted-images setting and signature images (R6, R7, R16).
  - **Acceptance:** unit tests with anonymised fixtures cover every structure in `docs/MAIL.md`.
- **T5: Send flow (FR1, FR10).** `encode()` with the upload ledger, the failure memo and the Mail Drop clean-up, with files decoded to temporary files (R5).
  - **Acceptance:** the send-flow Mail checks pass, and the delivered links work in Apple Mail, Gmail and Outlook.
- **T6: Password popover (FR7).** The popover's password field, kept per message in memory and the Keychain (R8).
  - **Acceptance:** the password Mail checks pass, and the links need the password.
- **T7: Send warnings (FR5, FR6).** Both warnings in the send check (R10).
  - **Acceptance:** the send-warning Mail checks pass.
- **T8: Progress display.** A notification when uploads start and finish, or the host app's window (R3).
  - **Acceptance:** a slow upload shows progress, and its end, without the user having to watch Mail.
- **T9: AGENTS.md in every agent tool.** Check which of the eleven agent tools in `writing-agent-skills` read `AGENTS.md` themselves, and add a pointer file for those that don't.
  - **Acceptance:** each tool loads the repository's instructions, checked once in each.

## ✅ Completed Tasks (Done)

- **Probing Mail with MailProbe (2026-11-05).** Four rounds of tests found what Mail does with an extension. See `probe/docs/` and `docs/MAIL.md`.
- **T1: Project skeleton (2026-11-06).** Verified: `scripts/build.sh` builds both targets signed with the Personal Team, with no warnings. `swift test` passes 4 tests, `scripts/lint.sh` is clean, and `scripts/install.sh` installs and registers the extension. The storage check passes for the App Group's container and settings, but not for the shared Keychain item, which needs OD7. The checks in Mail moved to T1b.
