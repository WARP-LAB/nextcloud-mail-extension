import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The rewriter on each message structure in docs/MAIL.md.
struct LinkRewriterTests {
    let text = LinkText()

    /// Rewrites a fixture with the given files linked, and parses the result.
    func rewrite(
        _ name: String, folder: FolderLinks? = nil, passwordNotice: Bool = false,
        linking select: (MimeMessage) throws -> [MessageFile] = { $0.files }
    ) throws -> (links: [Int: LinkedFile], output: MimeMessage) {
        let input = try Fixture.message(name)
        let links = try Links.links(try select(input))
        let output = LinkRewriter().rewrite(input, links: links, folder: folder, passwordNotice: passwordNotice)
        return (links, MimeMessage(output))
    }

    func plain(_ links: [Int: LinkedFile], _ index: Int) throws -> String {
        text.plain(try #require(links[index]))
    }

    func html(_ links: [Int: LinkedFile], _ index: Int) throws -> String {
        text.html(try #require(links[index]))
    }

    // MARK: - Plain messages: text, file, text (t15, t29)

    @Test func replacesFilesInPlainTextWhereTheyWere() throws {
        let (links, output) = try rewrite("t15-second")
        #expect(output.root.contentType == "text/plain")
        #expect(output.root.charset == "utf-8")
        #expect(output.files.isEmpty)
        #expect(
            output.root.text == """
                [probe ff] t15

                text above

                dummy-1MB.bin (1 KB, link expires 12 Dec 2026)
                View: https://cloud.example.test/s/file0
                Download: https://cloud.example.test/s/file0/download

                text in between

                \(try plain(links, 1))

                text below
                """)
    }

    @Test func keepsTheMessageHeadersWhenTheBodyBecomesOnePart() throws {
        let input = try Fixture.message("t15-second")
        let (_, output) = try rewrite("t15-second")
        let headers = ["from", "to", "subject", "date", "message-id", "mime-version"]
        for header in headers {
            #expect(output.root.field(header) == input.root.field(header), "\(header)")
        }
        #expect(output.root.field("content-transfer-encoding") == "quoted-printable")
    }

    @Test func replacesADroppedInPDFAndImage() throws {
        let (links, output) = try rewrite("t29-second")
        #expect(
            output.root.text == """
                [probe ff] t29

                text above the files

                \(try plain(links, 0))

                text between the files

                \(try plain(links, 1))

                text below the files
                """)
    }

    @Test func addsTheFolderLinksAtTheEnd() throws {
        let (links, output) = try rewrite("t15-second", folder: try Links.folder(), passwordNotice: true)
        let ending = try #require(text.plain(folder: try Links.folder(), passwordNotice: true))
        let body = try #require(output.root.text)
        #expect(body.hasSuffix("\(try plain(links, 1))\n\ntext below\n\n\(ending)\n"))
    }

    // MARK: - The size rule: some files stay (t27, t28)

