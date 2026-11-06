# MailProbe

A throwaway Apple Mail extension, used to find out what Mail does with a MailKit extension before building NextcloudMailExtension. It has no Nextcloud code. On send it removes attachments, adds a `[MAILPROBE]` note to the body and logs what Mail did. Only messages with a `[probe …]` marker in the subject are changed or saved.

- [docs/PROBE.md](docs/PROBE.md) explains how the probe works, the Mail behaviour the real extension relies on, and how to probe again, for example after a Mail update.
- [docs/TESTS.md](docs/TESTS.md) has every test, with its steps, question and baseline result.

Quick start, from this folder:

```sh
python3 scripts/make-test-files.py   # creates test-files/ (same bytes every run)
scripts/build-install.sh             # builds, installs to ~/Applications, registers the extension
```

Then in Mail, open Settings > Extensions, enable MailProbe, choose it in the message security popup, and restart Mail. `scripts/collect-results.sh` copies logs and saved messages into `test-results/`, and `scripts/uninstall.sh` removes the probe.

`test-results/` holds full copies of test messages, with personal addresses and mail server headers. Git ignores it, so it stays local.
