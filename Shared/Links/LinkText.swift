import Foundation

/// A file that has been uploaded and shared, as the email shows it.
struct LinkedFile: Equatable {
    var filename: String
    /// The decoded size in bytes.
    var size: Int
    var viewURL: URL
    var downloadURL: URL
    /// The expiry date the server returned, or nil for links that don't expire.
    var expiry: ExpiryDate?
}

/// The links to all of an email's files, its folder on Nextcloud (FR9).
struct FolderLinks: Equatable {
    var viewURL: URL
    var downloadURL: URL
}

/// A link's expiry date, as the server returns it: a day, in the server's time zone (docs/NEXTCLOUD.md).
struct ExpiryDate: Equatable, Codable {
    var year: Int
    var month: Int
    var day: Int

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Reads the server's `YYYY-MM-DD HH:MM:SS` or `YYYY-MM-DD`.
    init?(server value: String) {
        let numbers = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3, (1...12).contains(numbers[1]), (1...31).contains(numbers[2]) else {
            return nil
        }
        (year, month, day) = (numbers[0], numbers[1], numbers[2])
    }

    /// Such as "12 Dec 2026".
    var text: String {
        "\(day) \(Self.months[month - 1]) \(year)"
    }
}

/// How each file's links read in the email (FR8), and the links to all files (FR9).
struct LinkText {
    enum Style: String, Codable, CaseIterable {
        /// A link to the file's page in Nextcloud, and a download link. The default.
        case viewAndDownload
        /// Only a download link.
        case downloadOnly
    }

    static let passwordNotice = "The links need a password, which the sender will give you separately."

    var style: Style = .viewAndDownload

    func plain(_ file: LinkedFile) -> String {
        switch style {
        case .viewAndDownload:
            return "\(file.filename) (\(details(file)))\nView: \(file.viewURL.absoluteString)\n"
                + "Download: \(file.downloadURL.absoluteString)"
        case .downloadOnly:
            return "\(file.filename) (\(details(file))): \(file.downloadURL.absoluteString)"
        }
    }

    func html(_ file: LinkedFile) -> String {
        let name = HTML.escape(file.filename)
        let view = HTML.escape(file.viewURL.absoluteString)
        let download = HTML.escape(file.downloadURL.absoluteString)
        switch style {
        case .viewAndDownload:
            return "<div><a href=\"\(view)\">\(name)</a> (\(HTML.escape(details(file)))): "
                + "<a href=\"\(view)\">View</a> · <a href=\"\(download)\">Download</a></div>"
        case .downloadOnly:
            return "<div><a href=\"\(download)\">\(name)</a> (\(HTML.escape(details(file))))</div>"
        }
    }

    /// The links to all files and the password notice, or nil if there's neither.
    func plain(folder: FolderLinks?, passwordNotice: Bool) -> String? {
        var lines: [String] = []
        if let folder {
            lines.append("View all files in email: \(folder.viewURL.absoluteString)")
            lines.append("Download all files in email: \(folder.downloadURL.absoluteString)")
        }
        if passwordNotice {
            lines.append(Self.passwordNotice)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func html(folder: FolderLinks?, passwordNotice: Bool) -> String? {
        var lines: [String] = []
        if let folder {
            let view = HTML.escape(folder.viewURL.absoluteString)
            let download = HTML.escape(folder.downloadURL.absoluteString)
            lines.append(
                "<div><a href=\"\(view)\">View all files in email</a> · "
                    + "<a href=\"\(download)\">Download all files in email</a></div>"
            )
        }
        if passwordNotice {
            lines.append("<div>\(Self.passwordNotice)</div>")
        }
        return lines.isEmpty ? nil : lines.joined()
    }

    /// Such as "12 MB, link expires 12 Dec 2026", or just the size for links that don't expire.
    private func details(_ file: LinkedFile) -> String {
        guard let expiry = file.expiry else {
            return Self.size(file.size)
        }
        return "\(Self.size(file.size)), link expires \(expiry.text)"
    }

    /// A size in decimal units, as Finder shows it: "512 bytes", "1.5 MB", "12 MB".
    static func size(_ bytes: Int) -> String {
        guard bytes >= 1000 else {
            return bytes == 1 ? "1 byte" : "\(bytes) bytes"
        }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1000
        var unit = 0
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded = value < 9.95 ? (value * 10).rounded() / 10 : value.rounded()
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(number) \(units[unit])"
    }
}
