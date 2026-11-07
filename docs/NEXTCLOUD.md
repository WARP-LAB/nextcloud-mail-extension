# Nextcloud API

The Nextcloud requests the design in [ARCHITECTURE.md](ARCHITECTURE.md) uses, and how the server behaves. The share, password and expiry behaviour was first read from the Nextcloud server's source code on 2026-11-05: `ShareAPIController.php`, `Manager.php`, `Capabilities.php`, `ShareController.php`, `AuthPublicShareController.php` and the password policy app's `PasswordPolicyConfig.php`.

Everything here was then run against the test server (D14) on 2026-11-06, which runs Nextcloud 35.0.2. The enforced expiry maximum and enforced passwords were run with the server's settings changed for the test (T3b, D18). The server tests in `tests/NextcloudServerTests` repeat these checks.

## Requests

| Step | Request | What the server did |
| --- | --- | --- |
| Log in | Login Flow v2: `POST /index.php/login/v2` returns `login`, the page to open in the browser, and `poll` with `endpoint` and `token`. Then `POST` the token to the endpoint until it returns `server`, `loginName` and `appPassword` | The endpoint answers 404 until the user has logged in. The extension never sees the user's password |
| Log out | `DELETE /ocs/v2.php/core/apppassword` | 200. The app password then gets 401 |
| Find the user ID | `GET /ocs/v2.php/cloud/user` | Its `id` is what WebDAV paths need, which can differ from the login name |
| Read server limits | `GET /ocs/v2.php/cloud/capabilities` | See [Capabilities](#capabilities) |
| Create a folder | `MKCOL /remote.php/dav/files/<user>/<path>` | 201. 405 when the folder exists, 409 when its parent doesn't |
| Upload | `PUT /remote.php/dav/files/<user>/<path>/<name>`, with `If-None-Match: *` | 201. 412 when the file exists, because of the header, and 409 when its folder doesn't |
| Share a file or folder | `POST /ocs/v2.php/apps/files_sharing/api/v1/shares` with `path`, `shareType=3` (public link), `expireDate`, and `password` if set | The response's `data` has `id` (a string), `token`, `url` and `expiration`. See [Rate limit](#rate-limit) |
| Change a password | `PUT /ocs/v2.php/apps/files_sharing/api/v1/shares/<id>` with `password` | 200. The old password stops working at once. An empty `password` removes it, and the link then opens without one |
| Check a password | `POST /ocs/v2.php/apps/password_policy/api/v1/validate` with `password` | 200, with `passed` and, when it's false, `reason`, every broken rule in one message. Needs the login (T16) |
| Generate a password | `GET /ocs/v2.php/apps/password_policy/api/v1/generate` | 200, with a `password` the policy accepts: on the test server 10 characters of upper case, lower case and digits |
| Delete a share | `DELETE /ocs/v2.php/apps/files_sharing/api/v1/shares/<id>` | 200, then the link gives 404. Again: 404, "Wrong share ID, share does not exist" |
| Delete a file or folder | `DELETE /remote.php/dav/files/<user>/<path>` | 204, and 404 when it's gone. It goes to the user's trash bin, where it still counts against the quota until the trash expires. Deleting a folder deletes its shares too |

- **Headers:** OCS requests need `OCS-APIRequest: true`, and `Accept: application/json` for JSON. Each request sends Basic auth with the login name and the app password.
- **Errors:** OCS errors have the HTTP status, and `ocs.meta.message` gives the reason. WebDAV errors give it in `<s:message>`, such as "The resource you tried to create already exists".
- **Names:** WebDAV paths are percent-encoded name by name. Names with accents, spaces, `#` and `%` uploaded and downloaded unchanged.
- **Cookies:** the server sets a session cookie tied to the app password that made the request. A client that keeps cookies and then uses another app password, or one that was revoked, gets 401. The client keeps no cookies.
- **Large files:** single `PUT` requests may hit server or proxy limits on very large files. Nextcloud also has a chunked upload API for those. The test server's `files.chunked_upload.max_size` is 100 MB.
- **Testing without a browser:** `GET /ocs/v2.php/core/getapppassword` with the account password returns an app password. Only the tests and the command-line tool use it (D14).

## Server settings

An admin sets the sharing rules in Administration settings > Sharing. They are keys of the `core` app's config, which the provisioning API reads and changes with `GET`, `POST` (with `value`) and `DELETE` on `/ocs/v2.php/apps/provisioning_api/api/v1/config/apps/core/<key>`. Without a key, its default applies. The test server had none of these set.

| Key | Meaning |
| --- | --- |
| `shareapi_default_expire_date` | `yes`: link shares get an expiry date by default |
| `shareapi_expire_after_n_days` | The default number of days, `7` when unset |
| `shareapi_enforce_expire_date` | `yes`: the default is also the maximum |
| `shareapi_enforce_links_password` | `yes`: link shares need a password |

Changing or deleting a key asks for the password to be confirmed. An app password gets 403, "Password confirmation is required", while Basic auth with the account's own password works. Reading keys works with an app password.

## Capabilities

- **`files_sharing.public.expire_date`:** whether link shares get an expiry date by default (`enabled`), the default number of days (`days`), and whether that is a maximum (`enforced`). With `enabled` false, the other two are left out.
- **`files_sharing.public.password.enforced`:** whether link shares must have a password.
- **`password_policy`:** the password policy app's rules, such as `minLength`.
- **`version.string`:** such as `35.0.2`.

The test server has no default expiry and no enforced password. Its password policy asks for 10 characters, and rejects common passwords and ones found in Have I Been Pwned.

## Unavailable

What the client gets when the server or the network is unavailable, with each server state set by `scripts/server-state.sh` on the test server (T21, 2026-11-07), and the `NextcloudError` it becomes:

| State | What the requests get | Error |
| --- | --- | --- |
| Maintenance mode (`occ maintenance:mode --on`) | OCS: 503 with `X-Nextcloud-Maintenance-Mode: 1` and "Service unavailable". WebDAV: 503 with `ServerMaintenanceMode`, "System is in maintenance mode." `status.php`: 200 with `"maintenance": true` | `maintenance` |
| PHP-FPM down, nginx running | Every request: nginx's 502 Bad Gateway page | `unavailable(status: 502)` |
| The site switched off in nginx | The server's default site: OCS 404 and WebDAV 405, as HTML pages. `status.php` still answered, from another site | `notNextcloud(status: 404)` |
| A name that doesn't resolve | URLSession -1003, "A server with the specified hostname could not be found." | `cannotFindServer` |
| Nothing listening at the address | -1004, "Could not connect to the server." | `cannotConnect` |
| No answer | -1001, "The request timed out.", after up to 60 seconds | `timedOut` |
| No network | -1009, like a request Local Network privacy blocks. The client asks `NWPathMonitor` whether the Mac has a network at all | `noNetwork`, else `offline` |

- **Where it shows:** every request goes through `NextcloudClient+Network.swift`, so the app's Test connection, the popover's red text and Mail's send alert give the same text. The send's alert adds how to send anyway: turn off Sign, and the files go attached.
- **Not tried live:** no network, and a failing DNS, which would cut this Mac off; the unit tests cover them with the errors URLSession reports.

## Share labels and tags

Ways to make an email's files findable on the server later, read from Nextcloud 35's source and tried on the test server with a throwaway file on 2026-11-08 (T22):

- **Share label:** a link share takes `label`, up to 255 characters, when it's created (`POST …/shares` with `label`) or later (`PUT …/shares/<id>` with `label`), and returns it. The Files app shows it as the link's name in the share's entry in the sidebar (`SharingEntryLink.vue`). The sharing views, such as "Shared by link", neither show it nor filter or search by it (`apps/files_sharing/src/files_views/shares.ts`), so it tells this extension's links apart on an item, but doesn't help find files.
- **Collaborative tags:** `POST /remote.php/dav/systemtags/` with `{"name", "userVisible": true, "userAssignable": true}` creates a tag, whose ID ends the `Content-Location` header. `PUT /remote.php/dav/systemtags-relations/files/<file ID>/<tag ID>` assigns it, 201. An upload's `OC-FileId` header gives the file ID. A `REPORT` with `oc:filter-files` and `oc:systemtag` finds the tagged files, as the Files app's Tags view does (`apps/systemtags/src/files_views/systemtagsView.ts`).
- **Who may tag:** any user may create tags, unless an admin has set the `systemtags` app's `restrict_creation_to_admin` (off by default). Tags that are visible and assignable to users can be assigned by anyone. Tags are server-wide: one tag name is shared by every user, and each user sees only the files they can access.

## Rate limit

Nextcloud 34 and 35 allow each user 20 share creations in 10 minutes: `createShare` has `#[UserRateLimit(limit: 20, period: 600)]`. Refused attempts count too. The 21st gets HTTP 429 "Too Many Requests", seen when the server tests ran twice in a row. Uploads, folders and password changes aren't limited this way.

An admin can raise the limit in `config.php`:

```php
'ratelimit_overwrite' => [
    'files_sharing.shareapi.createshare' => ['user' => ['limit' => 200, 'period' => 600]],
],
```

By default the extension uses one share per email, of its folder (D17, R21).

## Share links

| Link | URL |
| --- | --- |
| View a shared file | The share's `url`, which is `/s/<token>` |
| Download a shared file | `/s/<token>/download`, which answers 303 to `/public.php/dav/files/<token>` |
| View a shared folder | The folder share's `url` |
| Download a shared folder | The folder share's `/s/<token>/download`, which answers 303 to `/public.php/dav/files/<token>?accept=zip` |
| Download one file from a folder share | `/s/<token>/download?files=<name>`, which answers 303 to `/public.php/dav/files/<token>/<name>` |

- **Folder zips:** `application/zip`, named `<folder>.zip`, with the folder as the zip's top level. Names are UTF-8 with the zip's UTF-8 flag set, so macOS's Archive Utility shows accents correctly. The old `unzip` command doesn't.
- **Password pages:** without the password, the view link goes to `/s/<token>/authenticate/showshare` and the download link to `/s/<token>/authenticate/downloadshare`. Both are password pages with status 200, so a script downloading the link gets HTML, not the file.
- **Public WebDAV:** `/public.php/dav/files/<token>` accepts Basic auth with the user `anonymous` and the share's password. A wrong password gives 401.
- **Downloaded names need debug mode off:** a file's download carries its name in `Content-Disposition` only when the server's `config.php` doesn't set `'debug' => true` (`ServerFactory` creates the DAV `FilesPlugin` with `downloadAttachment` set to `!$debugEnabled`). Otherwise a browser names the file after the last part of the address: a file's own share then downloads as its token, while one file of a folder share still gets its name from the path. Zips are named either way. The test server ran in debug mode until 2026-11-07, which the user found from a download named after its token.
- **Hidden downloads:** a share with "hide download" set fails to download. Shares created without that setting are unaffected.
- **No view page for one file in a folder share.** A link can't open one file of a folder share in Nextcloud's viewer: the public page opens the viewer only for a share of a single file, and reads no file from the URL (`apps/files_sharing/src/init-public.ts`, stable35). The public page's router has only `/s/:token`, so the address can't name a file either (`apps/files_sharing/src/router/index.ts`, rechecked 2026-11-07). A file in a folder share at `/public.php/dav/files/<token>/<name>` comes with `Content-Disposition: attachment`, so it downloads; it only showed inline while the test server ran in debug mode (D20).
- **One file of a folder share, by name:** the redirect puts the name into the WebDAV path without encoding it, so a name with `#`, `%` or `?` is cut or broken and gets 404 or an error. Spaces, accents, `&`, `+`, `;`, `=`, `@`, `,`, quotes, brackets and full-width characters worked. A file's own share downloads any name. Tested 2026-11-06.
- **One file of a password-protected folder share:** `?files=` survives the password page. After the password, the page redirects to that file alone (`downloadsOneFileOfAFolderShareAfterItsPassword`).

## Passwords

- **No password:** an empty `password` means none.
- **Enforced passwords:** when the server enforces passwords, creating a share without one fails with 403, "Passwords are enforced for link and mail shares", and the capabilities say `password.enforced` (T3b).
- **Password policy:** a rejected password gets 400, with every broken rule in one message, such as "Password is among the 1,000,000 most common ones. Please make it unique. Password needs to be at least 10 characters long. Password is present in compromised password list. Please choose a different password." Changing a share's password to a weak one is rejected the same way.

## Expiry

- **`expireDate`** takes a date as `YYYY-MM-DD`. The response's `expiration` is that date at `23:59:59`, when the link expires, in the server's or account's time zone.
- **No time of day:** a time sent with the date, as `2026-11-07 15:30:00` or `2026-11-07T15:30:00+02:00`, is accepted and dropped. The link still expires at `23:59:59` that day (tested 2026-11-06).
- **An empty string** means no expiry, and `expiration` is null.
- **Omitting it** applies the server default. With none, as on the test server, the link doesn't expire.
- **A date far ahead,** such as 2099-01-01, is accepted when there's no enforced maximum.
- **A date in the past** gets 404, "Expiration date is in the past".
- **Enforced maximum:** "no expiry" silently becomes the maximum, today plus the default days, and a later date is rejected with 404, "Cannot set expiration date more than 7 days in the future" for a 7-day maximum. A date at the maximum is accepted (T3b).
- **After expiry:** the share is deleted when someone next opens it, but the file stays in its folder.
