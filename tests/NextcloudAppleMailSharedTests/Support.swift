import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The anonymised messages from the probe in Fixtures/, made by tests/make-fixtures.py. Files in them are shrunk to
/// 1/1000 of their size, so "dummy-10MB.bin" has 10,000 bytes.
enum Fixture {
    static let names = [
        "t15-first", "t15-second", "t20-first", "t20-second", "t27-second", "t28-second",
        "t29-first", "t29-second", "t30-first", "t30-second", "t34-first", "t34-second",
    ]

    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "eml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func message(_ name: String) throws -> MimeMessage {
        MimeMessage(try data(name))
    }

    /// The signature images' Content-IDs, which only the first send call marks.
    static func signatureContentIDs(for name: String) throws -> Set<String> {
        let first = name.replacingOccurrences(of: "-second", with: "-first")
        guard names.contains(first) else {
            return []
        }
        return LinkPolicy.signatureContentIDs(in: try message(first))
    }
}

enum Links {
    static let expiry = ExpiryDate(server: "2026-12-12 00:00:00")

    static func link(_ file: MessageFile, filename: String? = nil) throws -> LinkedFile {
        LinkedFile(
            filename: filename ?? file.filename,
            size: file.decodedSize,
            viewURL: try #require(URL(string: "https://cloud.example.test/s/file\(file.index)")),
            downloadURL: try #require(URL(string: "https://cloud.example.test/s/file\(file.index)/download")),
            expiry: expiry
        )
    }

    static func links(_ files: [MessageFile]) throws -> [Int: LinkedFile] {
        Dictionary(uniqueKeysWithValues: try files.map { ($0.index, try link($0)) })
    }

    static func folder() throws -> FolderLinks {
        FolderLinks(
            viewURL: try #require(URL(string: "https://cloud.example.test/s/folder")),
            downloadURL: try #require(URL(string: "https://cloud.example.test/s/folder/download"))
        )
    }
}

extension MimeMessage {
    /// The text of all text parts of one subtype, in document order.
    func text(_ subtype: String) -> [String] {
        textParts(subtype).compactMap(\.text)
    }
}

extension String {
    /// The position of a substring, for checking the order of things in a message.
    func offset(of text: String) -> Int? {
        range(of: text).map { distance(from: startIndex, to: $0.lowerBound) }
    }
}
