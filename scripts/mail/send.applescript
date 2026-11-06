-- Builds and sends a message in Mail. Used by scripts/mail.sh, which reads the addresses from .env.
-- usage: osascript send.applescript <from address> <to address> <subject> <body> <signature|none> [file ...]
on run argv
    set fromAddress to item 1 of argv
    set toAddress to item 2 of argv
    set theSubject to item 3 of argv
    set theBody to item 4 of argv
    set keepSignature to (item 5 of argv) is "signature"
    tell application "Mail"
        set msg to make new outgoing message with properties {subject:theSubject, content:theBody & return & return, visible:true, sender:fromAddress}
        tell msg
            if not keepSignature then set message signature to missing value
            make new to recipient at end of to recipients with properties {address:toAddress}
            repeat with index from 6 to count of argv
                tell content to make new attachment with properties {file name:(POSIX file (item index of argv)) as alias} at after last paragraph
            end repeat
        end tell
        -- Mail adds attachments in the background, and sends without them if sent at once.
        delay 3
        send msg
    end tell
end run
