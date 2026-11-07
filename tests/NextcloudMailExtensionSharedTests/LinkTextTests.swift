import Foundation
import Testing

@testable import NextcloudMailExtensionShared

struct LinkTextTests {
    func file(expiry: ExpiryDate? = Links.expiry) throws -> LinkedFile {
        LinkedFile(
            filename: "Report <1>.pdf",
            size: 1_500_000,
            viewURL: try #require(URL(string: "https://cloud.example.test/s/abc")),
            downloadURL: try #require(URL(string: "https://cloud.example.test/s/abc/download")),
            expiry: expiry
        )
    }

    @Test func writesViewAndDownloadLinks() throws {
        let text = LinkText()
        #expect(
            text.plain(try file()) == """
                Report <1>.pdf (1.5 MB, link expires 12 Dec 2026)
                View: https://cloud.example.test/s/abc
                Download: https://cloud.example.test/s/abc/download
                """)
        #expect(
            text.html(try file()) == """
                <div><a href="https://cloud.example.test/s/abc">Report &lt;1&gt;.pdf</a> \
                (1.5 MB, link expires 12 Dec 2026): \
                <a href="https://cloud.example.test/s/abc">View</a> · \
                <a href="https://cloud.example.test/s/abc/download">Download</a></div>
                """)
    }

    @Test func callsTheViewLinkOverviewWhenItOpensTheFolder() throws {
        var text = LinkText()
        text.viewLabel = LinkText.folderViewLabel
        #expect(text.plain(try file()).contains("\nOverview: https://cloud.example.test/s/abc\n"))
        #expect(text.html(try file()).contains(#"<a href="https://cloud.example.test/s/abc">Overview</a> · "#))
    }

    @Test func writesDownloadLinksOnly() throws {
        let text = LinkText(style: .downloadOnly)
        #expect(
            text.plain(try file(expiry: nil)) == "Report <1>.pdf (1.5 MB): https://cloud.example.test/s/abc/download")
        #expect(
            text.html(try file(expiry: nil))
                == #"<div><a href="https://cloud.example.test/s/abc/download">Report &lt;1&gt;.pdf</a> (1.5 MB)</div>"#)
    }

    @Test func writesTheFolderLinksAndThePasswordNotice() throws {
        let text = LinkText()
        #expect(text.plain(folder: nil, passwordNotice: false) == nil)
        #expect(text.html(folder: nil, passwordNotice: false) == nil)
        #expect(
            text.plain(folder: try Links.folder(), passwordNotice: true) == """
                View all files in email: https://cloud.example.test/s/folder
                Download all files in email: https://cloud.example.test/s/folder/download
                \(LinkText.passwordNotice)
                """)
        #expect(text.html(folder: nil, passwordNotice: true) == "<div>\(LinkText.passwordNotice)</div>")
    }

    @Test(arguments: [
        (0, "0 bytes"), (1, "1 byte"), (999, "999 bytes"), (1000, "1 KB"), (1500, "1.5 KB"), (999_499, "999 KB"),
        (999_500, "1 MB"), (9_940_000, "9.9 MB"), (9_960_000, "10 MB"), (12_000_000, "12 MB"),
        (1_234_567_890, "1.2 GB"),
    ])
    func writesSizesInDecimalUnits(bytes: Int, text: String) {
        #expect(LinkText.size(bytes) == text)
    }

    @Test func readsTheServersExpiryDates() {
        #expect(ExpiryDate(server: "2026-12-12 00:00:00")?.text == "12 Dec 2026")
        #expect(ExpiryDate(server: "2027-01-05")?.text == "5 Jan 2027")
        #expect(ExpiryDate(server: "2026-13-01") == nil)
        #expect(ExpiryDate(server: "") == nil)
    }
}
