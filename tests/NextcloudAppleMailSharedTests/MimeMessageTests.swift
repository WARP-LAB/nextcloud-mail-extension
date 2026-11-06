import Foundation
import Testing

@testable import NextcloudAppleMailShared

struct MimeMessageTests {
    @Test(arguments: Fixture.names)
    func writesAnUnchangedMessageByteForByte(name: String) throws {
        let data = try Fixture.data(name)
        #expect(MimeMessage(data).data() == data)
    }

    @Test func findsTheFilesInDocumentOrder() throws {
        let files = try Fixture.message("t28-second").files
        #expect(files.map(\.filename) == ["dummy-1MB.pdf", "dummy-10MB.png"])
        #expect(files.map(\.index) == [0, 1])
        #expect(files.map(\.contentType) == ["application/pdf", "image/png"])
        #expect(files.map(\.decodedSize) == [1000, 10001])
    }

    @Test func readsContentIDsWithoutAngleBrackets() throws {
        let files = try Fixture.message("t29-first").files
        #expect(
            files.map(\.contentID) == ["47CFDB31-33DA-4F6C-BEAC-B589A5879309", "3AA32E53-5109-4A4E-A983-2BA3F8B728DE"])
    }

    @Test(arguments: Fixture.names)
    func measuresFilesWithoutDecodingThem(name: String) throws {
        for file in try Fixture.message(name).files {
            #expect(file.decodedSize == file.data.count, "\(name): \(file.filename)")
        }
    }

    @Test func readsRFC2231FileNames() {
        let header = "attachment; filename*=utf-8''P%C4%81rskats%202026.pdf"
        #expect(MimePart.parameter("filename", in: header) == "Pārskats 2026.pdf")
    }

    @Test func readsQuotedParametersWithSemicolons() {
        let header = #"attachment; filename="a; b \"c\".pdf"; size=12"#
        #expect(MimePart.parameter("filename", in: header) == #"a; b "c".pdf"#)
        #expect(MimePart.parameter("size", in: header) == "12")
    }

    @Test func keepsCRLFMessagesInCRLF() throws {
        let unix = try Fixture.data("t29-second")
        let text = try #require(String(bytes: unix, encoding: .utf8))
        let crlf = Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let message = MimeMessage(crlf)
        #expect(message.eol == "\r\n")
        #expect(message.data() == crlf)
        #expect(message.text("plain") == MimeMessage(unix).text("plain"))
    }
}

struct TransferEncodingTests {
    @Test(arguments: 0...9)
    func countsBase64Bytes(length: Int) {
        let data = Data((0..<length * 37).map { UInt8($0 % 251) })
        let body = TransferEncoding.encodeBase64(data, eol: "\n")
        #expect(TransferEncoding.decodedSize(body, encoding: "base64") == data.count)
        #expect(TransferEncoding.decode(body, encoding: "base64") == data)
    }

    @Test(arguments: [
        "plain ascii",
        "Pārskats ar garumzīmēm, 2 + 2 = 4",
        "trailing space \nand tab\t\nend",
        String(repeating: "long line with ā ", count: 20),
        "=3D is not decoded twice",
    ])
    func roundTripsQuotedPrintable(text: String) throws {
        let encoded = TransferEncoding.encodeQuotedPrintable(text, eol: "\n")
        let lines = try #require(String(bytes: encoded, encoding: .ascii)).components(separatedBy: "\n")
        #expect(lines.allSatisfy { $0.count <= 76 })
        #expect(lines.allSatisfy { !$0.hasSuffix(" ") && !$0.hasSuffix("\t") })
        #expect(TransferEncoding.decodeQuotedPrintable(encoded) == Data(text.utf8))
    }

    @Test func readsTextInLatin1AndWindows1252() {
        #expect(TransferEncoding.text(Data([0x63, 0x61, 0x66, 0xE9]), charset: "iso-8859-1") == "café")
        #expect(TransferEncoding.text(Data([0x80]), charset: "windows-1252") == "€")
        #expect(TransferEncoding.text(Data([0x41]), charset: "koi8-r") == nil)
    }
}
