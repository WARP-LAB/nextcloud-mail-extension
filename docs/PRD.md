# Product Requirements Document

NextcloudMailExtension is an Apple Mail extension for macOS, a successor to [cargolifter-mail-plugin](https://github.com/WARP-LAB/cargolifter-mail-plugin). This document says what it must do. [ARCHITECTURE.md](ARCHITECTURE.md) describes how, and [MAIL.md](MAIL.md) records the Mail behaviour that showed each requirement can be met.

The upload can run only while Sign is on in the message window, because Mail doesn't give the extension the outgoing message otherwise. FR5 covers messages sent with Sign off.

The defaults were confirmed by the user (D21). Requirements marked "Proposed" await confirmation (OD5), an open decision in [TASKS.md](TASKS.md).

## FR1: Replace attachments with links at send

Files are added to the message window as usual. When the message is sent, they are uploaded to Nextcloud and replaced by share links in the email body. FR8 and FR9 describe the links.

Acceptance criteria:

- With Sign on, every file that FR3 selects is missing from the delivered email and replaced by its links, and the links open and download the file.
- The Sent copy is the same as what recipients get.
- If an upload or share fails, nothing is sent, the message window stays open with its files, and an alert names the file and the server's reason.
- Mail encoding a message more than once doesn't upload its files more than once, and sending again after Undo Send reuses the same links.

## FR2: Nextcloud settings and folders

The extension's settings hold the Nextcloud server URL and the directory where files are uploaded, which is "MailAttachments" by default. Each email gets its own subfolder inside that directory, so that:

- files with the same name in different emails don't clash
- all of an email's files can be downloaded at once, as that folder (FR9)

Only files that become links are uploaded, so files that stay attached under FR3 aren't in the folder.

Acceptance criteria:

- The user logs in through Nextcloud's own login page in the browser. The extension never sees or stores the user's password.
- Each email's files are in their own subfolder of the configured directory, and two emails with files of the same name don't overwrite each other.
- Files that stay attached aren't uploaded.

## FR3: Which files become links

A setting chooses one of:

- All attachments become links. This is the default.
- Only attachments over a set size become links. The rest stay attached, so one message can have both.

The size is in decimal megabytes, as Finder shows them, and keeps the decimals typed, such as 0.2 or 10.2, with either "." or "," before them. With a size, a second setting, "Size limit applies to", chooses:

- **Each file:** each file larger than the limit becomes links. This is the default.
- **All files together:** when the files together are larger than the limit, all of them become links, and otherwise all of them stay attached. Only files that could become links count towards the total, so pasted images that stay in the email and signature images don't.

Another setting, "Pasted images become links", decides whether images pasted into the body follow that rule. It is on by default. When it is off, pasted images stay in the email whatever the rule says. Images in the signature never become links.

In the message window, a menu in the toolbar button's popover, "For this email", chooses for that email (D24):

- **Use settings:** the settings above decide. This is the default.
- **All files via Nextcloud:** every file becomes links, pasted images too, whatever the size limit and the pasted-images setting say.
- **All files kept as attachments:** every file stays attached, and nothing is uploaded for the email. The popover's password and expiry don't apply then, so they're greyed out. Keeping the files after Undo Send deletes what the earlier send uploaded.

Acceptance criteria:

- With "all attachments", every attached file becomes links.
- With a size limit for each file, only files larger than the limit become links. The others arrive attached and byte-identical, and a file exactly at the limit stays attached.
- With a size limit for all files together, either every file becomes links or every file arrives attached and byte-identical, and files exactly at the limit together stay attached.
- A size typed as "0.2" or "0,2" stays 0.2 MB.
- Pasted images follow the rule while the pasted-images setting is on, and stay in the email while it's off.
- Signature images always stay in the email.
- With "All files via Nextcloud" in an email's popover, every file but the signature's images becomes links, whatever the settings say.
- With "All files kept as attachments", every file arrives attached and byte-identical, and nothing is left uploaded for that email.

## FR4: Link expiry

A setting chooses when links expire:

- in a week, a month or a year, with a month as the default
- after a custom period of years, months, days and hours, such as 0 years, 2 months, 3 days and 1 hour, counted from sending
- never

In the message window, the extension's toolbar button lets the user give that email its own expiry instead, with the same choices. The button also opens the app's settings.

Acceptance criteria:

- Each choice gives links that expire at the end of the day the period reaches, or never. Nextcloud ends links only at the end of a day, so hours move the date only when they cross midnight, and the setting says so.
- The email shows the expiry date the server actually set.
- If the server enforces a maximum, the links get the maximum, and the email shows that date.
- An email's own expiry, set from the toolbar button, applies to that email's links only.

## FR5: Warn if Sign is off

The settings have a checkbox, "Warn if signing (upload via link) is disabled". It is on by default.

When the checkbox is on, Sign is off, and at least one file would become a link under FR3, clicking Send shows an alert. The alert names those files and says how to turn on Sign. It has two buttons:

- **Cancel:** nothing is sent and the message window stays open with its files. The user can turn on Sign and send again, which uploads the files.
- **Send Anyway:** the message is sent with the files as normal attachments, and nothing is uploaded.

No alert appears when the checkbox is off, when Sign is on, or when no file would become a link.

Acceptance criteria:

- The alert appears exactly in the case above, names the files, and says how to turn on Sign.
- Cancel sends nothing and keeps the files in the window. Send Anyway sends the files attached and uploads nothing.

## FR6: Warn if text mentions an attachment but none is added

The settings have a field, "Warn if the email's text includes a phrase but there's no attachment", where the user enters words or phrases, such as "attachment" or "see attached". Each one entered with Return becomes a tag, shown as a bubble with an x that removes it, and a tag can hold several words. It is empty by default, and while it is empty there is no check.

When the message text contains one of those words or phrases and the message has no attachment, clicking Send shows an alert. The alert names the word or phrase it found. It has two buttons:

- **Cancel:** nothing is sent and the message window stays open. The user can add the forgotten file and send again.
- **Send Anyway:** the message is sent as written.

This works the same with Sign on or off. These rules decide what counts:

- **Matching:** upper and lower case are treated the same, and the text is also found inside longer words, so "attach" matches "attached".
- **Message text:** only what the user wrote. The subject, quoted text in replies and forwards, and the signature are not checked.
- **Attachments:** any file in the message, including one that became a link under FR3 and an image pasted into the body. An image in the signature doesn't count.

FR5 and FR6 can't apply to the same message, because FR5 needs a file and FR6 needs none.

Acceptance criteria:

- With phrases set, the alert appears when the user's own text contains one and the message has no attachment, by the rules above, and it names the phrase.
- Phrases in the subject, in quoted text or in the signature never trigger it.
- Cancel and Send Anyway behave as described, with Sign on and with Sign off.

## FR7: Password per email

In the message window, the user can set a password for that email's links, using the extension's button in the toolbar. It is empty by default, and then the links have no password.

- The password applies to every link in that email, including the links to all files (FR9).
- The email says that the links need a password, but doesn't contain it. The user gives it to recipients some other way.
- If Nextcloud rejects the password, for example because it's shorter than the server's password policy allows, the send stops with the server's reason and the message window stays open.
- If the server requires passwords on links and none is set, the send stops with an alert asking for one.

Acceptance criteria:

- Every link of an email with a password asks for that password, and the email doesn't contain it.
- The password survives closing and reopening the draft.
- The two failure cases stop the send with the alerts described.

## FR8: Links for each file

A setting, "Nextcloud shares", chooses what Nextcloud shares (D17):

- **One share for all files in the email:** one share per email, of its folder (FR2). This is the default. Each file's view link opens the folder's page, which lists the email's files, and its download link downloads only that file.
- **Separate share for each file in the email:** one share per file, and each file's view link opens that file's own page. Nextcloud allows each user only 20 new shares in 10 minutes, so an email with many files, or several emails in a row, can fail to send until the server's admin raises that limit. The settings warn about it, and link to Nextcloud's documentation of the setting that raises it.

With one share for all files in the email, a second setting, "Place links", chooses:

- **Inline, where each file was:** each file gets its links as described below. This is the default.
- **Below your text:** the files are removed from where they were. After the user's own text, the email lists each file's name and size, followed by FR9's two links, whatever FR9's setting and however many files became links.

Each file that becomes a link is replaced by its links where the file was dropped in the message, which may be between paragraphs of text. If the extension can't tell where a file was, its links go in a list after the user's own text, above any quoted messages in a reply or forward. They never go at the top.

A setting, "Show download link for file", chooses how many links each file gets:

- **Together with view link:** two links, one that opens the file in Nextcloud and one that downloads it. This is the default.
- **Only:** one link, which downloads the file.

Acceptance criteria:

- Each file's links are where the file was, or in the list described above, and never at the top.
- The setting gives two links or one link per file, as described.
- With one share for all files in the email, the email's files use one share, each view link opens the folder's page, and each download link downloads only its file. With a separate share for each file, each file has its own share and page.
- With only the folder's links, the email lists every linked file's name and size, followed by FR9's two links, and has no other links.
- The links show correctly in Apple Mail, Gmail on the web and Outlook.

## FR9: Links for all files

A setting, "If multiple attachments, also add links for all files below your text", is off by default. When it is on and two or more files in an email became links, two more links are added after the user's own text. They go below any list from FR8 and above any quoted messages in a reply or forward:

- **View all files in email:** opens the email's folder (FR2) in Nextcloud.
- **Download all files in email:** downloads that folder as one zip file.

With a separate share for each file (FR8), these links need one more share, for the folder. With only the folder's links (FR8), they are always added, even for one file, and this setting doesn't apply.

These links follow FR4 (expiry) and FR7 (password). The folder holds only the files that became links, so files that stayed attached under FR3 aren't included.

Acceptance criteria:

- With the setting on and two or more linked files, both links appear in the place described. With one linked file, or the setting off, they don't, unless FR8's setting gives only the folder's links.
- The zip holds exactly the email's linked files.
- Both links follow FR4 and FR7.

## FR10: Mail Drop

When an email is over the account's size limit, Mail asks whether to use Mail Drop before the extension runs. The extension can't prevent this.

- The setup help tells users to choose "Try Sending in Email" and tick "Don't ask again for this account". The extension then uploads the files as usual, and the email is small.
- If the user chooses "Use Mail Drop", the email goes out with Mail Drop's link. The extension deletes the files and links it had already uploaded to Nextcloud for that email.

Acceptance criteria:

- After Try Sending in Email, the email goes out as FR1 describes.
- After Use Mail Drop, the email goes out with Mail Drop's link, and nothing uploaded for it is left on Nextcloud.
- The setup help gives the advice above.

## Non-functional requirements

NFR1 is decided (D12). The others are proposed (OD5).

- **NFR1, platforms:** macOS 27 or later, on Apple silicon only, and Nextcloud 34 or later. How the app is distributed is still open (OD3).
- **NFR2, privacy:** no telemetry. Files go only to the configured server. Message contents, addresses and passwords are never logged. Credentials are kept only in the Keychain.
- **NFR3, security:** server URLs are `https://` only. The extension uses an app password from Nextcloud's browser login, never the user's own password. An upload never overwrites an existing file.
- **NFR4, reliability:** an email is never sent with links to files that failed to upload. Every file selected for a link either arrives as a working link, or the send stops with the file still in the window.

## Out of scope

Proposed (OD5).

- iOS and iPadOS Mail, which don't support MailKit extensions.
- Cloud services other than Nextcloud, which the old plugin also supported.
- Real email signing or encryption, such as S/MIME, while the extension is chosen for message security. The extension takes over Mail's Sign button (R12).
- Cleaning up or managing old uploads on Nextcloud.
- Mail apps other than Apple Mail.
