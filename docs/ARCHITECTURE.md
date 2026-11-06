# Architecture

How to build the requirements in [PRD.md](PRD.md). Nothing of the real extension has been built yet, so this is a plan. It rests on facts recorded elsewhere:

- **Mail's behaviour:** [MAIL.md](MAIL.md), found by probing. `tN` refers to a probe test.
- **Nextcloud's API:** [NEXTCLOUD.md](NEXTCLOUD.md), read from the server's source.
- **Settled choices and why:** [DECISIONS.md](DECISIONS.md).
- **What could go wrong:** [RISKS.md](RISKS.md). `Rn` refers to a risk.

Anything here that doesn't cite a test is proposed and untried.

## Approach

The extension is a Mail message security extension (D1). At send, Mail passes the whole message to `encode()`. The extension uploads the files and returns a new message with links in their place, which Mail delivers. Mail calls `encode()` at send only while Sign is on, so Mail's Sign button is the upload switch. The extension can't turn it on, and FR5 warns about messages sent with it off.

The extension's toolbar button in the message window opens a popover, where the user types the email's password (FR7).

## Components

| Component | Runs in | Job | Starting point |
| --- | --- | --- | --- |
| Settings UI and login | Host app | Settings for FR2–FR6, FR8, FR9 and D17, Nextcloud login, Test connection and the setup help | Done: [App/](../App/) |
| `SecurityHandler` | Extension | Status, `encode()`, and stubs for decoding | Done: [SecurityHandler.swift](../Extension/SecurityHandler.swift), which hands each call to `Sender` |
| `ComposeHandler` | Extension | FR5 and FR6 warnings, the password popover (FR7) | Done: [ComposeHandler.swift](../Extension/ComposeHandler.swift), with `SendWarnings` in [Shared/Send/](../Shared/Send/) |
| `MimeMessage` | Extension | Parse the message and write it out again | Done: [Shared/Mime/](../Shared/Mime/) |
| `LinkPolicy` | Extension | Decide which files become links (FR3) and which count as attachments (FR6) | Done for FR3: [LinkPolicy.swift](../Shared/Links/LinkPolicy.swift) |
| `LinkRewriter`, `LinkText` | Extension | Put each file's links in the message (FR8), and the links to all files and the password notice (FR7, FR9) | Done: [Shared/Links/](../Shared/Links/) |
| `TextCheck` | Extension | Find FR6 phrases in the text the user wrote | Done: [TextCheck.swift](../Shared/Links/TextCheck.swift) |
| `NextcloudClient` | Both | Login, folders, uploads, shares, server limits | Done: [Shared/Nextcloud/](../Shared/Nextcloud/), with `LinkExpiry` (FR4) and `NextcloudNames` (FR2) |
| `Sender`, `SendFlow`, `UploadLedger` | Extension | Run each `encode()` call: the uploads, shares and links, the failure memo and the Mail Drop clean-up, with each message's folder and finished uploads remembered | Done: [Shared/Send/](../Shared/Send/), tested against a fake Nextcloud |
| `MessageValues` | Extension | What the popover sets for each email, its link choice, its password and its own expiry, with their Keychain copies | Done: [MessageValues.swift](../Shared/Send/MessageValues.swift) |
| `Settings`, `Credentials`, `ConnectionCheck` | Both | Shared settings, the app password, and the connection check | Done: [Shared/Settings/](../Shared/Settings/) |

The extension keeps both capabilities in its `Info.plist`: `MEMessageSecurityHandler` and `MEComposeSessionHandler`. The project copies code across from the probe as needed, leaving `ProbeDirective`, `ProbeLog` and the rest of MailProbe behind. Code that both the host app and the extension use lives in `Shared/`, which both targets compile and which also builds as a Swift package for its unit tests (D13).

## Send flow

`getEncodingStatus` reports `canSign: true` and `canEncrypt: false`. MailProbe only ever reported the two together (R9).

`encode()` runs these steps for each call, in `Sender`, which runs one call at a time:

