# Probing Apple Mail

How to check what Apple Mail does with a MailKit extension, using the MailProbe test extension in this repository. Use this after a macOS or Mail update, when the real extension starts misbehaving, or before relying on Mail behaviour nobody has tested.

The real extension depends on Mail behaviour that Apple doesn't document, so an update can break it without warning. This document lists that behaviour, the tests that check it and the baseline results. It also explains how to run tests and read their results. [TESTS.md](TESTS.md) has every test with its steps and baseline result.

## Baseline

Every result here and in [TESTS.md](TESTS.md) comes from:

| | |
| --- | --- |
| Mail | 16.0 (3901.100.1.1.12) |
| macOS | 27.0.1 (26A434) |
| Architecture | aarch64 |
| Account | Gmail, with Mail Drop off |
| Xcode | 27.0 (27A266a), for building the probe |
| Dates | 2026-11-05, four rounds |

Record the same details before re-probing:

```sh
sw_vers
uname -m
defaults read /System/Applications/Mail.app/Contents/Info.plist CFBundleShortVersionString
defaults read /System/Applications/Mail.app/Contents/Info.plist CFBundleVersion
xcodebuild -version
```

## What the real extension relies on

If one of these changes, the design in [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) has to change too. "Message ID" means Mail's `X-Universally-Unique-Identifier` header.

| # | Behaviour | Tests | Baseline |
| --- | --- | --- | --- |
| A1 | `encode()` runs at send only while Sign or Encrypt is on | t1–t6 | Yes. Draft auto-saves call it whatever the toggles |
| A2 | Mail delivers the bytes `encode()` returns, even flagged neither signed nor encrypted. This contradicts Apple's header comment | t5 | Yes |
| A3 | A send makes two `encode()` calls with the same message ID. The send check sees the first call's output, and the second call's output is delivered and kept in Sent | t5, t27, t38 | Yes, Sent copies byte-identical |
| A4 | Auto-saves have `state` 1 and sends `state` 2. Returning nil for an auto-save keeps the draft's files | t17, all rounds | Yes, for all 78 calls in rounds 1 and 2. `X-Apple-Auto-Saved` was missing on 7 of their 30 auto-saves, so don't use headers |
| A5 | Returning nil with Sign on sends the message normally, unsigned | t18 | Yes |
| A6 | An encoder error stops the send, shows the error text with only OK, and keeps the files | t7, t8, t12 | Yes. Both send calls still run |
| A7 | Mail waits for a slow `encode()` | t9–t11 | Yes, up to 320 seconds, with no timeout or progress display |
| A8 | The send check reads the Sign state. An error from it gives Cancel and Send Anyway, and Cancel returns to the message | t23, t33 | Yes |
| A9 | The send check gets the whole message with Sign off. With Sign on it gets the first call's output, or exactly Mail's input when that call returned nil | t33–t35 | Yes |
| A10 | Mail keeps each file's place among the text, and decoded files are byte-identical in both calls | t15, t27–t29 | Yes |
| A11 | The first call's HTML marks the signature with `id="AppleMailSignature"` and quotes with `blockquote type="cite"`. Pasted images are named `PastedGraphic-N.png`, and Content-IDs are the same in both calls | t20, t30, t34 | Yes |
| A12 | Delivered placeholders: U+FFFC in plain text, and `<img src="cid:…">` in HTML | t20, t30 | Yes |
| A13 | Mail removes `Bcc:` and the message ID header before sending | t5, t19 | Yes |
| A14 | Undo Send keeps the message ID but gets a new `contextID`. Send Later encodes at scheduling | t21, t22 | Yes |
| A15 | The toolbar popover accepts drops and typing, and what it holds is available at send. A reopened draft gets a new `contextID` but keeps its message ID | t24–t26, t36, t37 | Yes |
| A16 | Over the provider's size limit, Mail's Mail Drop prompt comes before any extension call. Try Sending in Email then runs the extension as usual, and Use Mail Drop adds a third send call with `Remote-Attachment-Url` | t31, t38, t39 | Yes |

