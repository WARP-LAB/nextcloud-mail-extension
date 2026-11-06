import SwiftUI

/// The host app's window: the account, every setting, the connection checks and the setup help.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                AccountSection(model: model)
                uploads
                files
                links
                warnings
                check
                SetupHelp()
            }
            .formStyle(.grouped)
            Text(Self.version)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 600, idealHeight: 860)
    }

    /// Such as "Version 0.1.0 (1)": the version and the build number (D22).
    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "Version \(version) (\(build))"
    }

    /// FR2.
    private var uploads: some View {
        Section {
            TextField("Directory", text: $model.settings.directory, prompt: Text(Settings.defaultDirectory))
        } header: {
            Text("Uploads")
        } footer: {
            Text(
                "Each email's files go in a folder of their own inside this directory on Nextcloud, named with the "
                    + "time of sending and the subject, such as “2026-11-05-14-03-09 Report”."
            )
            .foregroundStyle(.secondary)
        }
    }

    /// FR3.
    private var files: some View {
        Section {
            Picker("Files that become links", selection: $model.settings.onlyLargeFiles) {
                Text("All attachments").tag(false)
                Text("Only attachments over a size").tag(true)
            }
            if model.settings.onlyLargeFiles {
                DecimalField(label: "Larger than, in MB", value: $model.settings.sizeLimitMegabytes)
                Picker("Size limit applies to", selection: $model.settings.sizeLimitScope) {
                    Text("Each file").tag(Settings.SizeLimitScope.eachFile)
                    Text("All files together").tag(Settings.SizeLimitScope.allFiles)
                }
            }
            Toggle("Pasted images become links", isOn: $model.settings.pastedImagesBecomeLinks)
        } header: {
            Text("Which files become links")
        } footer: {
            Text(filesFooter).foregroundStyle(.secondary)
        }
    }

    private var filesFooter: String {
        let signature = "Images in your signature always stay in the email."
        guard model.settings.onlyLargeFiles && model.settings.sizeLimitScope == .allFiles else {
            return signature
        }
        return "When the files together are larger than the limit, all of them become links, and otherwise they "
            + "all stay attached. " + signature
    }

    /// FR4, FR8, FR9 and D17.
    private var links: some View {
        Section {
            Picker("Share files as", selection: $model.settings.sharing) {
                Text("One link for the email's folder").tag(Settings.Sharing.folder)
                Text("A link for each file").tag(Settings.Sharing.eachFile)
            }
            if model.settings.sharing == .folder {
                Picker("Links in the email", selection: $model.settings.placement) {
                    Text("Where each file was").tag(Settings.Placement.whereEachFileWas)
                    Text("Only the folder's links").tag(Settings.Placement.folderLinksOnly)
                }
            }
            Picker("Show download link for file", selection: $model.settings.linkStyle) {
                Text("Together with view link").tag(LinkText.Style.viewAndDownload)
                Text("Only").tag(LinkText.Style.downloadOnly)
            }
            .disabled(model.settings.onlyFolderLinks)
            Toggle(
                "If multiple attachments, add view and download links at the bottom",
                isOn: $model.settings.folderLinks
            )
            .disabled(model.settings.onlyFolderLinks)
            ExpiryPicker(expiry: $model.settings.expiry)
        } header: {
            Text("Links")
        } footer: {
            Text(linksFooter).foregroundStyle(.secondary)
        }
    }

    private var linksFooter: String {
        switch (model.settings.sharing, model.settings.placement) {
        case (.folder, .whereEachFileWas):
            return "Each file's view link opens the email's folder, and its download link downloads only that file."
        case (.folder, .folderLinksOnly):
            return "The email lists the files' names and sizes, followed by links that view and download its folder."
        case (.eachFile, _):
            return "Nextcloud allows 20 new links in 10 minutes, so an email with many files can fail to send until "
                + "the server's admin raises that limit. See Setting up Mail."
        }
    }

    /// FR5 and FR6.
    private var warnings: some View {
        Section {
            Toggle("Warn if signing (upload via link) is disabled", isOn: $model.settings.warnIfSignOff)
            LabeledContent("Warn if text found but no attachment") {
                TagField(tags: $model.settings.warningPhrases, prompt: "Type a word or phrase, then Return")
            }
        } header: {
            Text("Warnings")
        } footer: {
            Text(
                "Such as “attach” or “see attached”. Upper and lower case count the same, and a word is also found "
                    + "inside longer words. With none, there's no check."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var check: some View {
        Section {
            HStack {
                Button("Test connection") {
                    Task { await model.testConnection() }
                }
                Button("Test from Mail") {
                    Task { await model.testFromMail() }
                }
            }
            .disabled(model.checking)
            if let result = model.check {
                CheckResultView(result: result)
            }
        } header: {
            Text("Check")
        } footer: {
            Text(
                "Test from Mail opens a new message window in Mail, where the extension runs the same check itself. "
                    + "Close the window afterwards."
            )
            .foregroundStyle(.secondary)
        }
    }
}

/// A field for a decimal number that keeps the decimals typed, with "." or "," (`DecimalText`). Text that isn't a
/// number leaves the value as it was, and the field shows the value again when it loses focus.
private struct DecimalField: View {
    let label: String
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .focused($focused)
            .onAppear { text = DecimalText.text(of: value) }
            .onChange(of: text) { _, text in
                if let typed = DecimalText.value(of: text) {
                    value = typed
                }
            }
            .onChange(of: focused) { _, focused in
                if !focused {
                    text = DecimalText.text(of: value)
                }
            }
            .onChange(of: value) { _, value in
                if !focused {
                    text = DecimalText.text(of: value)
                }
            }
            .onSubmit { text = DecimalText.text(of: value) }
    }
}

private struct AccountSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section("Nextcloud account") {
            if let account = model.account {
                LabeledContent("Server", value: account.server.absoluteString)
                LabeledContent("Logged in as", value: account.loginName)
                Button("Log out") {
                    Task { await model.logOut() }
                }
            } else {
                TextField("Server", text: $model.settings.server, prompt: Text("https://cloud.example.com"))
                    .disabled(model.login != .idle)
                switch model.login {
                case .idle:
                    Button("Log in in the browser") {
                        model.logIn()
                    }
                case .waiting(let url):
                    Text(
                        "Log in on the Nextcloud page that opened in your browser, and grant access. "
                            + "NextcloudAppleMail never sees your password."
                    )
                    HStack {
                        Button("Open the page again") {
                            NSWorkspace.shared.open(url)
                        }
                        Button("Cancel") {
                            model.cancelLogin()
                        }
                    }
                }
            }
            if let problem = model.accountProblem {
                Text(problem).foregroundStyle(.red)
            }
        }
    }
}

