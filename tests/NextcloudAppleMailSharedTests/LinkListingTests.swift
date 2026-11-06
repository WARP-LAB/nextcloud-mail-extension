import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The rewriter when the email has only the folder's links (FR8, D17).
struct LinkListingTests {
    let text = LinkText()

    /// Rewrites a fixture with only the folder's links, the given files linked.
    func listing(
        _ name: String, linking select: (MimeMessage) throws -> [MessageFile] = { $0.files }
    ) throws -> (links: [Int: LinkedFile], output: MimeMessage) {
        let input = try Fixture.message(name)
        let links = try Links.links(try select(input))
        var rewriter = LinkRewriter()
        rewriter.linksInPlace = false
        let output = rewriter.rewrite(input, links: links, folder: try Links.folder(), passwordNotice: true)
        return (links, MimeMessage(output))
    }

    @Test func listsThePlainMessagesFilesAboveTheFolderLinks() throws {
        let (links, output) = try listing("t15-second")
        #expect(output.root.contentType == "text/plain")
        #expect(output.files.isEmpty)
        let names = try [0, 1].map { text.plainListing(try #require(links[$0])) }.joined(separator: "\n")
        let ending = try #require(text.plain(folder: try Links.folder(), passwordNotice: true))
        #expect(
            output.root.text == """
                [probe ff] t15

                text above

                text in between

                text below

                \(names)

                \(ending)

                """)
        #expect(output.root.text?.contains("/s/file") == false)
    }

    @Test func removesTheRichMessagesImagesAndKeepsTheSignature() throws {
        let signature = try Fixture.signatureContentIDs(for: "t30-second")
        let (links, output) = try listing("t30-second") {
            LinkPolicy(rule: .allAttachments).linkedFiles(in: $0, signatureContentIDs: signature)
        }
        #expect(output.files.map(\.filename) == ["Screenshot 2026-11-05 at 22.00.04.png"])
        let plain = try #require(output.text("plain").first)
        #expect(plain.filter { $0 == "\u{FFFC}" }.count == 1)
        #expect(plain.contains(text.plainListing(try #require(links[1]))))
        let body = try #require(output.text("html").first)
        #expect(!body.contains("cid:7E6EEE94") && !body.contains("cid:2892C84E"))
        #expect(body.contains(#"src="cid:AEF717F0-8F04-44D2-82FC-5268AA0673D5""#))
        #expect(body.contains(text.htmlListing(try #require(links[0]))))
        #expect(body.contains("View all files in email"))
        #expect(!body.contains("/s/file"))
    }

    @Test func listsAForwardedFileAboveTheQuote() throws {
        let (links, output) = try listing("t20-second")
        #expect(output.files.isEmpty)
        let listing = text.plainListing(try #require(links[0]))
        for plain in output.text("plain") {
            #expect(!plain.contains("\u{FFFC}"))
            let listed = try #require(plain.range(of: listing))
            let quote = try #require(plain.range(of: "\n>"))
            #expect(listed.lowerBound < quote.lowerBound)
        }
        for html in output.text("html") {
            #expect(!html.contains("/s/file"))
        }
    }
}
