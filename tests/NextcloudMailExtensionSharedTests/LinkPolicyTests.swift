import Foundation
import Testing

@testable import NextcloudMailExtensionShared

struct LinkPolicyTests {
    @Test func linksEveryFileUnderTheAllRule() throws {
        let files = LinkPolicy(rule: .allAttachments).linkedFiles(
            in: try Fixture.message("t27-second"), signatureContentIDs: [])
        #expect(files.map(\.index) == [0, 1])
    }

    @Test func linksOnlyLargerFilesUnderTheSizeRule() throws {
        let policy = LinkPolicy(rule: .largerThan(bytes: 5000))
        #expect(
            policy.linkedFiles(in: try Fixture.message("t27-second"), signatureContentIDs: []).map(\.filename)
                == ["dummy-10MB.bin"])
        #expect(
            policy.linkedFiles(in: try Fixture.message("t28-second"), signatureContentIDs: []).map(\.filename)
                == ["dummy-10MB.png"])
    }

    @Test func linksAllFilesOrNoneUnderTheTogetherRule() throws {
        let message = try Fixture.message("t27-second")
        let total = message.files.reduce(0) { $0 + $1.decodedSize }
        let over = LinkPolicy(rule: .togetherLargerThan(bytes: total - 1))
        #expect(over.linkedFiles(in: message, signatureContentIDs: []).map(\.index) == [0, 1])
        let atTheLimit = LinkPolicy(rule: .togetherLargerThan(bytes: total))
        #expect(atTheLimit.linkedFiles(in: message, signatureContentIDs: []).isEmpty)
    }

    @Test func countsOnlyFilesThatCanBecomeLinksTowardsTheTotal() throws {
        let message = try Fixture.message("t30-second")
        let signature = try Fixture.signatureContentIDs(for: "t30-second")
        var policy = LinkPolicy(rule: .allAttachments)
        policy.pastedImagesBecomeLinks = false
        let candidates = policy.linkedFiles(in: message, signatureContentIDs: signature)
        let total = candidates.reduce(0) { $0 + $1.decodedSize }
        policy.rule = .togetherLargerThan(bytes: total)
        #expect(policy.linkedFiles(in: message, signatureContentIDs: signature).isEmpty)
        policy.rule = .togetherLargerThan(bytes: total - 1)
        #expect(policy.linkedFiles(in: message, signatureContentIDs: signature).map(\.index) == candidates.map(\.index))
        let known = policy.linkedFiles(in: message, signatureContentIDs: signature) { $0.filename == "dummy-1MB.png" }
        #expect(known.isEmpty, "a signature image found by an earlier call doesn't count")
    }

    @Test func findsSignatureImagesInTheFirstCall() throws {
        #expect(
            LinkPolicy.signatureContentIDs(in: try Fixture.message("t30-first"))
                == ["aef717f0-8f04-44d2-82fc-5268aa0673d5"])
        #expect(LinkPolicy.signatureContentIDs(in: try Fixture.message("t30-second")).isEmpty)
        #expect(LinkPolicy.signatureContentIDs(in: try Fixture.message("t29-first")).isEmpty)
    }

    @Test func neverLinksSignatureImages() throws {
        let signature = try Fixture.signatureContentIDs(for: "t30-second")
        let files = LinkPolicy(rule: .allAttachments).linkedFiles(
            in: try Fixture.message("t30-second"), signatureContentIDs: signature)
        #expect(files.map(\.filename) == ["dummy-1MB.png", "PastedGraphic-1.png"])
    }

    @Test func keepsPastedImagesWhenTheSettingIsOff() throws {
        var policy = LinkPolicy(rule: .allAttachments)
        policy.pastedImagesBecomeLinks = false
        let signature = try Fixture.signatureContentIDs(for: "t30-second")
        let files = policy.linkedFiles(in: try Fixture.message("t30-second"), signatureContentIDs: signature)
        #expect(files.map(\.filename) == ["dummy-1MB.png"])
    }

    @Test(arguments: [
        ("PastedGraphic-1.png", "image/png", true),
        ("PastedGraphic-12.tiff", "image/tiff", true),
        ("PastedGraphic-1.png", "application/pdf", false),
        ("PastedGraphic-.png", "image/png", false),
        ("My PastedGraphic-1.png", "image/png", false),
        ("Screenshot 2026-11-05 at 22.00.04.png", "image/png", false),
    ])
    func tellsPastedImagesByMailsNames(filename: String, contentType: String, pasted: Bool) {
        let part = MimePart(fields: [])
        let file = MessageFile(
            index: 0, filename: filename, contentType: contentType, contentID: nil, decodedSize: 1, part: part)
        #expect(LinkPolicy.isPastedImage(file) == pasted)
    }
}

struct HTMLTests {
    @Test func endsOwnTextBeforeQuotedMessages() throws {
        let html = try #require(try Fixture.message("t34-first").text("html").first)
        let end = HTML.endOfOwnText(in: html)
        #expect(html[..<end].hasSuffix("See attached.<br id=\"lineBreakAtBeginningOfMessage\">"))
    }

    @Test func treatsSharedContentAsOwnText() {
        let html =
            #"<body><div class="Apple-Mail-URLShareWrapperClass" style="position: relative;">"#
            + #"<blockquote type="cite" style="border-left-style: none;">Mine</blockquote></div>"#
            + #"<blockquote type="cite">Theirs</blockquote></body>"#
        let end = HTML.endOfOwnText(in: html)
        #expect(html[end...].hasPrefix(#"<blockquote type="cite">Theirs"#))
    }

    @Test func endsOwnTextBeforeTheBodyEndsWithoutQuotes() {
        let html = "<html><body>Hello</body></html>"
        #expect(html[..<HTML.endOfOwnText(in: html)] == "<html><body>Hello")
    }

    @Test func findsTheWholeSignature() {
        let html = #"<body>Hi<div id="AppleMailSignature"><div>Name</div><img src="cid:a"></div>After</body>"#
        let range = HTML.signatureRange(in: html)
        #expect(
            range.map { String(html[$0]) } == #"<div id="AppleMailSignature"><div>Name</div><img src="cid:a"></div>"#)
    }

    @Test func declaresUTF8() {
        let html = #"<meta http-equiv="content-type" content="text/html; charset=us-ascii"><meta charset="ISO-8859-1">"#
        let utf8 = #"<meta http-equiv="content-type" content="text/html; charset=utf-8"><meta charset="utf-8">"#
        #expect(HTML.declaringUTF8(html) == utf8)
    }

    @Test func escapesMarkup() {
        #expect(HTML.escape(#"<a & "b">"#) == "&lt;a &amp; &quot;b&quot;&gt;")
    }
}