private struct CheckResultView: View {
    let result: AppModel.CheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let report = result.report {
                Label(result.title, systemImage: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(report.passed ? .green : .red)
                Text(report.text).textSelection(.enabled)
            } else {
                Text(result.title)
            }
        }
    }
}

/// How to set up Mail, and the limits worth knowing (FR5, FR10, R12, R13, R15, R21).
private struct SetupHelp: View {
    private let steps = [
        "Log in above. If macOS asks whether NextcloudAppleMail may find devices on your local network, allow it. "
            + "The extension in Mail uses the same permission to reach a server on your local network.",
        "In Mail, open Settings > Extensions, turn on NextcloudAppleMail, and choose it in the message security "
            + "popup. Then quit and reopen Mail.",
        "In each message window, turn on Sign, the badge button at the right of the subject line. Files become "
            + "links only while it's on, and it stays on for later messages.",
        "If Mail asks about Mail Drop for a large email, choose Try Sending in Email and tick “Don't ask again for "
            + "this account”. If you choose Use Mail Drop, the email goes out with Mail Drop's link, and the files "
            + "uploaded for it are deleted from Nextcloud.",
    ]

    private let notes = [
        "While a slow upload runs, NextcloudAppleMail shows a notification, and another when it's done. Allow "
            + "its notifications when macOS asks, or in System Settings > Notifications.",
        "Send Later uploads the files when you schedule the email, so the links' expiry starts then.",
        "Your Sent mailbox keeps the links, not the files, so once a link expires the file is only on Nextcloud.",
        "While NextcloudAppleMail is chosen for message security, Mail can't sign or encrypt with certificates.",
        "With a link for each file, an admin can raise Nextcloud's limit of 20 new links in 10 minutes in "
            + "config.php: 'ratelimit_overwrite' => ['files_sharing.shareapi.createshare' => ['user' => "
            + "['limit' => 200, 'period' => 600]]].",
    ]

    var body: some View {
        Section("Setting up Mail") {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
            }
            ForEach(notes, id: \.self) { note in
                Text(note).foregroundStyle(.secondary)
            }
        }
    }
}
