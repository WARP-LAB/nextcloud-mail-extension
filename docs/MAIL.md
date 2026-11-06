# Apple Mail behaviour

What Apple Mail does with a MailKit extension, as far as the design in [ARCHITECTURE.md](ARCHITECTURE.md) depends on it. Apple documents little of this, so everything here was found by probing with the MailProbe test extension in Mail 16.0 (3901.100.1.1.12) on macOS 27.0.1 (26A434), aarch64, with a Gmail account.

`tN` is a test in [probe/docs/TESTS.md](../probe/docs/TESTS.md), with its logs and messages in `probe/test-results/`, which stays local. After a macOS or Mail update, rerun the quick regression set in [probe/docs/PROBE.md](../probe/docs/PROBE.md), then update this file and [RISKS.md](RISKS.md).

## The Sign button

- **Upload switch:** `encode()` runs at send only while Sign or Encrypt is on (t1–t5). Draft auto-saves call it whatever the toggles.
- **Returned bytes are delivered:** Mail sends the message `encode()` returns, even when it's flagged as neither signed nor encrypted (t5). Apple's header comment suggests otherwise, so this may change (R1).
- **No contents in the status call:** `getEncodingStatus` doesn't get the message's contents, so whether Sign is offered can't depend on attachments. Reporting that the extension can't sign makes the button unavailable, and `encode()` then doesn't run at send (t6).
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

In the first call's structure, the typed text is only in the HTML (t15, t24, t34, t35). The HTML also marks:

- **Quoted text:** inside `<blockquote type="cite">`, which a reply wraps in `<div class="AppleOriginalContents">`. The "On … wrote:" line is inside the quote (t20, t34). A file in the quoted message appears only as its name in angle brackets.
- **Signature:** inside `<div id="AppleMailSignature">`, including its image (t30). The second call's HTML drops these IDs and classes, but each image keeps the same Content-ID in both calls.
- **Pasted images:** named `PastedGraphic-1.png` and so on, while a dropped file keeps its own name (t30). Both are `inline` `image/png` parts.

Decoded files are byte-identical in both calls (t15). Mail didn't resize a 10 MB PNG (t28), and every kept or removed file matched the original byte for byte.

Mail chooses each file's transfer encoding by its content. The 10 MB test PNG, mostly padding text, was quoted-printable in both of t28's calls, while the other files were base64. Lines end in LF, not CRLF, in all 165 saved send calls.

## The toolbar popover

- **Opening it:** the compose session's view controller appears as a popover from the extension's button in the message window's toolbar.
- **Files:** files dropped on it were still readable at send, after about 107 seconds (t24, t25).
- **Typing:** typing in a secure text field works, and `encode()` sees the value at both send calls (t36).
- **Reopened drafts:** what the popover holds is tied to the `contextID`, which a reopened draft doesn't keep. Dropped files were lost (t26). A password was found again by linking each `contextID` to the message ID that `encode()` sees, including at auto-saves (t37).
