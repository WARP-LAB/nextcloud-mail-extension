# Apple Mail behaviour

What Apple Mail does with a MailKit extension, as far as the design in [ARCHITECTURE.md](ARCHITECTURE.md) depends on it. Apple documents little of this, so everything here was found by probing with the MailProbe test extension in Mail 16.0 (3901.100.1.1.12) on macOS 27.0.1 (26A434), aarch64, with a Gmail account.

`tN` is a test in [probe/docs/TESTS.md](../probe/docs/TESTS.md), with its logs and messages in `probe/test-results/`, which stays local. After a macOS or Mail update, rerun the quick regression set in [probe/docs/PROBE.md](../probe/docs/PROBE.md), then update this file and [RISKS.md](RISKS.md).

## The Sign button

- **Upload switch:** `encode()` runs at send only while Sign or Encrypt is on (t1–t5). Draft auto-saves call it whatever the toggles.
- **Returned bytes are delivered:** Mail sends the message `encode()` returns, even when it's flagged as neither signed nor encrypted (t5). Apple's header comment suggests otherwise, so this may change (R1).
- **No contents in the status call:** `getEncodingStatus` doesn't get the message's contents, so whether Sign is offered can't depend on attachments. Reporting that the extension can't sign makes the button unavailable, and `encode()` then doesn't run at send (t6).
- **Choosing the extension:** Mail's Settings > Extensions shows a "Message security extension" popup at the bottom only when there's a choice to make. With this the only message security extension installed, there's no popup (the user, 2026-11-07).
- **The extension can't turn Sign on.** Sign keeps its state across messages and Mail restarts.
- **Reading the state:** `composeContext.shouldSign` matched the toggle in all 30 logged sends when read at send (t5, t23). At compose start it can be wrong at first and then correct itself.
- **Returning nil:** with Sign on, Mail sends the message normally, unsigned, with its files intact (t18).

## What happens at send

```text
Sign on
  additionalHeaders
  encode, first send call    Mail waits while this runs
  allowMessageSend           rawData is the first call's output, or Mail's input if it returned nil
  additionalHeaders
  encode, second send call   this output is delivered and kept in Sent

Sign off
  additionalHeaders
  allowMessageSend           rawData is the whole message, files included
  no encode at send
```

- **Delivered copy:** both send calls have the same message ID, `X-Universally-Unique-Identifier`. The second call's output is what's delivered, and the Sent copy is byte-identical to it (t5, t27, t38).
- **Headers:** Mail includes `Bcc:` in the extension's input and removes it before sending, along with the message ID header. It adds `X-Mailer` (t5, t19).
- **The send check:** after an error in the first call, `allowMessageSend` gets no `rawData`. Otherwise it gets the first call's output, or exactly Mail's input to that call when the call returned nil (t34). With Sign off it gets the whole message, files included (t33).
- **No overlap:** send-time `encode()` calls never overlapped in the 48 logged.
- **Waiting:** Mail waits for a slow first call, with no timeout and no progress display, and its other windows stay usable. 32, 128 and 320 seconds all worked (t9–t11). Only the first call was ever slow in these tests.
- **Auto-saves:** draft auto-saves have `state` 1 and send calls `state` 2, in all 78 calls logged in rounds 1 and 2. Use `state`, not headers: `X-Apple-Auto-Saved` was missing on 7 of the 30 auto-saves.
- **Size in memory:** Mail passes the whole message in memory. A 244 MB draft auto-save and a 40.5 MB message at send passed without trouble (t38).

## Errors and alerts

- **An encoder error stops the send.** Mail shows the extension's text with only an OK button, nothing is delivered, and the files stay in the message window. Both send calls still run (t7, t8, t12).
- **A send-check error only warns.** Mail shows an alert with the extension's name, its text, and Cancel and Send Anyway, once per click on Send. The buttons can't be changed. Send Anyway sends the message unchanged. Cancel returns to the message with its files, and the next send runs as usual (t23, t33).

## Drafts, Undo Send and Send Later

- **Reopened drafts:** a reopened draft gets a new `contextID` but keeps its message ID, and keeps its files (t17, t26, t37). `compose-end` rarely fires, so don't rely on it.
- **Undo Send:** `encode()` runs at the first click. After undo, the file is back in the window, and sending again works. The message ID stays the same, and the `contextID` changes (t21).
- **Send Later:** `encode()` runs when the message is scheduled, and those bytes go out later with only the date updated. The extension can't tell this apart from a normal send (t22).

