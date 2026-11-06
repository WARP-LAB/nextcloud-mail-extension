# Risks

What could go wrong, how we'd notice, and what's being done about it. Each entry ends with a judgment call: what an agent may decide alone when the risk comes up. Anything beyond that goes to [TASKS.md](TASKS.md) as an open decision. When a task touches a risk, update its entry.

## Mail

### R1: Mail stops delivering the bytes `encode()` returns

- **Risk:** the whole design relies on Mail sending what `encode()` returns even when it's flagged unsigned, which contradicts Apple's header comment ([MAIL.md](MAIL.md#the-sign-button)). A macOS or Mail update could change it.
- **Signal:** after an update, files go out attached with Sign on, or Mail shows signing errors.
- **Mitigation:** after every macOS update, run the quick regression set in [probe/docs/PROBE.md](../probe/docs/PROBE.md).
- **Judgment call:** an agent may investigate and report, but must not switch to another route, such as the popover or AppleScript, without asking.

### R2: "Don't ask again" in the Mail Drop prompt is untested

- **Risk:** FR10's setup help assumes that ticking it with Try Sending in Email makes Mail stop asking. What it really remembers, and how to undo it, is unknown.
- **Signal:** users still see the prompt every time, or large emails go out through Mail Drop.
- **Mitigation:** test it once, on an account where changing the behaviour doesn't matter (open decision OD6).
- **Judgment call:** never tick it on the user's account without asking.

### R3: No progress display during uploads

- **Risk:** Mail shows nothing while `encode()` runs, so a slow upload looks like Mail has hung.
- **Signal:** users close the window or quit Mail during an upload.
- **Mitigation:** a notification while an upload runs and when it ends, done in T8. Tested in Mail with a 30 MB file: both notifications appeared.
- **Judgment call:** an agent may choose whichever of the two works from the extension. If neither works, ask.

### R4: Very long uploads

- **Risk:** Mail waited 5 minutes 20 seconds without a timeout, but longer waits, and quitting Mail during an upload, are untested.
- **Signal:** large uploads fail or the message is lost from the Outbox.
- **Mitigation:** request timeouts, and a test with a large file on a slow connection.
- **Judgment call:** an agent may set request timeouts. A maximum upload size would be a product change, so ask.

### R5: Large messages in memory

- **Risk:** Mail passes the whole message in memory, and decoding attachments can double that.
- **Signal:** the extension is killed or slows down with big attachments. So far a 244 MB draft and a 40.5 MB send worked.
- **Mitigation:** decode each attachment to a temporary file and upload from there, one file at a time, which `SendFlow` does (T5). The message itself is still in memory, as Mail passes it.
- **Judgment call:** implementation details are the agent's.

### R6: Mail's HTML markers change

- **Risk:** finding quoted text, the signature and each file's position relies on markers in Mail's HTML, such as `AppleMailSignature`, `blockquote type="cite"`, `cid:` and U+FFFC ([MAIL.md](MAIL.md#message-structures)).
- **Signal:** links appear inside quotes or the signature, or FR6 warns about quoted text.
- **Mitigation:** probe tests t29, t30 and t34 in the regression set, the unit tests over the fixtures made from them, and the fallback list for files whose position can't be found.
- **Judgment call:** an agent may adapt the detection to new markers after re-probing, and update MAIL.md.

### R7: Telling pasted images from dropped ones

- **Risk:** pasted images are recognised only by Mail's `PastedGraphic-N.png` names. Mail may use other names in other languages, and a dropped file with such a name counts as pasted.
- **Signal:** the pasted-images setting (FR3) doesn't affect some pasted images.
- **Mitigation:** probe once with macOS in another language (not run yet, see [probe/docs/TESTS.md](../probe/docs/TESTS.md#not-run-yet)).
- **Judgment call:** an agent may add name patterns found by probing. Changing what FR3 does is the user's call.

### R8: A password that can't be found at send

- **Risk:** if a typed password isn't found at send, for example after Mail restarts before the draft's first auto-save, the links go out without one, and the extension can't tell.
- **Signal:** recipients can open links that should need a password.
- **Mitigation:** keep the password in the Keychain under the message ID as soon as that's known. Tested in Mail (T6): after typing it, saving the draft and restarting Mail, the reopened draft's links still needed it.
- **Judgment call:** an agent must not drop the Keychain copy, or weaken FR7, without asking.

### R9: Offering Sign without Encrypt

- **Risk:** reporting `canSign: true` with `canEncrypt: false` is untested. MailProbe always reported both.
- **Signal:** Sign is unavailable or behaves differently.
- **Mitigation:** check it in task T1.
- **Judgment call:** an agent may report both as available if needed, and note it here.

### R10: The extension is enabled but not chosen for message security

- **Risk:** the send check would still run, but Sign wouldn't reach the extension, so FR5's advice to turn on Sign wouldn't help.
- **Signal:** users see the FR5 warning even with Sign on.
- **Mitigation:** test it, and have the host app check the setup.
- **Judgment call:** an agent may word the warnings and the setup check.

### R11: Other mail providers

- **Risk:** only Gmail was probed. Another provider might store the Sent copy differently, or Mail might handle it differently.
- **Signal:** the Sent copy differs from what recipients get.
- **Mitigation:** send test t27 from a non-Gmail account.
- **Judgment call:** none needed. This is a test to run.

### R12: Real signing and encryption

- **Risk:** the extension takes over Mail's Sign button, so it can't be used alongside real email signing or encryption with S/MIME certificates. This is untested, but likely, since only one extension is chosen for message security.
- **Signal:** users with certificates can't sign mail while the extension is chosen.
- **Mitigation:** listed as out of scope in the PRD, and to be said in the setup help.
- **Judgment call:** ask before designing anything around it.

## Product

### R13: Send Later uploads at scheduling

- **Risk:** `encode()` runs when a message is scheduled, so files upload and link expiry starts then, not at delivery.
- **Signal:** links expire earlier than expected for scheduled mail.
- **Mitigation:** say so in the setup help.
- **Judgment call:** none. It's a documented limit.

### R14: Uploads left behind by Undo Send

- **Risk:** after Undo Send the files are already on Nextcloud. If the email is never sent again, they stay there.
- **Signal:** unused folders in the upload directory.
- **Mitigation:** none yet. The ledger knows which messages these are.
- **Judgment call:** never delete the user's files automatically without a product decision.

### R15: Expired links leave no copy in the mailbox

- **Risk:** the Sent copy holds links, not files, so once a link expires the mailbox has no copy of the file.
- **Signal:** users can't find old attachments.
- **Mitigation:** say so in the setup help. Files stay on Nextcloud after the share expires.
- **Judgment call:** ask before adding anything that keeps copies.

### R16: How recipients' mail clients show the links

- **Risk:** links put where each file was might look wrong in some mail clients.
- **Signal:** broken layout or missing links in Gmail, Outlook or Apple Mail.
- **Mitigation:** merge text parts so the message has one text part, and check delivered messages in those three clients ([TESTING.md](TESTING.md#mail-checks)). The Mail checks found that files next to each other ran their links together in the plain text, now fixed (T5b).
- **Judgment call:** an agent may change the link layout within what FR8 says.

### R22: Nextcloud's trademarks

- **Risk:** Nextcloud GmbH objects to its logo as the project's icons, or to Nextcloud in the project's name, and asks for them to go. Its trademark guidelines allow the logos only as links to nextcloud.com, and say that third-party apps shouldn't have its mark in their name.
- **Signal:** a request from Nextcloud GmbH, or an app store refusing the app.
- **Mitigation:** `LICENSE.Nextcloud` names the files that use the logo, their sources and the trademark, and says the project isn't official. The artwork is in three places, `Design/`, the toolbar's image set and `App/AppIcon.icon`, so it can be replaced in one change. The user asks Nextcloud GmbH for permission while the project is published (D25, T13b).
- **Judgment call:** none on using, replacing or renaming, which is the user's call. An agent keeps `LICENSE.Nextcloud` up to date when Nextcloud artwork is added or changed.

### R23: Apple's trademarks

- **Risk:** Apple objects to Apple in the project's name, or refuses the app in review. Its trademark guidelines don't allow Apple's trademarks in a third party's product name, only in phrases that say what a product works with.
- **Signal:** a request from Apple, or a rejection in the Mac App Store's review.
- **Mitigation:** `LICENSE.Apple` gives Apple's trademark notice, says the project isn't Apple's, and that it contains nothing of Apple's. Keeping the name or renaming is open (OD12).
- **Judgment call:** none on the name, which is the user's call. An agent describes compatibility in Apple's terms, such as "for Mail on macOS", and keeps `LICENSE.Apple`'s list of trademarks up to date when docs or the app start naming another one.

## Platform and server

### R17: Sharing the app password needs a provisioning profile

- **Risk:** the host app and the extension share settings through the App Group, and the app password through a Keychain item in the same group.
- **Tested** (T1, 2026-11-06, with the free Personal Team): the App Group's container and settings work without a provisioning profile. The shared Keychain item fails with `-34018`, because it needs the `keychain-access-groups` entitlement. That entitlement needs a provisioning profile, which Xcode can only create once this Mac is registered as a device with the team.
- **Tested** (T1b, 2026-11-06, with this Mac registered, D16): the host app's storage check passes for the container, the settings and the Keychain item. The extension's read of the Keychain item is checked by Test from Mail, which runs the connection check in the extension and reads the app password from it.
- **Signal:** the Keychain line of the host app's storage check fails, or the extension can't read the app password.
- **Mitigation:** this Mac is registered with the Personal Team (D16). On another Mac, register it the same way. The fallback is doing the login in the extension and keeping the app password in the extension's own Keychain.
- **Judgment call:** registering a Mac, or switching to the fallback, is the user's call.

### R18: Network access from the extension

- **Risk:** the extension using the network during `encode()` is untested.
- **Tested** (T2, 2026-11-06): inside Mail, the extension read the settings and the app password, but its requests to the test server, which is on the local network, failed with "offline" because of Local Network privacy ([MAIL.md](MAIL.md#network)). Servers on the internet aren't affected by that, and haven't been tried from the extension yet. Once the user allowed the app's local network access, Test from Mail passed (T2b). After a new build is installed, macOS refuses its first local network request once, which a retry covers (T5b, [MAIL.md](MAIL.md#network)).
- **Signal:** uploads fail with sandbox or connection errors.
- **Mitigation:** the host app declares `NSLocalNetworkUsageDescription`, so macOS asks the user, and the extension shares the app's permission. The offline error and the setup help say where to allow it. Test from Mail checks it (T2b).
- **Judgment call:** if it's blocked, stop and ask.

### R19: Nextcloud behaves differently from what was tested

- **Risk:** everything in [NEXTCLOUD.md](NEXTCLOUD.md) has now been run against the test server's Nextcloud 35.0.2, the enforced settings included (T3, T3b). T5 found that a folder share's download of one file breaks on names with `#`, `%` or `?`, and adapted the names. Other servers may run other versions, apps or settings, such as Nextcloud 34, a different password policy, or a proxy in front.
- **Signal:** shares, links or expiry dates behave differently from what NEXTCLOUD.md says.
- **Mitigation:** the server tests (`scripts/test-nextcloud.sh`, and `--server-settings` for the enforced settings, D18), which can be run against another test server.
- **Judgment call:** an agent may adapt to what the server really does, and update NEXTCLOUD.md.

### R21: Nextcloud's limit on new shares

- **Risk:** Nextcloud allows each user 20 share creations in 10 minutes, refused attempts included ([NEXTCLOUD.md](NEXTCLOUD.md#rate-limit)). With one share per file and one per folder, an email with 20 files, or a few emails in a row, fails to send.
- **Signal:** sends stop with the rate-limit error, `NextcloudError.rateLimited`.
- **Mitigation:** one link for the email's folder, the default, uses one share per email (D17). With a link for each file, the setup help tells admins how to raise the limit.
- **Judgment call:** an agent may change how the shares are made within D17. Changing what the links point to, or the default, is the user's call.

## Tooling

### R20: swift-format changes with Xcode

- **Risk:** the swift-format bundled with Xcode reports its version only as "main", so an Xcode update can change its findings.
- **Signal:** new swift-format findings after an Xcode update, with no code change.
- **Mitigation:** treat them as tooling changes, not code problems.
- **Judgment call:** an agent may adjust `.swift-format` to restore the earlier behaviour, but should ask before switching rules off broadly.
