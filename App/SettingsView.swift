import SwiftUI

/// The host app's window: the account, every setting, the connection checks and the setup help.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
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
        .frame(minWidth: 560, idealWidth: 640, minHeight: 600, idealHeight: 860)
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
                TextField("Larger than, in MB", value: $model.settings.sizeLimitMegabytes, format: .number)
            }
            Toggle("Pasted images become links", isOn: $model.settings.pastedImagesBecomeLinks)
        } header: {
            Text("Which files become links")
        } footer: {
            Text("Images in your signature always stay in the email.").foregroundStyle(.secondary)
        }
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

/// FR4: in a week, a month or a year, after a custom period of years, months, days and hours, or never.
private struct ExpiryPicker: View {
    enum Choice: Hashable {
        case week, month, year, custom, never
    }

    @Binding var expiry: LinkExpiry
    /// Whether the custom choice is shown, which a custom period equal to a preset, such as 7 days, needs.
    @State private var custom = false

    var body: some View {
        Picker("Links expire", selection: choice) {
            Text("In a week").tag(Choice.week)
            Text("In a month").tag(Choice.month)
            Text("In a year").tag(Choice.year)
            Text("After a custom period").tag(Choice.custom)
            Text("Never").tag(Choice.never)
        }
        .onAppear {
            custom = Self.preset(expiry) == nil
        }
        if choice.wrappedValue == .custom {
            LabeledContent("After") {
                HStack(spacing: 12) {
                    amount("year", "years", \.years)
                    amount("month", "months", \.months)
                    amount("day", "days", \.days)
                    amount("hour", "hours", \.hours)
                }
            }
            Text(
                "Counted from sending. Nextcloud ends a link at the end of a day, so the link expires at the end of "
                    + "the day the period reaches, and hours only matter when they cross midnight."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func amount(_ unit: String, _ units: String, _ part: WritableKeyPath<LinkExpiry.Period, Int>)
        -> some View
    {
        HStack(spacing: 4) {
            TextField(units, value: binding(part), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Stepper(units, value: binding(part), in: 0...9999)
                .labelsHidden()
            Text(period[keyPath: part] == 1 ? unit : units)
        }
    }

    private var choice: Binding<Choice> {
        Binding {
            custom ? .custom : Self.preset(expiry) ?? .custom
        } set: { choice in
            custom = choice == .custom
            switch choice {
            case .week:
                expiry = .week
            case .month:
                expiry = .month
            case .year:
                expiry = .year
            case .never:
                expiry = .never
            case .custom:
                if expiry == .never {
                    expiry = .days(14)
                }
            }
        }
    }

    /// The custom period, or two weeks to start from when links don't expire.
    private var period: LinkExpiry.Period {
        if case .after(let period) = expiry {
            return period
        }
        return LinkExpiry.Period(days: 14)
    }

    private func binding(_ part: WritableKeyPath<LinkExpiry.Period, Int>) -> Binding<Int> {
        Binding {
            period[keyPath: part]
        } set: { value in
            var changed = period
            changed[keyPath: part] = min(max(value, 0), 9999)
            expiry = .after(changed)
        }
    }

    private static func preset(_ expiry: LinkExpiry) -> Choice? {
        if expiry == .week {
            return .week
        }
        if expiry == .month {
            return .month
        }
        if expiry == .year {
            return .year
        }
        return expiry == .never ? .never : nil
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