1. If the message is an auto-save (`state` 1), link its `contextID` to its message ID (see [Passwords](#passwords-in-the-message-window-fr7)) and return nil. The draft keeps its files (t17).
2. Parse the message and let `LinkPolicy` pick the files, leaving out the signature images that the first call's HTML marked. If there are none, return nil, and Mail sends the message normally (t18). If nobody is logged in, stop the send with an error saying so.
3. Read the server's limits, and stop the send if it requires a password and there's none. Look up each file in the ledger. For any file not found, create the message's folder if needed, decode the file to a temporary file, upload it, create its share with the message's password if each file gets its own link, and add it to the ledger (R5). A name that's taken in the folder gets a number. The same file attached twice is uploaded once, and both get its links.
4. With one link for the email's folder, or when FR9 applies, share the folder once for the message (D17).
5. Replace each file with its links (FR8), add the folder links after the user's own text (FR9), and return `MEEncodedOutgoingMessage(rawData:, isSigned: false, isEncrypted: false)`. Keep all other headers, including `Bcc:`, which Mail removes itself (t19).
6. If anything failed, return a `signingError` naming the file and the server's message.

The first send call does the uploads and the second finds them all in the ledger, so the code doesn't need to tell the calls apart. Decoded files are byte-identical in both calls (t15). Returning rewritten bytes from both calls is the combination tested so far.

### Upload ledger

Each message ID maps to its folder, the folder's share if there is one, and its files. Files are keyed by the SHA-256 of the decoded file, and each records its remote path, share ID, URL and returned expiry date. The ledger is a JSON file in the extension's container, pruned after 30 days. It never holds passwords.

The key is the message ID, `X-Universally-Unique-Identifier`, because the `contextID` changes on a reopened draft and on Undo Send (t21, t26). Access is serialized per message, which costs little even though calls haven't overlapped.

The same key means Undo Send followed by a second send reuses the folder and links, and a retry after a partial failure uploads only the remaining files. If the password changed in between, update each of the message's shares (T6). `Sender` keeps the ledger in memory too, so a ledger that can't be saved still covers the second call.

### Failed uploads

After a failed upload, Mail still makes the second send call (t7, t8, t12). It shouldn't retry, because the send is already stopped and the user would wait through a second upload. Remember the failure per message, have the second call return the same error and clear it, so the next click on Send retries. Let the memo expire after a minute as a safeguard.

### Mail Drop (FR10)

If the user chooses Use Mail Drop, the first call has already uploaded the files, but the email goes out with Mail Drop's link (t39). When a later send call for the message has a `Remote-Attachment-Url` header, or has no files to link while the ledger has uploads for it, return nil and delete the message's folder, which deletes its files and shares too (D8). This also cleans up after Undo Send when the user removes every file before sending again.

## Rewriter

- **Selecting files:** `isAttachment` is true for any part with an attachment disposition or a filename, which includes signature images and pasted images. Signature images are inside `AppleMailSignature` in the first call's HTML, so the first call records their Content-IDs, and the SHA-256 of their bytes, for the second call, which may have them without Content-IDs ([MAIL.md](MAIL.md#message-structures)). Pasted images can only be told apart by Mail's `PastedGraphic-N.png` names (R7). Signature images never become links and don't count as attachments for FR6. Pasted images follow the FR3 rule when its pasted-images setting is on, which is the default, and stay in the email when it's off. They always count for FR6.
- **Measuring files:** the size rule uses decoded bytes, so a file exactly at the limit stays (t27, t28). `TransferEncoding.decodedSize` counts base64 characters instead of decoding the file.
- **Unchanged parts:** header fields, bodies, and each multipart's preamble and epilogue are kept as written. A message with nothing to change, and every part the rewriter doesn't touch, comes out byte for byte the same.
- **Links in place (FR8):** in a plain message, each file part becomes the link text, merged with the text parts on either side, so the delivered message has one text part instead of several and doesn't depend on how each mail client shows a run of text parts (R16). In the structure with a signature or pasted image, replace each `<img src="cid:…">` with the links and remove its part. Also replace the matching U+FFFC in the plain text, since they come in the same order as the images in the HTML (t30). Each file's links get lines of their own there, since files next to each other have touching placeholders. In the forward structure, replace U+FFFC in the plain text and the file part in the HTML. In the first call's structure, replace each `cid:` placeholder, which matters for FR6. In `multipart/mixed`, a file's own part marks where it was. Elsewhere, such as in `multipart/related`, a file whose placeholder isn't found goes in the fallback list. Each alternative of a `multipart/alternative` shows every linked file, in place or in its list.
- **Fallback list (FR8):** if a file's position can't be found, for example in a structure the tests haven't shown yet, its links go in a list at the end of the user's own text, never at the top.
- **End of the user's own text:** in HTML, this is before `<div class="AppleOriginalContents">` or the first `<blockquote type="cite">`, leaving out the blockquote of shared content inside `Apple-Mail-URLShareWrapperClass`. In plain text, it's before the first line starting with `>` (t20, t34). If no quote is found, it's the end of the message.
- **Folder links (FR9):** add them at the end of the user's own text, after any fallback list. The send flow passes them to the rewriter when FR9's setting is on and two or more files became links, or always when FR8's setting gives only the folder's links.
- **Below your text, with only the folder's links (FR8):** each linked file is removed as if it went to the fallback list, and the list names each file with its size, without links, above the folder links.
- **No text to add to:** a branch with no text part, which no test has shown, gets a new `text/plain` part with the links, so links are never lost.
- **Non-ASCII names:** every text part the rewriter changes is written as quoted-printable UTF-8, and the charset in the HTML's `<meta>` tags is changed to match. The probe replaced non-ASCII characters with `?`.
- **Message that is only a file:** its root becomes `text/plain` with the file's links, keeping the message's headers. Mail hasn't been seen to produce this.

### Link text

Each file shows its name on Nextcloud, its size and the expiry date the server returned. With the default settings, one link for the email's folder and both links for each file, the view link is the folder's page and the download link fetches just that file (D17):

```text
report.pdf (12 MB, link expires 12 Dec 2026)
View: https://cloud.example.com/s/xyz
Download: https://cloud.example.com/s/xyz/download?files=report.pdf
```

With a link for each file, the file has a share of its own:

```text
report.pdf (12 MB, link expires 12 Dec 2026)
View: https://cloud.example.com/s/abc
Download: https://cloud.example.com/s/abc/download
```

With only the folder's links, the files are listed above them:

```text
report.pdf (12 MB, link expires 12 Dec 2026)
photo.jpg (2 MB, link expires 12 Dec 2026)

View all files in email: https://cloud.example.com/s/xyz
Download all files in email: https://cloud.example.com/s/xyz/download
```

With download only:

```text
report.pdf (12 MB, link expires 12 Dec 2026): https://cloud.example.com/s/abc/download
```

FR9's links after the user's own text, plus the password notice from FR7 when there is a password:

```text
View all files in email: https://cloud.example.com/s/xyz
Download all files in email: https://cloud.example.com/s/xyz/download
The links need a password, which the sender will give you separately.
```

The HTML version uses the same text, with the file names and labels as links.

## Using Nextcloud

The requests are in [NEXTCLOUD.md](NEXTCLOUD.md).

- **Folders (FR2):** name each message's folder `<yyyy-MM-dd-HH-mm-ss> <subject>`, the time of the first send call in the Mac's time zone, inside the settings' directory (D19). Shorten the subject to 60 characters, replace `/` and `\`, and trim spaces and dots from the ends. Use `Email` if there's no subject. If the folder exists, add a number, as in `2026-11-05-14-03-09 Report (2)`. Recipients see this name on the folder's page, and probably as the zip's name. Two different files with the same name in one message get an index.
- **Uploads:** always upload with `If-None-Match: *`, so a file that older links point to is never overwritten.
- **Shares (FR8, FR9, D17):** with one link for the email's folder, the default, share the folder once, and give each file the folder share's page as its view link and `/s/<token>/download?files=<name>` as its download link. A folder share has no view page for a single file. Files in a shared folder get `#`, `%` and `?` in their names replaced with `_`, because Nextcloud's redirect for one file doesn't encode them ([NEXTCLOUD.md](NEXTCLOUD.md#share-links)). With a link for each file, create a share per file, plus one for the folder when FR9 applies. Nextcloud allows each user 20 new shares in 10 minutes, which a share per file reaches with one email of 20 files (R21).
- **Requests:** every request sends Basic auth with the app password, and the client keeps no cookies, because Nextcloud's session cookie is tied to the app password that made it ([NEXTCLOUD.md](NEXTCLOUD.md#requests)). A 401 means the app password no longer works, a 429 that the share limit was reached, and "offline" may mean that Local Network privacy blocked the server ([MAIL.md](MAIL.md#network)). Each stops the send with its own message.
- **Expiry (FR4):** send every share an explicit `expireDate`. For a week, month, year, or a custom period of years, months, days and hours, use the time of sending plus that period by calendar, and send the date it reaches. For never, send an empty string. Read the server's limits first, and shorten the date to the maximum when one is enforced. Show the `expiration` the server returns next to each link, never the requested date. The folder share gets the same date as the file shares.
- **Passwords (FR7):** send the email's password with every share. If the server enforces passwords and there's none, stop the send with an alert asking for one. If the password policy rejects the password, stop the send with the server's reason.

## Send warnings (FR5, FR6)

Both warnings come from `allowMessageSendForSession`, which returns at most one error, so Mail shows at most one alert. FR5 needs a file and FR6 needs none, so only one can apply. The alert's buttons are fixed, as Cancel and Send Anyway (t23, t33).

### FR5: Sign is off

1. If `composeContext.shouldSign` is true, there's no FR5 warning. Read it here, not at compose start.
2. Parse `rawData` with `LinkPolicy`. With Sign off it holds the whole message (t33). If no file would become a link, there's no FR5 warning.
3. Otherwise return `MEComposeSessionError(.invalidBody, userInfo: [NSLocalizedDescriptionKey: …])`. The extension can't turn on Sign, so the text has to say how.

### FR6: text mentions an attachment

1. If the phrase list is empty, there's no check.
2. Count the files in `rawData`, leaving out the signature's images, which its HTML marks. With Sign on, the first call has already turned files into links, and the ledger has them under the message ID, so the check adds those. If there are any, there's no warning.
3. Take the text from the HTML part, because the plain-text part is empty at this point (t34, t35). Remove tags, decode entities and collapse spaces. Skip `<div class="AppleOriginalContents">`, `<blockquote type="cite">` and `<div id="AppleMailSignature">`, but keep the blockquote of shared content inside `Apple-Mail-URLShareWrapperClass`. Without HTML, use the plain text without `>` lines and without the signature after Mail's signature separator line, two dashes and a space.
4. Look for each phrase ignoring case, including inside longer words. Report the first one found: "Your message mentions "see attached" but has no attachment."

## Passwords in the message window (FR7)

- **Popover:** the compose session's view controller, as high as its content, with a menu for which of the email's files become links (FR3), a secure password field (t36), a switch for the email's own link expiry with the app's expiry picker, a Settings… button that opens the app, three folders up from the extension, and the account. The toolbar button shows Nextcloud's blue logo mark, from the extension's asset catalog through `MEComposeSession` > `MEComposeIcon` in its `Info.plist`, with a tooltip in `MEComposeIconToolTip`. The app's icon is Nextcloud's macOS app icon, made with Icon Composer as `App/AppIcon.icon`, which `ASSETCATALOG_COMPILER_APPICON_NAME` in `Config/Signing.xcconfig` names for the app target only.
- **Link choice:** kept per email like the expiry, as a `LinkChoice` raw value under its own Keychain service. `Settings.linkPolicy(for:)` turns it into the rule, for the send calls and for FR5's warning. When the files are kept attached after Undo Send, the uploads are deleted as after Mail Drop, but the email's popover values stay, since the user can undo again.
- **Own expiry:** kept per email the same way as the password, as `LinkExpiry` JSON under its own Keychain service. When it changes after shares were made, as after Undo Send, each share gets the new date, and the email shows the dates the server returns. The ledger records the date the shares were given.
- **Storage:** the password is stored by `contextID`. Every `encode()` call, including auto-saves, links its `contextID` to the message ID, so a reopened draft, which gets a new `contextID`, still finds it (t37).
- **Restarts:** keep it in memory, and also in the Keychain under the message ID once that's known, so that restarting Mail doesn't send the links without a password (R8). A compose session whose message already has its ID, as a reopened draft may, links it at once, so the popover shows the kept password. Copies not changed for the ledger's 30 days are deleted when the extension starts, and Mail Drop's clean-up deletes the message's. Never write it to logs, settings or the ledger.
- **Changing it:** the popover saves the field at every change, since it can close without ending the edit. When the password changes after shares were made, as after Undo Send, every share of the message gets the new one, and an empty one removes it. `Sender` remembers which password it gave the shares in this process, so the second send call changes nothing. After Mail restarts it doesn't know, and sets the password again. The ledger records only whether the shares have a password.

## Settings and credentials

- **Where they live:** the settings UI is in the host app: server, directory, the FR3 rule and pasted-images option, FR4 expiry, the FR5 checkbox, the FR6 phrases, the sharing settings (D17), and the FR8 and FR9 options. Settings are shared through an App Group, and the app password through a shared Keychain group (R17). The per-email password isn't a setting.
- **The App Group:** `<team ID>.lv.warp.nextcloudmailextension`. The build writes it into each target's `Info.plist` as `NCMEAppGroupIdentifier`, from `$(TeamIdentifierPrefix)`, and `SharedStorage` reads it from there. Its container and settings work with the free Personal Team. The shared Keychain item works once the Mac is registered with the team (D16, R17).
- **Entitlements:** both targets need the sandbox, `com.apple.security.network.client` and the App Group, and `keychain-access-groups` with the App Group's identifier (D16, R17, R18). Leave out `files.user-selected.read-only`, which only dropping files on the popover needed.
- **Server URLs:** accept `https://` only, because App Transport Security blocks plain HTTP by default. `ServerAddress` adds `https://` when the user types none, and cuts a pasted page's path, keeping a path that Nextcloud is installed under.
- **Settings:** stored as JSON in the App Group's defaults. A setting that's missing or can't be read gets its default, so a later version can add settings without losing the others. The app password is in the shared Keychain item, as JSON with the server and login name, and nowhere else.
- **Local network:** the host app's `Info.plist` has `NSLocalNetworkUsageDescription`, and the extension shares the app's Local Network permission. The app asks for it when it first reaches a server on the local network, such as at login ([MAIL.md](MAIL.md#network)).
- **Test connection:** the host app runs `ConnectionCheck`, which logs in, reads the server's limits and looks for the upload directory. Test from Mail writes a request into the App Group's container and opens a new message window in Mail with `mailto:`. When that window's compose session begins, the extension runs the same check with the settings and app password it reads itself, and writes its answer next to the request. Requests older than two minutes are ignored. Until T6, the toolbar popover shows the account and has its own Test connection button.
- **Not set up yet:** if the extension isn't set up when a file would become a link, stop the send with an error saying so. Reporting `canSign: false` instead would send the files as attachments with no warning.

## Failures

An encoder error stops the send, keeps the files in the message window and shows our text (t7, t8, t12). All folder, upload, share, password, login and server-limit errors use this route, naming the file and the server's reason.

## Progress

Mail shows nothing while `encode()` runs (t9). The extension posts a notification when an upload of files not yet on Nextcloud has run for 2 seconds, "Uploading 2 files (14 MB) to Nextcloud…", and replaces it when the upload is done with how long it took. If the upload fails, the notification is removed, because Mail's alert explains. Uploads under 2 seconds show none, and Mail's second send call, which finds everything uploaded, shows none. Notifications give the number of files and their size, never names. They come under the host app's permission, which the app asks for when it starts (R3).
