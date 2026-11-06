-- Replies to or forwards the newest message with this subject in the inboxes, adding files, and sends it.
-- Used by scripts/mail.sh. usage: osascript respond.applescript <reply|forward> <subject> <forward to address> [file ...]
on run argv
    set action to item 1 of argv
    set theSubject to item 2 of argv
    set toAddress to item 3 of argv
    tell application "Mail"
        set found to (messages of inbox whose subject is theSubject)
        if (count of found) is 0 then error "No message with that subject in the inboxes."
        if action is "forward" then
            set msg to forward (item 1 of found) with opening window
            make new to recipient at end of to recipients of msg with properties {address:toAddress}
        else
            set msg to reply (item 1 of found) with opening window
        end if
        repeat with index from 4 to count of argv
            tell content of msg to make new attachment with properties {file name:(POSIX file (item index of argv)) as alias} at after last paragraph
        end repeat
        -- As in send.applescript, the files need a moment before sending.
        delay 3
        send msg
    end tell
end run
