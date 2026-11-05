# Probe tests

Every probe test run so far, grouped by what it checks, with its baseline result. The baseline is Mail 16.0 (3901.100.1.1.12) on macOS 27.0.1 (26A434), aarch64, sending from a Gmail account. [PROBE.md](PROBE.md) explains how to run them and read the results.

Test numbers follow the order they were first run, in four rounds. A new test gets the next free number and "Pending" as its result until it has been run, as [PROBE.md](PROBE.md#running-a-round) describes.

How to run any test:

- Send each message to yourself, one at a time, with Encrypt off.
- The Sign column gives the state of Mail's Sign button at send. It's the badge button at the right of the subject line.
- Type some text in each body, as well as the marker in the subject.
- Attach exactly the files listed. They come from `probe/scripts/make-test-files.py`.
- After each send, note whether the window closed straight away, any alert text, and whether the message arrived or stayed in Drafts or Outbox. Take a screenshot of anything Mail shows.

## When `encode()` runs

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `[probe log] t1` | Off | `dummy-1MB.bin` | | Baseline: is `encode()` called with the toggles off, and how often? | No `encode()` at send, only for draft auto-saves. Sent with the file |
| 2 | `[probe ff] t2` | Off | `dummy-1MB.bin` | | Are the returned bytes used with both flags false? | As t1: not rewritten |
| 3 | `[probe tf] t3` | Off | `dummy-1MB.bin` | | Same, flagged signed. Is the MIME damaged? | As t1 |
| 4 | `[probe ft] t4` | Off | `dummy-1MB.bin` | | Same, flagged encrypted. Is the MIME damaged? | As t1 |
| 5 | `[probe ff] t5` | On | `dummy-1MB.bin` | Turn Sign on | Does the toggle change the result? | Two send calls with the same message ID. File removed and note added. The Sent copy is byte-identical to the second call's output. Mail removed `X-Universally-Unique-Identifier` and added `X-Mailer` |
| 6 | `[probe ff nostatus] t6` | Unavailable | `dummy-1MB.bin` | Type the subject before the recipient | Does `encode()` still run if we report we can't sign or encrypt? That would hide the toggles. | The extension reported it can't sign, so Sign was unavailable and there was no `encode()` at send. Sent with the file |
| 18 | `[probe log] t18` | On | `dummy-1MB.bin` | | The extension returns nothing: does the file go as normal, with no signature? | The extension returned nil: sent normally, unsigned, with the file intact |

## Errors

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 7 | `[probe errs] t7` | On | `dummy-1MB.bin` | | Does a signing error stop the send? | Not sent. An alert showed the extension's text with only an OK button, and the draft kept the file. Both send calls still ran |
| 8 | `[probe erre] t8` | On | `dummy-1MB.bin` | | Does an encryption error stop the send? | As t7 |
| 12 | `[probe errs delay=30] t12` | On | `dummy-1MB.bin` | | A slow upload that then fails: is there an alert, and is the file still there? | As t7, after a 32-second wait |

## Waiting for a slow `encode()`

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 9 | `[probe ff delay=30] t9` | On | `dummy-1MB.bin` | While waiting, use another Mail window | What happens on screen during a slow upload? | Mail waited 32 seconds and then sent. No progress display, and other windows stayed usable |
| 10 | `[probe ff delay=120] t10` | On | `dummy-1MB.bin` | | Does Mail wait this long? | Waited 128 seconds, then sent |
| 11 | `[probe ff delay=300] t11` | On | `dummy-1MB.bin` | | Does Mail wait this long, or give up? | Waited 320 seconds with no timeout, then sent |

Only the first send call is delayed. The second returned at once in every test.

## Sizes and Mail Drop

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 13 | `[probe ff] t13` | On | `dummy-5MB.bin` | | Larger file | Rewritten and delivered |
| 14 | `[probe ff] t14` | On | `dummy-10MB.bin` | | Larger file | Rewritten and delivered |
| 27 | `[probe ff min=5] t27` | On | `dummy-1MB.bin`, `dummy-10MB.bin` | | Does the 1 MB file stay attached while the 10 MB one is removed? | The 10 MB file was removed, and the 1 MB file arrived byte-identical |
| 31 | `[probe ff] t31` | On | `dummy-30MB.bin` | Mail Drop off in Settings > Accounts. Screenshot anything Mail shows | Does Mail step in before the extension when a file is over Gmail's 25 MB limit? | Before any extension call, Mail asked whether to use Mail Drop: Use Mail Drop, Try Sending in Email, Cancel, and a "Don't ask again for this account" checkbox. Cancel returned to the message. Nothing was sent |
| 38 | `[probe ff] t38` | On | `dummy-30MB.bin` | Click Send, then Try Sending in Email | Does the extension run after the prompt, and does the message then send? It should arrive with the file removed and the `[MAILPROBE]` note | Two send calls on the 40.5 MB message. The file was removed, and a 761-byte message was delivered |
| 39 | `[probe log] t39` | On | `dummy-30MB.bin` | Click Send, then Use Mail Drop | What does the extension get when Mail Drop is used? The probe leaves this one unchanged, so it arrives as Mail Drop sends it | Three send calls: the whole message, then the message without the file, then about 7 seconds later Mail's Mail Drop message with a `Remote-Attachment-Url` header. The third was delivered |

Don't tick "Don't ask again for this account" while probing. What it remembers and how to undo it are unknown.

## Message structures

The structures themselves are described in [ARCHITECTURE.md](../../docs/ARCHITECTURE.md#what-mail-does-at-send).

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 15 | `[probe ff] t15` | On | `dummy-1MB.pdf`, `dummy-1MB.png` | Type text above, between and below the files | Inline files, and is the text kept in order? | Run with `dummy-1MB.bin` twice by mistake. The text kept its order and both files were removed |
| 16 | `[probe ff] t16` | On | `dummy-1MB.bin` | Format > Make Plain Text | Plain-text messages | Rewritten and delivered |
| 20 | `[probe ff] t20` | On | none | Forward `t1` with its file, and add the marker to the subject | Forwarded files and quoted text | File removed and quoted HTML kept. A U+FFFC was left in the plain text where the file was |
| 28 | `[probe ff min=5] t28` | On | `dummy-1MB.pdf`, `dummy-10MB.png` | Type text above, between and below. Choose Actual Size if offered | The same rule with inline files | PNG removed. The PDF stayed inline and byte-identical, the text kept its order, and Mail didn't resize the PNG. Delivered as plain text with no image placeholder |
| 29 | `[probe ff] t29` | On | `dummy-1MB.pdf`, `dummy-1MB.png` | Type text above, between and below | How does Mail structure inline files, and is the text kept in order? | Inline parts sat between the text parts, in order. In the first call's HTML, the PNG was `<img src="cid:…">` and the PDF `<object data="cid:…">` |
| 30 | `[probe log] t30` | On | `dummy-1MB.png` | Use a signature with the text `Any attachments are confidential.` and an image, and paste a screenshot into the body. If the image won't stay in the signature, untick "Always match my default message font" in Settings > Signatures | How do a logo, a pasted image and an attached file differ, and can the signature's text be told apart? This one goes out unchanged. | In the first call's HTML, the signature and its image were inside `<div id="AppleMailSignature">`. The pasted image was named `PastedGraphic-1.png`. Delivered as `multipart/alternative` with a U+FFFC for each image in the plain text. The delivered HTML dropped the IDs, but each image kept its Content-ID in both calls |
| 34 | `Re: [probe log] t34` | On | none | Reply to `t1`, change the subject to this, and type `See attached.` above the quote | What text does the send check see when there's no file, and how is quoted text marked in a reply? | In the first call's HTML, the quote was in `<div class="AppleOriginalContents">` and `<blockquote type="cite">`, with the "On … wrote:" line inside. The quoted file showed only as `<dummy-1MB.bin>`. Delivered as a single `text/plain` with `>` lines. The send check got Mail's input byte-identical |

## Drafts, recipients, Undo Send and Send Later

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 17 | `[probe ff] t17` | On | `dummy-1MB.bin` | Wait a minute for auto-save, close, reopen from Drafts, send | Drafts, and do they keep the file? | The draft kept the file, and the reopened draft was rewritten at send |
| 19 | `[probe ff] t19` | On | `dummy-1MB.bin` | Add a Bcc to another of your addresses | Does the Bcc recipient get it, and is the Bcc hidden from the To copy? | `Bcc:` was in the extension's input, and Mail removed it before sending. The Bcc recipient got the message, and the Bcc was hidden in the To copy |
| 21 | `[probe ff] t21` | On | `dummy-1MB.bin` | Send, click Undo Send, then send again. Needs an undo delay in Settings > Composing | Is the file back in the window, and does the second send work? | `encode()` ran at the first click. The file was back in the window after undo, and the second send was delivered. Same message ID, new `contextID` |
| 22 | `[probe ff] t22` | On | `dummy-1MB.bin` | Use Send Later, about 2 minutes ahead | Does the rewrite happen when scheduling or when sending? | `encode()` ran when scheduling, and those bytes went out later with only the date updated |

## Send check (compose handler)

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 23 | `[probe block] t23` | Off | `dummy-1MB.bin` | Click Send Anyway in the alert | Can the compose handler stop a file going out without an upload? | An alert with the extension's name, its text, and Cancel and Send Anyway. Send Anyway delivered the file intact. The send check got the whole message |
| 33 | `[probe block] t33` | Off, then on | `dummy-1MB.bin` | Send and click Cancel. Check the window, turn Sign on, change the subject to `[probe ff] t33` and send | Does Cancel return you to the message, and does the second send go through the extension? It should arrive with the file removed and the `[MAILPROBE]` note | Cancel returned to the message with the file. The second send went through the extension. With Sign off, the send check had the file intact |
| 35 | `[probe log] t35` | Off | none | Type `See attached.` | The same with Sign off. t34 and t35 go out unchanged | The send check got the text in the HTML part. The plain-text part was empty |

## Toolbar popover

Click the MailProbe button in the message window's toolbar to open the popover. Drag files from Finder onto it, and it lists them under "Dropped". Note whether the popover stays open while you drag or type.

| # | Subject | Sign | Attach | Steps | Question | Baseline result |
| --- | --- | --- | --- | --- | --- | --- |
| 24 | `[probe ff] t24` | On | Drop `dummy-5MB.pdf` on the popover | Close the popover, then send | Does the drop work, and does the note in the delivered body name the file? | The drop worked, and the note named the file |
| 25 | `[probe ff] t25` | On | Drop `dummy-1MB.bin` and `dummy-10MB.png` on the popover | Wait, then send | Can the extension still read the files after a wait? | The files were still readable at send, after about 107 seconds |
| 26 | `[probe ff] t26` | On | Drop `dummy-1MB.bin` on the popover | Wait for auto-save, close, reopen from Drafts, send | Does a reopened draft keep track of the files? The probe holds them in memory, so I expect not. | The files were lost. The reopened draft gets a new `contextID`, and the probe holds dropped files by `contextID` |
| 36 | `[probe ff] t36` | On | `dummy-1MB.bin` | Type `probe-password-36` in the popover's field, close the popover and send | Can you type in the popover, and does the extension see it at send? The note should say `password=17chars` | Typing worked, and both send calls saw 17 characters |
| 37 | `[probe ff] t37` | On | `dummy-1MB.bin` | Fill in the subject and file first. Type `probe-password-37` in the popover, wait for auto-save, close, reopen from Drafts, and send without opening the popover | Does the password survive a reopened draft? The note should say `password=17chars via-message-id` | The password was found through the message ID: the note says `via-message-id` |

## Not run yet

- **t32:** t31 with Mail Drop on in the account settings. It's off on the baseline account.
- **Another provider:** t27 sent from a non-Gmail account, to see whether the Sent copy differs. The real extension relies on the second send call's output being what's delivered and kept in Sent.
- **"Don't ask again":** what Mail does with later large messages after ticking it with Try Sending in Email, and how to undo it. FR10's setup help assumes Mail then stops asking and sends as if Try Sending in Email had been chosen.
- **Pasted images in other languages:** whether Mail names pasted images other than `PastedGraphic-N.png` when macOS uses another language. The name is the only way the real extension can tell a pasted image from a dropped image file (FR3).
