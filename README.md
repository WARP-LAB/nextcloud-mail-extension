# Nextcloud Mail Extension (for Apple Mail)

NextcloudMailExtension is an extension for Apple Mail on macOS. When you send an email, its attachments are uploaded to your Nextcloud server and replaced in the email by share links. Recipients download the files from your server, and your email stays small — no more bounces for oversized mail, no more dependence on Apple's Mail Drop or a provider's attachment limit.

## User's manual

> [!TIP]
> **[Read the user manual →](https://warp-lab.github.io/nextcloud-mail-extension/)**
> How to install, use, config options

## Rant on history and this extension

I was a user of [cargolifter-mail-plugin](https://github.com/WARP-LAB/cargolifter-mail-plugin) which I liked. Back then, doing something like this for Apple Mail involved accessing private APIs, monkey patching (`JRSwizzle`) etc., and naturally at one major Mail upgrade it had to end.

[Sendent's Nextcloud for Mail](https://apps.apple.com/lv/app/nextcloud-for-mail/id6758224475?mt=12) exists, but it is exactly what I don't want - a situation of multiple followup emails to receiver about some files to download, I want everything contained in the mail, and also inline links. They probably went that direction exactly because direction I took is _grey_.

NextcloudMailExtension uses public interface - MailKit's public extension point, no private APIs etc, **but still IMHO it is a hack**, as we are acting as if we are signing the email, although we are not. Semantics matter to me. That is the only way some Apple Mail extension can alter message data (the only way to change an outgoing email is the message security handler's `encode()`). If you are using something in Apple Mail to truly sign messages then you are out of luck, as Mail uses one message security extension at a time, so you can't sign with certificates while this one is chosen (GPG anyone?). Also, this thing might not be sustainable, because Apple changes things - let us hope that the change would be MailKit API that is meant for something like this by design. Then again I have tickets about API behaviour in Apple Radar since 2009 that are not yet resolved.
