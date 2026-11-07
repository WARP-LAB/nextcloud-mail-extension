import AppKit
import SwiftUI

/// The email's password in the toolbar popover (FR7, T16): the field, icon buttons to show, generate and copy it, and
/// the server's reason when its password policy refuses the password. The buttons have tooltips, as Apple's Human
/// Interface Guidelines ask for buttons without text.
struct PasswordSection: View {
    let context: UUID
    @Binding var password: String
    @State private var shown = false
    @State private var server: NextcloudClient?
    @State private var problem: String?
    @State private var generating = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Group {
                    if shown {
                        TextField("Password for this email's links", text: $password)
                    } else {
                        SecureField("Password for this email's links", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                // Saved at every change, because the popover can close without the field ending its editing.
                .onChange(of: password) { _, value in
                    MessageValues.passwords.set(value, context: context)
                }
                iconButton(shown ? "eye.slash" : "eye", shown ? "Hide the password" : "Show the password") {
                    shown.toggle()
                }
                iconButton("dice", "Generate a password that Nextcloud accepts", action: generate)
                    .disabled(generating)
                iconButton(
                    copied ? "checkmark" : "doc.on.doc", "Copy the password to give to the recipients", action: copy
                )
                .disabled(password.isEmpty)
            }
            Text("Empty means no password. If you set one, consider a safe way to pass it to the recipients.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { server = await PasswordAdvice.sharedServer() }
        // Runs again, and cancels the last run, whenever the password changes or the server is ready.
        .task(id: [password, server == nil ? "" : "ready"]) { await check() }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    /// Asks the server's password policy once the user has stopped typing for a moment.
    private func check() async {
        guard !password.isEmpty else {
            problem = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else {
            return
        }
        let answer = await PasswordAdvice.problem(with: password, server: server)
        if !Task.isCancelled {
            problem = answer
        }
    }

    private func generate() {
        generating = true
        Task {
            password = await PasswordAdvice.generated(by: server)
            shown = true
            generating = false
        }
    }

    /// Copies the password, marked as concealed, so that clipboard managers following nspasteboard.org's convention
    /// don't keep it.
    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
