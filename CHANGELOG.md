# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html), with [ZeroVer](https://0ver.org) while it is in early development.

<!-- markdownlint-disable MD024 -->

## [Unreleased]

### Added

- NextcloudMailExtension, an extension for Apple Mail on macOS 27 or later, on Apple silicon, for Nextcloud 34 or later. When you send an email, its attachments are uploaded to your Nextcloud server, into a folder of their own for that email, and replaced in the email by share links.
- It works through Mail's **Sign** button: files become links only while Sign is on, and while NextcloudMailExtension is chosen as Mail's message security extension, Mail can't sign or encrypt email with certificates.
- An email is never sent half-way: if an upload fails, the email isn't sent, you keep your files in the message window, and Mail says what went wrong and how to send the files attached instead.
- Login through Nextcloud's own page in your browser. The extension connects with an app password kept in the macOS Keychain, and never sees your Nextcloud password.
- Settings in the app: the upload folder, which files become links (all of them, or only those over a size limit), whether pasted images do too, link expiry, one share per email or one per file, where the links go in the email, view and download links or download only, and links for all of an email's files.
- Per email, from the toolbar button in Mail: keep all files attached or send all via Nextcloud, and set the links' expiry and a password. The password is checked against your server's password policy, and one it accepts can be generated.
- A warning before sending files attached when Sign is off, and an optional check for emails that mention an attachment but have none.
- Notifications while a slow upload runs and when it's done.
- When Mail offers Mail Drop for a large email, choosing **Try Sending in Email** sends the files via Nextcloud instead. Choosing **Use Mail Drop** deletes what was already uploaded for that email.
- No telemetry. Files go only to your own server, and message contents, addresses and passwords are never logged.
- A download as a DMG, signed with a Developer ID and notarized by Apple.

[unreleased]: https://github.com/WARP-LAB/nextcloud-mail-extension/commits/main
