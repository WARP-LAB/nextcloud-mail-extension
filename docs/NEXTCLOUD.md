# Nextcloud API

The Nextcloud requests the design in [ARCHITECTURE.md](ARCHITECTURE.md) uses, and how the server behaves. The share, password and expiry behaviour was read from the Nextcloud server's source code on 2026-11-05: `ShareAPIController.php`, `Manager.php`, `Capabilities.php`, `ShareController.php`, `AuthPublicShareController.php` and the password policy app's `PasswordPolicyConfig.php`. The rest is standard API use. None of it has been run against a server yet (R19), so update this file with what testing finds.

## Requests

| Step | Request | Notes |
| --- | --- | --- |
| Log in | Login Flow v2: `POST /index.php/login/v2`, open the returned URL in the browser, then poll for `server`, `loginName` and `appPassword` | The extension never sees the user's password |
| Find the user ID | `GET /ocs/v2.php/cloud/user` | WebDAV paths need the ID, which can differ from the login name |
| Read server limits | `GET /ocs/v2.php/cloud/capabilities` | See [Capabilities](#capabilities) |
| Create a folder | `MKCOL /remote.php/dav/files/<user>/<path>` | Fails when the folder exists |
| Upload | `PUT /remote.php/dav/files/<user>/<path>/<name>`, with `If-None-Match: *` | The header makes the server refuse to overwrite an existing file |
| Share a file or folder | `POST /ocs/v2.php/apps/files_sharing/api/v1/shares` with `path`, `shareType=3` (public link), `expireDate`, and `password` if set | The response gives `id`, `url` and `expiration` |
| Change a password | `PUT /ocs/v2.php/apps/files_sharing/api/v1/shares/<id>` with `password` | |
| Delete a share or file | `DELETE /ocs/v2.php/apps/files_sharing/api/v1/shares/<id>`, `DELETE /remote.php/dav/files/<user>/<path>` | |

OCS requests need the header `OCS-APIRequest: true`. Single `PUT` requests may hit server or proxy limits on very large files. Nextcloud also has a chunked upload API for those.

## Capabilities

- **`files_sharing.public.expire_date`:** whether link shares get an expiry date by default (`enabled`), the default number of days (`days`), and whether that is a maximum (`enforced`).
- **`files_sharing.public.password.enforced`:** whether link shares must have a password.

## Share links

| Link | URL |
| --- | --- |
| View a shared file | The share's `url`, which is `/s/<token>` |
| Download a shared file | `/s/<token>/download`, which redirects to `/public.php/dav/files/<token>` |
| View a shared folder | The folder share's `url` |
| Download a shared folder | The folder share's `/s/<token>/download`, which redirects with `accept=zip` and gives one zip file |

- **Password pages:** a visitor without the password of a protected share is sent to `/s/<token>/authenticate/<redirect>`, then continues to the page or download.
- **Hidden downloads:** a share with "hide download" set fails to download. Shares created without that setting are unaffected.
- **Single files from a folder share:** `/s/<token>/download?files=<name>` downloads one file, but there's no view page for a single file inside a folder share.

## Passwords

- **No password:** an empty `password` means none.
- **Enforced passwords:** when the server enforces passwords, creating a share without one fails with "Passwords are enforced for link and mail shares".
- **Password policy:** the password policy app can reject a password with a 400 response and a reason. Its default minimum is 10 characters, and admins can add rules.

## Expiry

- **`expireDate`** takes a date as `YYYY-MM-DD`. A link expires at 23:59:59 on that date, in the server's or account's time zone.
- **Omitting it** applies the server default. An empty string means no expiry.
- **Enforced maximum:** "no expiry" silently becomes the server default, and a later date is rejected with "Cannot set expiration date more than %n days in the future".
- **After expiry:** the share is deleted when someone next opens it, but the file stays in its folder.