## Mail Drop

When a message is over the provider's size limit, Mail asks about Mail Drop before calling the extension at all, even with Mail Drop off for the account (t31: 30.4 MB on Gmail). The prompt has Use Mail Drop, Try Sending in Email and Cancel buttons, and a "Don't ask again for this account" checkbox.

- **Cancel:** returns to the message, and the extension isn't called (t31).
- **Try Sending in Email:** the usual two send calls follow, with the whole 40.5 MB message (t38).
- **Use Mail Drop:** there are three send calls (t39). The first gets the whole message, with the same headers as without Mail Drop. The second gets the message with the file already removed. About 7 seconds later, after the upload to iCloud, the third gets Mail's Mail Drop message, with a `Remote-Attachment-Url` header and a download link. The third call's output is what's delivered.

What "Don't ask again" remembers is untested (R2).

## Message structures

The two send calls receive different structures, and only the second is delivered:

| Call | Structure | Seen in |
| --- | --- | --- |
| First | `multipart/alternative`: empty `text/plain`, then `text/html`, inside `multipart/related` with the files when there are any. In the HTML, each image is `<img src="cid:…">` and each other file `<object data="cid:…">` | All tests |
| Second, plain message | `multipart/mixed`: `text/plain`, file, `text/plain`, file, `text/plain`. Inline PDFs and PNGs are `inline` parts in the same places | t9–t19, t21, t22, t27–t29 |
| Second, message with a signature and a pasted image | `multipart/alternative`: `text/plain` with U+FFFC for each image, then `multipart/related` holding `text/html` with `<img src="cid:…">` and the images | t30 |
| Second, forward with quoted HTML | `multipart/alternative`: `text/plain` with U+FFFC where the file was, then `multipart/mixed` holding `text/html`, file, `text/html` | t20 |
| Second, reply or no files | Single `text/plain`, with quoted lines starting with `>` | t24–t26, t34, t35 |
| Second, message with a file and a signature image | `multipart/alternative`: `text/plain` with U+FFFC for each, then `multipart/mixed` holding `text/html`, file, `text/html`, image, `text/html`. Neither part has a Content-ID | T5b, sent through AppleScript |

In the first call's structure, the typed text is only in the HTML (t15, t24, t34, t35). The HTML also marks:

- **Quoted text:** inside `<blockquote type="cite">`, which a reply wraps in `<div class="AppleOriginalContents">`. The "On … wrote:" line is inside the quote (t20, t34). A file in the quoted message appears only as its name in angle brackets.
- **Signature:** inside `<div id="AppleMailSignature">`, including its image (t30). The second call's HTML drops these IDs and classes. Each image keeps the same Content-ID in both calls, except when the message also has another file: then the second call's images have no Content-ID at all (T5b), and only their bytes, which are the same in both calls, tell them apart.
- **Shared content:** text set through AppleScript, like content shared from another app, sits in `<div class="Apple-Mail-URLShareWrapperClass">` around a `<blockquote type="cite" style="border-left-style: none;…">`. It isn't a quote, although the plain-text alternative shows it with `>` (T5b).
- **Pasted images:** named `PastedGraphic-1.png` and so on, while a dropped file keeps its own name (t30). Both are `inline` `image/png` parts.

Decoded files are byte-identical in both calls (t15). Mail didn't resize a 10 MB PNG (t28), and every kept or removed file matched the original byte for byte.

Files next to each other, with no text between them, have touching U+FFFC placeholders in the plain text, such as `￼￼` (T5b). A file's name comes as macOS stores it, often decomposed, so `ā` arrives as `a` and a combining macron, and Nextcloud keeps that form.

Mail chooses each file's transfer encoding by its content. The 10 MB test PNG, mostly padding text, was quoted-printable in both of t28's calls, while the other files were base64. Lines end in LF, not CRLF, in all 165 saved send calls.

## Network

The extension's requests are subject to macOS's Local Network privacy, found in T2 on 2026-11-06 with the test server, whose address is on this Mac's local network.

