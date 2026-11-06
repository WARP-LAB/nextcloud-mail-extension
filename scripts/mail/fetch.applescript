-- Prints the source of the newest message with this subject in all inboxes or all Sent mailboxes, or nothing.
-- Used by scripts/mail.sh. usage: osascript fetch.applescript <inbox|sent> <subject>
on run argv
    set boxKind to item 1 of argv
    set theSubject to item 2 of argv
    tell application "Mail"
        if boxKind is "sent" then
            set found to (messages of sent mailbox whose subject is theSubject)
        else
            check for new mail
            set found to (messages of inbox whose subject is theSubject)
        end if
        if (count of found) is 0 then return ""
        return source of item 1 of found
    end tell
end run