### Quick regression set

After a Mail update, run these first: t5, t7, t9, t18, t29, t30, t33, t34, t36, t37 and t38. That's 11 sends and covers every row above except A14 and the Bcc part of A13. If a result differs from [TESTS.md](TESTS.md), run that section's other tests too.

## The probe

Everything lives in `probe/`, including these docs. Commands in this document run from the repository root.

| Part | Path | What it does |
| --- | --- | --- |
| Overview | `probe/README.md` | What the folder is, quick setup, and links to these docs |
| Host app | `probe/MailProbe/MailProbeApp.swift` | A window with setup instructions. macOS finds the extension through it |
| Extension entry | `probe/MailProbeExtension/MailExtension.swift` | Returns the compose and security handlers |
| Security handler | `probe/MailProbeExtension/SecurityHandler.swift` | `getEncodingStatus`, `encode()` and decode stubs |
| Compose handler | `probe/MailProbeExtension/ComposeHandler.swift` | Send check, extra headers, toolbar popover with drop area and password field |
| Rewriter | `probe/MailProbeExtension/MimeRewriter.swift` | MIME parser and writer: removes files and adds the note |
| Markers | `probe/MailProbeExtension/ProbeDirective.swift` | Reads the `[probe …]` marker from the subject |
| Logging | `probe/MailProbeExtension/ProbeLog.swift` | Writes events and message dumps |
| Config | `probe/Config/` | `Info.plist`, entitlements and signing. Add `probe/Config/Local.xcconfig` to sign with an Apple team |
| Rewriter checks | `probe/Tests/check_rewriter.py`, `probe/Tests/RewriterCheck/main.swift` | Checks the rewriter and markers without Mail |
| Scripts | `probe/scripts/` | Test files, build and install, collect results, uninstall, and the analysis tools `sends.py`, `timeline.py` and `mime_tree.py` (see [Reading the results](#reading-the-results)) |

### Markers

The probe changes or saves only messages whose subject contains a `[probe …]` marker, anywhere and in any case, so `Re: [probe log] t34` works. For other mail it logs only sizes and flags, and Mail sends it as usual.

| Token | Effect on `encode()` at send |
| --- | --- |
| `log` | Log and save the message, return nil. The default |
| `ff` | Remove the files, add the note, return it flagged neither signed nor encrypted |
| `tf`, `ft`, `tt` | As `ff`, flagged signed, encrypted, or both |
| `errs`, `erre` | Return a signing or encryption error |
| `nostatus` | Report that the extension can't sign or encrypt, so Mail disables both buttons |
| `delay=N` | Wait N seconds before answering. Applies once per message, to its first send call |
| `min=N` | With `ff` and the like, remove only files over N decimal MB (N × 1,000,000 decoded bytes) |
| `block` | The send check returns an error, so Mail shows Cancel and Send Anyway |

Tokens combine, as in `[probe ff min=5]` or `[probe errs delay=30]`.

### What it does

- **Auto-saves** (`state` 1): logs and saves the input, then returns nil.
- **Rewrites:** removes every part with an attachment disposition or a file name, or only those over `min=N`. That includes inline images and signature images. It then adds a `[MAILPROBE] …` note at the start of the first `text/plain` part and inside the first HTML `<body>`, and an `X-MailProbe` header. The note lists the call number, removed files, popover files and the password length. A message that is only a file is left unchanged.
- **Send check:** logs, saves the message it gets, and returns an error for `block`.
- **Popover:** dropped files and the typed password are held in memory by `contextID`. Every `encode()` call for a marked message links its `contextID` to the message ID, so a reopened draft still finds the password. Only the password's length is logged.

### Where results go

The extension writes to `~/Library/Containers/lv.warp.mailprobe.extension/Data/Library/Application Support/MailProbe/`, and to the system log under the subsystem `lv.warp.mailprobe`.

- `events.jsonl` has one JSON object per event, with times in UTC.
- `<pid>-<sequence>-call<N>-in.eml` and `-out.eml` are what `encode()` got and returned. `call` counts per message ID, auto-saves included, and `sequence` counts per process.
- `<pid>-can-send-<milliseconds>.eml` is what the send check got.
- Messages over 32,000,000 bytes aren't saved, but their structure and header names are still logged.

| Event | When | Useful fields |
| --- | --- | --- |
| `status` | Mail asks whether the extension can sign or encrypt | `shouldSign`, `reportedCanEncode` |
| `encode-marked` | `encode()` for a marked message | `state`, `call`, `messageID`, `contextID`, `rawBytes`, `structure`, `headerNames`, `sha256` |
| `encode-skipped-autosave` | Auto-save answered with nil | `sequence` |
| `encode-finished` | `encode()` answered | `returnedBytes`, `strippedParts`, `elapsedSeconds` |
| `encode-unmarked` | `encode()` for unmarked mail | Sizes and flags only |
| `delay-start`, `delay-end` | Around a `delay=N` wait | `seconds` |
| `compose-begin`, `compose-end` | Message window opened or closed. `compose-end` rarely fires | `contextID`, `shouldSign` |
| `compose-additional-headers` | Mail asks for extra headers, at each send call | |
| `compose-can-send` | The send check | `shouldSign`, `rawBytes` |
| `compose-can-send-dumped` | The send check's message was saved | `file` |
| `compose-popover` | The toolbar button was clicked | `contextID` |
| `popover-drop`, `popover-files-at-encode` | Files dropped, and seen at send | `files` with `readableBytes` |
| `popover-password`, `popover-password-at-encode` | Password typed, and seen at send | `characters`, `viaMessageID` |
| `decode-called` | Mail showed a message carrying `X-MailProbe` | `bytes` |

## Running a round

1. **Test files:** run `python3 probe/scripts/make-test-files.py`. It writes the same bytes every time.
2. **Install:** run `probe/scripts/build-install.sh`. It builds, installs to `~/Applications`, since `~/Downloads` is privacy-protected, and registers the extension. You can build `probe/MailProbe.xcodeproj` in Xcode instead, then open the app once so macOS finds the extension.
3. **Enable:** the first time, and after any Mail update, open Mail's Settings > Extensions. Enable MailProbe, choose it in the message security popup, then restart Mail. `pluginkit -m -p com.apple.email.extension` should list one MailProbe.
4. **Clear the logs:** run `probe/scripts/collect-results.sh --clear`. It copies the old logs to `probe/test-results/` first.
5. **Write the round:** add each new test to [TESTS.md](TESTS.md), in its topic's table, with the next free number, its subject, files, steps and question, and "Pending" as the result.
6. **Send:** run each pending test as written. Check the Sign button before every send. Note whether the window closed straight away, any alert text, and whether the message arrived or stayed in Drafts or Outbox.
7. **Save messages:** drag them from Mail to `probe/test-results/round<N>/` as `t<N>-received.eml` and `t<N>-sent.eml`. For tests that didn't send, save `t<N>-draft.eml` and `t<N>-screenshot.png`.
8. **Collect:** run `probe/scripts/collect-results.sh`. It copies the container and recent system log into `probe/test-results/<timestamp>/`.
9. **Record:** replace each "Pending" in [TESTS.md](TESTS.md) with the result, and update the "Tested" claims in ARCHITECTURE.md and the PRD's test status.

When re-probing after an update, keep the old baseline in TESTS.md and note the new result next to it, with the Mail version.

## Reading the results

```sh
python3 probe/scripts/sends.py probe/test-results/<timestamp>              # one line per click on Send
python3 probe/scripts/timeline.py probe/test-results/<timestamp> --since 21:00:00
python3 probe/scripts/mime_tree.py probe/test-results/round<N>/t<N>-received.eml probe/test-results/<timestamp>/<dump>.eml
cmp probe/test-results/<timestamp>/<pid>-<sequence>-call<N>-out.eml probe/test-results/round<N>/t<N>-sent.eml
```

`mime_tree.py` names any part that matches a file in `probe/test-files/`, and counts the markers listed in A11 and A12.

| Question | Where to look |
| --- | --- |
| Which events belong to which test? | Match the `marker` and time, then follow `contextID` and `messageID` |
| Did `encode()` run at send? | `encode-marked` with `state` 2 |
| Did the extension run at all? | `compose-additional-headers` or `compose-can-send` for that `contextID`. t31 had neither |
| Which call's output was delivered? | `cmp` the Sent copy with each `-out.eml`, or with `-in.eml` when the probe returned nil |
| What did the send check get? | The `can-send` dump. Its `rawBytes` equals the previous `encode-finished` `returnedBytes`, or the input size after nil |
| How long did Mail wait? | `elapsedSeconds` in `encode-finished` |
| Did the Sign state change? | `shouldSign` in `status` and `compose-*` events |

## Changing the probe

- **New marker token:** add it in `ProbeDirective.swift`, then add a directive check to `probe/Tests/check_rewriter.py`.
- **Rewriter change:** edit `MimeRewriter.swift`, add a fixture to `probe/Tests/check_rewriter.py`, and run `python3 probe/Tests/check_rewriter.py`.
- **Check without building:** `xcrun swiftc -typecheck -parse-as-library -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos15.0 -swift-version 5 probe/MailProbeExtension/*.swift`
- **Privacy:** never log the content of unmarked mail, and never log passwords, only their length.
- **One copy only:** don't build a second copy of the app anywhere else. macOS can register both extensions under the same bundle ID.

## Lessons from the first rounds

- **Sign stays on:** the Sign button keeps its state across messages and Mail restarts. Leaving it on changed round 1's t7 and t8, so check it before every send.
- **Read Sign at send:** `compose-begin` can report Sign off and then correct itself. Only the send-time reading is reliable.
- **UTC times:** logged times are UTC, while Mail shows local time.
- **Exact files:** t15 ended up with the same `.bin` file twice, so inline PDFs and PNGs had to wait for round 3.
- **Marker before auto-save:** the probe links contexts to message IDs only for marked messages. In t37, type the subject before waiting for the auto-save.
- **Missing events are results:** when Mail stops a send itself, as in t31, nothing is logged for it. Screenshots and notes are the only record.
- **Large dumps:** inputs over 32 MB aren't saved (t38, t39), but their structure and headers are logged.
- **Don't tick "Don't ask again":** in the Mail Drop prompt, it changes later sends from that account in a way nobody has worked out how to undo.
- **Privacy prompt:** `collect-results.sh` reads another app's container, so macOS may ask for permission.
- **Repeated copies:** each `probe/test-results/<timestamp>/` holds everything since the last `--clear`, so a folder can repeat an earlier round.
- **Personal data:** results hold full messages with addresses and mail server headers, and the system log copy can include Mail's own lines about encoding unmarked mail. Keep them local.
- **zsh:** when writing quick one-liners, `echo ======` fails because of `=` expansion, and `PIPESTATUS` only exists in bash.

## Results so far

| Path | Contents |
| --- | --- |
| `probe/test-results/20261105-152852/` | Round 1 logs, t1–t8 |
| `probe/test-results/20261105-170130/` | Round 2 logs, t9–t26 |
| `probe/test-results/20261105-230344/` | Rounds 3 and 4 logs, t27–t39. Round 4 is after 21:00 UTC |
| `probe/test-results/t1-…` to `probe/test-results/t8-…` | Round 1 messages and screenshots |
| `probe/test-results/round2/`, `round3/`, `round4/` | Rounds 2–4 messages and screenshots |
| `probe/test-results/README-original.md` | The README as used for rounds 1–4, with each round's original instructions |

Three copies collected between rounds repeated these logs and were deleted. Each folder above is complete for its rounds.

## Removing the probe

Turn it off in Mail's Settings > Extensions, or run `probe/scripts/uninstall.sh` to remove the app, its logs and its dumps. While it's enabled, every outgoing message passes through it.