- **Blocked until allowed:** while the host app's Local Network permission was undetermined, every request from the extension failed at once with `NSURLErrorNotConnectedToInternet`, "The Internet connection appears to be offline". The system log said "Local network prohibited".
- **The extension needs a permission of its own** (T14, 2026-11-07): Apple's [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) says app extensions share their container app's permission and that `NSLocalNetworkUsageDescription` goes in the app's `Info.plist`, but Mail's extension doesn't get the app's. With the key in the app's `Info.plist`, macOS makes the app a Local Network rule as soon as it's installed, links the extension's requests to it (the log says "found bundle id … by UUID"), and refuses them even with the app allowed, without ever asking for the extension or listing it. Adding the key to the extension's `Info.plist` too changed nothing. Without the key in either, no rule exists at install. The extension's first request from its open popover makes macOS ask "Allow “NextcloudMailEx” to find devices on local networks?", with the name cut short, and System Settings then lists NextcloudMailExtensionPlugIn, with a generic icon. The app asks for itself on its first request, with the same wording. Both then reach the server (D27).
- **Only the popover asks:** a send runs in the background, and macOS refuses its local network requests without asking. The popover's connection check, which runs as it opens, is what gets the extension its prompt.
- **An update locks the extension out until a restart** (T18, 2026-11-07): installing a new build refreshes macOS's cache of the app's binary IDs ("Populating the cache with 2 UUID(s)"), but not the extension's entry, which keeps the old build's ID ("1 UUIDs … are already in the cache"). The entry stays switched on, but every request of the new build is refused as "Local network prohibited", without a prompt, and the one-second retry doesn't help. Opening the popover and switching the entry off and on didn't refresh it either. Restarting the Mac did.
- **Rules outlive uninstalls:** macOS kept an app's rule after the app was deleted until the Mac restarted, or until a privacy check found the files gone, and switching an entry on didn't reach a running extension. So test Local Network changes from a clean state: uninstall the app, restart, reinstall. An entry for a deleted app, such as NextcloudAppleMailExtension, can't be removed from the list, and does nothing.
- **A new build's first request is refused:** after a build was installed, the extension's first request failed as offline although the app was allowed. The system log said "Local network allowed by preference … but received prompt. Clearing cached UUIDs": macOS knows a build by its binaries' UUIDs, refuses the first request of new ones, and then lets them through. Every update would hit this once, so the client retries an offline request once after a second (T5b, 2026-11-06).
- **Terminal runs are exempt:** the host app run from a terminal reached the same server, because command-line tools run from Terminal are allowed automatically. Only the app opened normally gets the prompt.

## Installing and AppleScript

- **Replacing the extension while Mail runs:** Mail kept using its connection to the old copy. Its log said "other version in use", and the next send stopped with Mail's own alert, "An error occurred while trying to encrypt your message", without reaching the extension. Quitting and reopening Mail fixed it (T5b, 2026-11-06).
- **Undo Send needs the Send button:** a message sent with AppleScript's `send` goes out at once, without Undo Send. After a click on the window's Send button, Edit > Undo Send undoes it during the undo send delay, 10 seconds by default. The menu only shows Undo Send once it's opened, and reads as a disabled Undo before (T5c).
- **Send Later:** Message > Send Later offers tonight at 21:00, tomorrow at 08:00, or a time to choose. The first time, Mail confirms with a sheet that the message goes out at the scheduled time, and `encode()` runs after that. The scheduled copy, already with the links, waits in the local SendLater mailbox (T5c).
- **Replies made in Mail's window** aren't among AppleScript's outgoing messages, so AppleScript can't add files to them (T5c).
- **Notifications from the extension:** the extension can post notifications with `UNUserNotificationCenter`, under the host app's permission, which macOS asks the user for when the app requests it (T8).
- **AppleScript sends get the send check too:** a message sent with AppleScript's `send` stopped at the send check's alert, with Cancel and Send Anyway, like one sent with the Send button (T7).
- **AppleScript sends go through the extension:** a message that AppleScript made, gave a file and sent from a visible window reached `encode()` with Sign on, so Mail checks can be run without a person at the keyboard ([TESTING.md](TESTING.md#driving-mail-from-the-command-line)). The extension's errors appear in that window as usual, and need a click on OK.

## The toolbar popover

- **Opening it:** the compose session's view controller appears as a popover from the extension's button in the message window's toolbar.
- **Files:** files dropped on it were still readable at send, after about 107 seconds (t24, t25).
- **Typing:** typing in a secure text field works, and `encode()` sees the value at both send calls (t36).
- **Reopened drafts:** what the popover holds is tied to the `contextID`, which a reopened draft doesn't keep. Dropped files were lost (t26). A password was found again by linking each `contextID` to the message ID that `encode()` sees, including at auto-saves (t37).
