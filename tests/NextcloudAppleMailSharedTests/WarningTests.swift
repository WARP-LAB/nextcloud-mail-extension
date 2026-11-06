import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The send check's warnings (FR5, FR6) and the text they look at.
struct SendWarningTests {
    func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = Settings()
        change(&settings)
        return settings
    }

    func warning(
        _ message: MimeMessage, signOn: Bool, linkedEarlier: Int = 0, _ change: (inout Settings) -> Void = { _ in }
    ) -> String? {
        SendWarnings.warning(for: message, signOn: signOn, settings: settings(change), linkedEarlier: linkedEarlier)
    }

    static func message(subject: String = "Hello", html: String, files: String = "") -> MimeMessage {
        MimeMessage(
            Data(
                """
                Subject: \(subject)
                Content-Type: multipart/related; boundary="r"

                --r
                Content-Type: text/html; charset=utf-8

                <html><body>\(html)</body></html>
                \(files)--r--

                """.utf8))
    }

    // MARK: - FR5: Sign is off

    @Test func warnsWithSignOffAndNamesTheFiles() throws {
        let text = try #require(warning(try Fixture.message("t15-first"), signOn: false))
        #expect(text.contains("“dummy-1MB.bin”"))
        #expect(text.contains("turn on Sign"))
        #expect(text.contains("Send Anyway sends the files attached"))
    }

    @Test func doesntWarnWithSignOnTheSettingOffOrNoFileForALink() throws {
        let message = try Fixture.message("t15-first")
        #expect(warning(message, signOn: true) == nil)
        #expect(warning(message, signOn: false) { $0.warnIfSignOff = false } == nil)
        let small = warning(message, signOn: false) {
            $0.onlyLargeFiles = true
            $0.sizeLimitMegabytes = 0.005
        }
        #expect(small == nil, "the files stay attached under the size rule")
        #expect(warning(try Fixture.message("t34-first"), signOn: false) == nil)
    }

    // MARK: - FR6: text mentions an attachment

    @Test func warnsWhenTheTextMentionsAnAttachmentThatIsntThere() throws {
        let message = try Fixture.message("t34-first")
        for signOn in [true, false] {
            #expect(
                warning(message, signOn: signOn) { $0.warningPhrases = ["nothing", "ATTACH"] }
                    == "Your message mentions “ATTACH” but has no attachment.")
        }
        #expect(warning(message, signOn: true) == nil, "no phrases, no check")
    }

    @Test func looksOnlyAtTheUsersOwnText() throws {
        let reply = try Fixture.message("t34-first")
        #expect(warning(reply, signOn: true) { $0.warningPhrases = ["wrote"] } == nil, "the quote isn't checked")
        let subject = Self.message(subject: "See attached", html: "<div>Hello</div>")
        #expect(warning(subject, signOn: true) { $0.warningPhrases = ["attached"] } == nil)
        let signature = Self.message(html: #"<div>Hello</div><div id="AppleMailSignature">See attached</div>"#)
        #expect(warning(signature, signOn: true) { $0.warningPhrases = ["attached"] } == nil)
        let shared = Self.message(
            html: #"<div class="Apple-Mail-URLShareWrapperClass"><blockquote type="cite" style="border-left-style: "#
                + #"none;">Please see the attached&nbsp;file</blockquote></div>"#)
        #expect(warning(shared, signOn: true) { $0.warningPhrases = ["attached file"] } != nil)
    }

    @Test func countsEveryFileButTheSignaturesImages() throws {
        let phrases: (inout Settings) -> Void = { $0.warningPhrases = ["text"] }
        #expect(warning(try Fixture.message("t15-first"), signOn: true, phrases) == nil)
        #expect(
            warning(try Fixture.message("t34-first"), signOn: true, linkedEarlier: 1) { $0.warningPhrases = ["see"] }
                == nil, "files the first call turned into links count")
        let image = """
            --r
            Content-Type: image/png; name="logo.png"
            Content-Disposition: inline; filename="logo.png"
            Content-ID: <logo@example.test>
            Content-Transfer-Encoding: base64

            iVBORw0KGgo=

            """
        let onlySignature = Self.message(
            html: #"<div>See attached</div><div id="AppleMailSignature"><img src="cid:logo@example.test"></div>"#,
            files: image)
        #expect(warning(onlySignature, signOn: true) { $0.warningPhrases = ["attached"] } != nil)
        let pasted = Self.message(html: #"<div>See attached</div><img src="cid:logo@example.test">"#, files: image)
        #expect(warning(pasted, signOn: true) { $0.warningPhrases = ["attached"] } == nil)
    }
}

struct TextCheckTests {
    @Test func takesTheOwnTextOfMailsHTML() {
        let html = """
            <html><head><style>p { color: red; }</style></head><body><div>Caf&eacute; &amp; tea&nbsp;&#8211; \
            &#x41;</div><div><br></div><div class="AppleOriginalContents"><div>Quoted <div>nested</div></div></div>\
            <blockquote type="cite"><div>Also <blockquote type="cite">quoted</blockquote></div></blockquote>\
            <div>After</div></body></html>
            """
        #expect(TextCheck.ownText(html: html) == "Caf&eacute; & tea – A After")
    }

    @Test func takesTheOwnTextOfPlainText() {
        #expect(TextCheck.ownText(plain: "Hello\n> quoted\nthere\n-- \nSignature") == "Hello there")
    }

    @Test(arguments: [
        ("attach", "Please see attached.", true), ("SEE  ATTACHED", "please see attached", true),
        ("pielikum", "Skatīt pielikumā", true), ("attachment", "attach", false), ("", "anything", false),
    ])
    func findsPhrasesInsideWordsIgnoringCase(phrase: String, text: String, found: Bool) {
        #expect((TextCheck.firstPhrase([phrase], in: text) != nil) == found)
    }
}