    @Test func keepsSmallFilesByteForByte() throws {
        let input = try Fixture.message("t28-second")
        let (links, output) = try rewrite("t28-second") {
            LinkPolicy(rule: .largerThan(bytes: 5000)).linkedFiles(in: $0, signatureContentIDs: [])
        }
        #expect(links.keys.sorted() == [1])
        #expect(output.root.contentType == "multipart/mixed")
        #expect(output.root.children.map(\.contentType) == ["text/plain", "application/pdf", "text/plain"])
        let pdf = try #require(input.files.first)
        #expect(output.files.map(\.filename) == ["dummy-1MB.pdf"])
        #expect(output.files.first?.part.body == pdf.part.body)
        #expect(output.files.first?.part.fields.map(\.raw) == pdf.part.fields.map(\.raw))
        #expect(output.root.children.first?.body == input.root.children.first?.body)
        #expect(
            output.root.children.last?.text
                == "\n\ntext between the files\n\n\(try plain(links, 1))\n\ntext below the files\n\n")
    }

    @Test func putsALastFilesLinksAfterTheFilesThatStay() throws {
        let (links, output) = try rewrite("t27-second") {
            LinkPolicy(rule: .largerThan(bytes: 5000)).linkedFiles(in: $0, signatureContentIDs: [])
        }
        #expect(output.root.children.map(\.contentType) == ["text/plain", "application/macbinary", "text/plain"])
        #expect(output.root.children.last?.text == (try plain(links, 1)))
    }

    // MARK: - Rich messages: alternative with related (t30, and the first call's structure)

    @Test func replacesImagesInBothAlternativesAndKeepsTheSignature() throws {
        let signature = try Fixture.signatureContentIDs(for: "t30-second")
        let (links, output) = try rewrite("t30-second") {
            LinkPolicy(rule: .allAttachments).linkedFiles(in: $0, signatureContentIDs: signature)
        }
        #expect(links.keys.sorted() == [0, 1])
        #expect(output.root.contentType == "multipart/alternative")
        #expect(output.root.children.map(\.contentType) == ["text/plain", "multipart/related"])
        #expect(output.files.map(\.filename) == ["Screenshot 2026-11-05 at 22.00.04.png"])
        #expect(
            output.text("plain") == [
                "[probe log] t30\n\n\(try plain(links, 0))\n\n\(try plain(links, 1))\n\n"
                    + "Any attachments are confidential.\n\n\u{FFFC} \n\n"
            ])
        let body = try #require(output.text("html").first)
        #expect(!body.contains("cid:7E6EEE94") && !body.contains("cid:2892C84E"))
        #expect(body.contains(#"src="cid:AEF717F0-8F04-44D2-82FC-5268AA0673D5""#))
        #expect(body.contains("[probe log] t30<div><br></div><div>\(try html(links, 0))</div>"))
        #expect(body.contains(try html(links, 1)))
        #expect(!body.contains("us-ascii"))
    }

    @Test func leavesPastedImagesInPlaceWhenTheSettingIsOff() throws {
        var policy = LinkPolicy(rule: .allAttachments)
        policy.pastedImagesBecomeLinks = false
        let signature = try Fixture.signatureContentIDs(for: "t30-second")
        let (links, output) = try rewrite("t30-second") {
            policy.linkedFiles(in: $0, signatureContentIDs: signature)
        }
        #expect(output.files.map(\.filename) == ["PastedGraphic-1.png", "Screenshot 2026-11-05 at 22.00.04.png"])
        #expect(
            output.text("plain").first?.hasPrefix("[probe log] t30\n\n\(try plain(links, 0))\n\n\u{FFFC}\n\n") == true)
        #expect(output.text("html").first?.contains(#"src="cid:2892C84E-A67F-48B5-9D61-0B9BF958A534""#) == true)
    }

    @Test func replacesPlaceholdersInTheFirstCall() throws {
        let (links, output) = try rewrite("t29-first")
        #expect(output.root.children.map(\.contentType) == ["text/plain", "text/html"])
        #expect(output.files.isEmpty)
        let body = try #require(output.text("html").first)
        #expect(!body.contains("cid:"))
        let above = try #require(body.offset(of: "text above the files"))
        let pdf = try #require(body.offset(of: try html(links, 0)))
        let between = try #require(body.offset(of: "text between the files"))
        let png = try #require(body.offset(of: try html(links, 1)))
        let below = try #require(body.offset(of: "text below the files"))
        #expect(above < pdf && pdf < between && between < png && png < below)
    }

    @Test func listsFilesInTheEmptyPlainTextOfTheFirstCall() throws {
        let (links, output) = try rewrite("t15-first")
        #expect(output.text("plain") == ["\(try plain(links, 0))\n\n\(try plain(links, 1))\n"])
    }

    // MARK: - Forwards: plain with U+FFFC, mixed HTML (t20)

    @Test func replacesAForwardedFileAndPutsTheFolderLinksAboveTheQuote() throws {
        let folder = try Links.folder()
        let (links, output) = try rewrite("t20-second", folder: folder)
        #expect(output.root.children.map(\.contentType) == ["text/plain", "text/html"])
        #expect(output.files.isEmpty)

        let plainText = try #require(output.text("plain").first)
        let plainFolder = try #require(text.plain(folder: folder, passwordNotice: false))
        #expect(plainText.hasPrefix("\(plainFolder)\n\n> Begin forwarded message:\n"))
        #expect(plainText.hasSuffix("> [probe log] t1\n\(try plain(links, 0))\n"))

        let body = try #require(output.text("html").first)
        let htmlFolder = try #require(text.html(folder: folder, passwordNotice: false))
        let folderAt = try #require(body.offset(of: htmlFolder))
        let quoteAt = try #require(body.offset(of: #"<blockquote type="cite">"#))
        let fileAt = try #require(body.offset(of: try html(links, 0)))
        #expect(folderAt < quoteAt && quoteAt < fileAt)
        #expect(body.components(separatedBy: "<html").count == 2)
        #expect(!body.contains("us-ascii"))
    }

    // MARK: - Replies without files (t34)

    @Test(arguments: ["t34-first", "t34-second"])
    func leavesMessagesWithoutFilesAlone(name: String) throws {
        let data = try Fixture.data(name)
        let message = MimeMessage(data)
        #expect(message.files.isEmpty)
        #expect(LinkRewriter().rewrite(message, links: [:], folder: nil, passwordNotice: false) == data)
    }

    @Test func putsThePasswordNoticeAboveTheQuoteInAReply() throws {
        let (_, output) = try rewrite("t34-second", passwordNotice: true)
        #expect(
            output.root.text == "See attached.\n\n\(LinkText.passwordNotice)\n\n> On 5 Nov 2026, at 16:37, "
                + "Test Sender <sender@example.test> wrote:\n> \n> [probe log] t1\n> <dummy-1MB.bin>\n\n")
    }

    // MARK: - Every structure

    @Test(arguments: Fixture.names)
    func showsEveryLinkInEveryAlternative(name: String) throws {
        let signature = try Fixture.signatureContentIDs(for: name)
        let input = try Fixture.message(name)
        let (links, output) = try rewrite(name, folder: try Links.folder()) {
            LinkPolicy(rule: .allAttachments).linkedFiles(in: $0, signatureContentIDs: signature)
        }
        #expect(output.files.count == input.files.count - links.count)
        let alternatives = output.root.contentType == "multipart/alternative" ? output.root.children : [output.root]
        for alternative in alternatives {
            let shown = Self.text(of: alternative)
            for link in links.values {
                #expect(shown.contains(link.downloadURL.absoluteString), "\(name): \(alternative.contentType)")
            }
            if !links.isEmpty {
                #expect(
                    shown.contains("https://cloud.example.test/s/folder/download"),
                    "\(name): \(alternative.contentType)")
            }
        }
    }

    @Test(arguments: Fixture.names)
    func keepsAccentsInFileNames(name: String) throws {
        let input = try Fixture.message(name)
        let named = try Dictionary(
            uniqueKeysWithValues: input.files.map { ($0.index, try Links.link($0, filename: "Pārskats <ā>.pdf")) }
        )
        let rewritten = MimeMessage(LinkRewriter().rewrite(input, links: named, folder: nil, passwordNotice: false))
        for subtype in ["plain", "html"] {
            for part in rewritten.textParts(subtype) where part.text?.contains("cloud.example.test") == true {
                #expect(part.charset == "utf-8")
                #expect(part.text?.contains(subtype == "plain" ? "Pārskats <ā>.pdf" : "Pārskats &lt;ā&gt;.pdf") == true)
            }
        }
    }

    @Test func turnsAMessageThatIsOnlyAFileIntoText() throws {
        let data = Data(
            """
            Subject: Only a file
            Content-Type: application/pdf; name="a.pdf"
            Content-Disposition: attachment; filename="a.pdf"
            Content-Transfer-Encoding: base64

            JVBERi0xLjQK

            """.utf8)
        let input = MimeMessage(data)
        let links = try Links.links(input.files)
        let output = MimeMessage(LinkRewriter().rewrite(input, links: links, folder: nil, passwordNotice: false))
        #expect(output.root.contentType == "text/plain")
        #expect(output.root.field("subject") == "Only a file")
        #expect(output.root.field("content-disposition") == nil)
        #expect(output.root.text == "\(try plain(links, 0))\n")
    }

    /// All text in a part and its children, as a reader would see it.
    static func text(of part: MimePart) -> String {
        part.isMultipart ? part.children.map { text(of: $0) }.joined() : (part.isText ? part.text ?? "" : "")
    }
}
