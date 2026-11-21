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

## D15: AGENTS.md is the one instruction file (2026-11-06)

- **Decision:** every agent tool gets its instructions from `AGENTS.md` at the repository root. `CLAUDE.md` only imports it, with `@AGENTS.md`. No other pointer files.
- **Why:** each of the eleven tools in the `writing-agent-skills` skill reads a root `AGENTS.md` itself, checked in their docs on 2026-11-06:

  | Tool | How it reads AGENTS.md |
  | --- | --- |
  | OpenCode | [Rules](https://opencode.ai/docs/rules): `AGENTS.md` first, `CLAUDE.md` only without one |
  | Command Code | [Memory](https://commandcode.ai/docs/reference/memory): `./AGENTS.md` or `./.commandcode/AGENTS.md` |
  | Cline | [Cline rules](https://docs.cline.bot/features/cline-rules/overview): after `.clinerules`, and always |
  | Kilo Code | [AGENTS.md](https://kilo.ai/docs/customize/agents-md): the root file, and per folder when reading files there |
  | Pi | Loads `AGENTS.md` from the current and parent directories at startup, and lists them in its header |
  | Claude Code | [Memory](https://code.claude.com/docs/en/memory#agents-md): from v2.1.277, when there's no `CLAUDE.md`. Older versions, and some sessions, read only `CLAUDE.md`, hence the import, which never loads the file twice |
  | OpenAI Codex | The tool `AGENTS.md` comes from |
  | GitHub Copilot | The coding agent, and VS Code with its `chat.useAgentsMdFile` setting on |
  | Cursor | [Rules](https://cursor.com/docs/rules): a root `AGENTS.md`, as an alternative to `.cursor/rules` |
  | Cognition Devin | Reads `AGENTS.md` at the repository root once the repository is indexed |
  | Amazon Kiro | Steering: a root `AGENTS.md` is always included |

  One file means the instructions can't drift apart. A tool-specific file would only be needed for rules that differ by tool, and there are none.

## D16: Register this Mac with the Personal Team (2026-11-06)

- **Decision:** this Mac is registered as a device with the free Personal Team, which resolves OD7. Xcode then makes a provisioning profile for each target, so both targets can have `keychain-access-groups` with `<team ID>.lv.warp.nextcloudmailextension`, the App Group's identifier, and share the app password's Keychain item.
- **Why:** the user's choice. The alternative was R17's fallback, logging in from the extension.
- **How:** registering needs a build with a destination, given in AGENTS.md's setup. Building in Xcode's window before the entitlement was added didn't register the Mac, because nothing needed a profile then. The Personal Team's profiles last 7 days, and `scripts/build_app.sh` renews them with `-allowProvisioningUpdates`.

## D17: Share the email's folder, or each file (2026-11-06)

- **Decision:** a setting chooses how an email's files are shared, which resolves OD9:
  - **One share for all files in the email,** the default: one public share per email, of its folder. Each file's view link is the folder's page and its download link is the folder share's `/download?files=<name>`. A second setting chooses where each file's links go, which D28 extends to both kinds of share.
  - **Separate share for each file in the email:** a share per file, plus one for the folder when FR9's setting is on.
- **Why:** the user's choice. Nextcloud allows each user 20 new shares in 10 minutes (R21). One share per email allows 20 emails in that time, however many files they have, and FR9's links need no extra share. A share per file gives each file a page of its own, for servers whose admin has raised the limit.

## D18: Tests may change the test server's sharing settings (2026-11-06)

- **Decision:** server tests may switch on an enforced expiry maximum and enforced passwords on the test server for the length of a run, through Nextcloud's admin API, and switch them back to what they were at the end. This resolves OD8.
- **Why:** the user's choice. It's the only way to test those two (R19), and the test account is an admin.
- **How:** the changes ask for the password to be confirmed, which an app password can't do, so these admin requests alone use the account password from `.env`. They run only with `scripts/test-nextcloud.sh --server-settings`, which runs nothing else, because other tests running at the same time would see the changed settings.

## D19: Folder names carry the time (2026-11-06)

- **Decision:** each email's folder is named `<yyyy-MM-dd-HH-mm-ss> <subject>`, such as `2026-11-05-14-03-09 Report`, in the Mac's time zone, at the time of the first send call. This replaces the date alone of D5's naming in ARCHITECTURE.md.
- **Why:** the user's choice, so that emails with the same subject on one day don't share a name. They offered this or a date with a short UUID, and the time was chosen because it stays readable and sorts by time. There's no `T` and no colons, which paths don't take well. If two folders still get the same name, a number is added.

## D20: View links in a shared folder open the folder (2026-11-06)

- **Decision:** with one share for all files in the email (D17), each file's View link opens the folder's page, where the recipient clicks the file. This resolves OD10, and may be revisited.
- **Why:** the user's choice. Nextcloud 35 can't open one file of a folder share in its viewer from a link: the public page opens the viewer only for a share of a single file, and takes no file from the URL (`apps/files_sharing/src/init-public.ts`). The rejected options, recorded for a later look:
  - A share of its own for each file that Nextcloud can show, used only for View. It opens the viewer, but costs a share each, which brings back the limit of 20 new shares in 10 minutes (R21).
  - View showing the file itself from the folder share's WebDAV address. That's the browser's display, not Nextcloud's viewer, and with a password the browser asks for the user name "anonymous" and the password. It only seemed to work because the test server ran in debug mode; without it Nextcloud sends `Content-Disposition: attachment`, so the file downloads.
- **Revisit when:** a Nextcloud version lets a link open one file of a folder share, or recipients find the folder page confusing.
- **Rechecked** (2026-11-07, Nextcloud 35, debug mode off): the public page's router has only `/s/:token`, so no address names a file of a folder share. So that it doesn't promise the file, the email calls this link "Overview", and keeps "View" for a file's own share (the user's choice).

## D21: The defaults (2026-11-06)

- **Decision:** the user confirmed the defaults that an agent had chosen, which resolves OD4, and changed one: the upload directory is `MailAttachments`, without a space. The others stay: all attachments become links (FR3), links expire in a month (FR4), FR5's warning is on, FR6 has no phrases, each file gets view and download links (FR8), the all-files links are off (FR9), the email says that the links need a password without containing it (FR7), with only the folder's links the files' names and sizes are listed (D17), and upload notifications appear only after 2 seconds (T8).
- **Why:** the user's choice. A name without spaces reads better in paths and URLs.

## D22: Versions follow SemVer, with ZeroVer until 1.0.0 (2026-11-06)

- **Decision:** the version follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html), and [ZeroVer](https://0ver.org) (`0.y.z`) during early development: there, MINOR goes up for new features and breaking changes, and PATCH for fixes. Only the user decides a major release, including the first `1.0.0`. The version is `MARKETING_VERSION` in the project file, which becomes `CFBundleShortVersionString`, and it's always `MAJOR.MINOR.PATCH`, so `0.1` became `0.1.0`. `CURRENT_PROJECT_VERSION`, which becomes `CFBundleVersion`, is the build number, and goes up with every build that's distributed. Releases are tagged `v<version>`. The app shows both in its window's footer.
- **Why:** the user's choice, as set out in the versioning skill (`~/.agents/skills/versioning/`). Apple allows up to three integers in `CFBundleShortVersionString`, without a pre-release part, so that matches SemVer's core. The version stays in the project file, where Xcode's General tab and `agvtool` change it.

## D23: The settings' wording (2026-11-06)

- **Decision:** the user chose these labels: "Nextcloud shares", in a Sharing section above Links, offers "One share for all files in the email" and "Separate share for each file in the email", with a warning about Nextcloud's share limit under the second. The user renamed them on 2026-11-07 from "Share files as", "One link for all files in the email" and "A link for each file", because one share can still give each file its own links. With one share, "Place links" offers "Inline, where each file was" and "Below your text". FR6's field is "Warn if the email's text includes a phrase but there's no attachment". FR9's switch is "If multiple attachments, also add links for all files below your text" (2026-11-07): it adds two links, one viewing and one downloading all files, and they go above any quoted message, not at the very bottom. The UI and docs keep the word "folder" for a folder on Nextcloud, and "directory" for the upload directory that holds each email's folder.
- **Why:** the user's choice. "Folder" is the word macOS, Apple's Human Interface Guidelines and Nextcloud's own interface use. "Below your text" fits replies and forwards too, where the links go above the quoted message rather than at the bottom.

## D24: Each email chooses which files become links (2026-11-06)

- **Decision:** the popover's first block, "For this email", chooses for the email: "Use settings", the default, "All files via Nextcloud", which ignores the size limit and the pasted-images setting, so pasted images become links too, or "All files kept as attachments", which uploads nothing. The user chose these labels. Images in the signature stay in the email even with all files, as FR3 says they always do. With the files kept, the password and expiry are greyed out, and after Undo Send what the earlier send uploaded is deleted, while the email's popover values are kept.
- **Why:** the user's request, so that one email can differ from the settings without changing them. The signature's images are part of the signature, not files the user attached, so an agent kept them out. Keeping the values lets the user undo again and change their mind without typing the password again.

## D25: Publish with Nextcloud's logo, and ask for permission meanwhile (2026-11-06)

- **Decision:** the project is pushed with Nextcloud's mark as the toolbar and app icons and with Nextcloud in its name, and the user asks Nextcloud GmbH for permission at the same time (T13b). If Nextcloud GmbH objects, the icons are replaced and the project is renamed. This resolves OD11.
- **Why:** the user's choice, accepting that Nextcloud GmbH may ask for changes. Its trademark guidelines allow the logos only as links to nextcloud.com, and say that third-party apps shouldn't have its mark in their name, and `LICENSE.Nextcloud` says so. The artwork is in three places, so replacing it is one change (R22).

## D26: The product is NextcloudMailExtension (2026-11-06)

- **Decision:** the product was NextcloudAppleMail and is now NextcloudMailExtension, as the user renamed the GitHub repository from `nextcloud-apple-mail` to `nextcloud-mail-extension`. The app is `NextcloudMailExtension.app` and its Mail extension `NextcloudMailExtensionPlugIn.appex`. The bundle IDs, App Group and Keychain services start `lv.warp.nextcloudmailextension` instead of `lv.warp.nextcloudapplemail`. The Swift package's modules are `NextcloudMailExtensionShared` and its tests, the abbreviation `ncam` became `ncme`, and the `.env` keys start `NCME_`. This resolves OD12.
- **Why:** the user's choice. Apple's trademark guidelines don't allow Apple in a third party's product name. The extension isn't called `NextcloudMailExtensionExtension`, which reads twice. It was briefly `NextcloudMailExtensionAppex`, and the user renamed it `NextcloudMailExtensionPlugIn`, because System Settings can list it by that name under Local Network, where "plug-in" means something to users and "appex" doesn't. Mail itself shows it under the app's name. New bundle IDs make a new app for macOS: it doesn't see the old app's login, settings or Keychain items, Mail lists its extension as a new one to enable, and macOS asks again for notifications and the local network.

## D27: No Local Network usage text, and the popover checks the connection (2026-11-07)

- **Decision:** neither the app's nor the extension's `Info.plist` has `NSLocalNetworkUsageDescription`. The popover checks the connection quietly as it opens, and shows only a problem, in red: the Local Network refusal, or the server's error. The setup help tells users to open the toolbar button once and allow the extension when macOS asks.
- **Why:** with the key, macOS made the app a Local Network rule at install and refused the extension's requests even with the app allowed, without asking. Without it, macOS asks for the app and for the extension separately, and both work (T14, [MAIL.md](MAIL.md#network)). A send never makes macOS ask, so the popover's check is how the extension gets asked. The user chose the design: no button, nothing shown when the check passes.

## D28: "Place links" decides only where each file's links go (2026-11-07)

- **Decision:** with either kind of Nextcloud share, "Place links" puts each file's links where the file was, or lists each file with its name, size and links below the user's text. "Link types for files", which was "Show download link for file", offers "Download only" and "View and download" and applies to both. The links for all files are added for two or more files, when their switch is on or the links go below the text, where the switch is greyed out; for one file they're never added. The placement is still stored as `folderLinksOnly`, so stored settings keep it. This replaces D17's "only the folder's links", and D21's listing of names and sizes without links.
- **Why:** the user's rule, so that each setting does one thing and only the switch is ever greyed out. The list below the text helps a reader find every file, and each listed file's own links make the links for all files unnecessary for one file.

## D29: Tests may take the test server down, and always bring it back (2026-11-07)

- **Decision:** `scripts/server-state.sh` may switch the test server into maintenance mode, take its PHP-FPM pool down, or switch its site off in nginx, over SSH with the `NCSERVER_*` keys in `.env`. Its `with <state> -- <command>` restores everything afterwards, also when the command fails or is interrupted, PHP-FPM first. Restarting PHP-FPM restarts every pool of that PHP version on the server, and reloading nginx reloads every site.
- **Why:** the user's request, to see what users get when the server is unavailable (T21). The user set up the SSH access for it.

## D30: The website is built from `site/` by a GitHub Actions workflow (2026-11-08)

- **Decision:** the project's website, for users, is the Markdown in `site/`, with its screenshots in `site/media/screenshots/`. `.github/workflows/pages.yml` builds it with GitHub's `jekyll-build-pages` action, which uses GitHub Pages' own Jekyll setup and its default theme, and deploys it to GitHub Pages. It runs on pushes to main that change `site/` or the workflow, and by hand. `site/_config.yml` keeps the screenshots' notes, `SCREENSHOTS.md`, out of the site. `site/_layouts/default.html` replaces the theme's own layout, which Jekyll prefers, so the footer links to the repository as "Source" rather than to the page's edit page as "Improve this page". The screenshots are 2x, so each image in `site/index.md` sets `width` to half its pixel width with a kramdown attribute list (`{: width="833"}`), and the theme's `max-width: 100%` shrinks it on narrower windows. `site/assets/css/style.scss` replaces the theme's stylesheet: it imports the theme and centres the screenshots.
- **Why:** the user chose `site/` as the website's source (T25). Publishing from a branch takes only the repository's root or `docs/`, and `docs/` holds the developer docs, so a workflow publishes it. GitHub's own actions need no Gemfile and add no dependencies to the project.

## D31: The website's search and preview details live in `site/_config.yml` (2026-11-11)

- **Decision:** `site/_config.yml` sets the website's title, description, preview image and keywords. The theme's `jekyll-seo-tag` writes the title, the description and the image into the page's `<head>`, also as Open Graph and Twitter tags for link previews. It writes no keywords, so `site/_includes/head-custom.html`, which replaces the Primer theme's own, writes a `keywords` meta tag from the page's `keywords` front matter or else the site's. `jekyll-sitemap` writes `sitemap.xml`. The preview image is the website's icon as a 1200 × 630 PNG on white, since link previews don't show SVG and may show transparency as black.
- **Why:** the user's request (T26). Search engines mostly ignore keywords, so the description, the title and the page's own text matter more, but the keywords are kept in one place for the user to manage. The title matches the page's heading, because otherwise the theme prints the site's title as a second heading.

## D32: One script builds, zips and installs (2026-11-21)

- **Decision:** `scripts/build_app.sh` takes `-c`/`--configuration debug|release` (default release), `-z`/`--zip yes|no` (default yes) and `-i`/`--install yes|no` (default no), and passes any other arguments to `xcodebuild`. Installing implies the zip, since the app is installed from it, and replaces `scripts/install.sh`, which is gone. With `--zip no` the bare bundle stays in `build/<configuration>/`, where macOS can take it for the installed app (AGENTS.md). The Mail checks, `scripts/use-test-account.sh` and the app's debug options need a Debug build, so the docs say `-c debug`.
- **Why:** the user's request, after the scripts were renamed from `build.sh` and `install.sh`. One command builds and installs, and its options match the user's other build scripts.

## D33: Distribute a notarized DMG on GitHub Releases (2026-11-21)

- **Decision:** the app is distributed as `dmg/NextcloudMailExtension.dmg`, attached to a GitHub release, signed with the team's Developer ID and notarized. This resolves OD3. `scripts/build_dmg.sh` builds Release with `scripts/build_app.sh`, unpacks the zip into a staging folder under `build/`, and with `--sign yes` checks that the app and the extension carry Developer ID, the hardened runtime, a secure timestamp, no `get-task-allow`, and a Developer ID provisioning profile for `keychain-access-groups`. With `--notarize yes` it notarizes and staples the app, packs it with a link to `/Applications` into a DMG whose volume is "Nextcloud Mail Extension" and the version, such as "Nextcloud Mail Extension 0.1.0", signs the DMG with the identity that signed the app, and notarizes and staples the DMG. `scripts/build_validate.sh` checks a finished DMG, also one downloaded from a release, the way a downloader's Mac would: the DMG's and the bundles' signatures, notarization tickets and Gatekeeper, Apple's `syspolicy_check`, the entitlements and the profiles that allow them, the App Group in `Info.plist`, the versions, and no `NSLocalNetworkUsageDescription` (D27). `scripts/build_publish.sh` releases the app's version, `MARKETING_VERSION`: after asking, it commits everything as `v<version>`, adds a signed tag, builds, notarizes and validates the DMG from that tree, and only then pushes `main` and the tag and creates the GitHub release, with the DMG and the version's CHANGELOG.md section as its notes. It stops first if that section is missing or the tag exists. The staging folder is unregistered and deleted on exit, also after a failure, and `scripts/build_app.sh` removes the bundles a failed build leaves. The Release signing lives in `Config/Local.xcconfig`, as `Config/Local.example.xcconfig` lists: Developer ID, hardened runtime, `--timestamp`, a Developer ID profile for each target, and `NOTARY_PROFILE`. Debug keeps the Personal Team (D11, D16). The project file no longer sets `ENABLE_HARDENED_RUNTIME`, which had overridden `Local.xcconfig`. `Config/Signing.xcconfig` turns off `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` for Release, since `xcodebuild build` otherwise signs Release with `get-task-allow` too.
- **Why:** the user's request. The paid membership is active again: the notary service accepted the team's submissions on 2026-11-20. `keychain-access-groups` needs a provisioning profile, and Xcode refuses a Developer ID build without one, so Release has Developer ID profiles rather than giving up the shared Keychain item (D16). The app is notarized on its own as well, so that it opens without a network check once it's copied out of the DMG. A DMG is signed with the Developer ID Application identity; the Developer ID Installer identity is for `.pkg` files only.
