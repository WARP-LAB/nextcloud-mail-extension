import Foundation

/// The names an email's folder and files get on Nextcloud (FR2, docs/ARCHITECTURE.md, "Using Nextcloud").
enum NextcloudNames {
    /// `<yyyy-MM-dd> <subject>`, such as `2026-11-05 Quarterly report`, with the subject cut to 60 characters. If the
    /// folder exists, `NextcloudClient.createUniqueFolder` adds a number.
    static func folder(date: Date, subject: String?, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var name = clean(subject ?? "", trimmingDots: true)
        if name.count > 60 {
            name = clean(String(name.prefix(60)), trimmingDots: true)
        }
        return "\(day) \(name.isEmpty ? "Email" : name)"
    }

    /// The email's file names, with a number added to a name that's already used, ignoring case: a second `a.pdf`
    /// becomes `a (2).pdf`.
    static func uniqueFiles(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { original in
            var name = clean(original, trimmingDots: false)
            if name.isEmpty || name == "." || name == ".." {
                name = "attachment"
            }
            var candidate = name
            var number = 2
            while used.contains(candidate.lowercased()) {
                candidate = numbered(name, number)
                number += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    /// A name that a folder share's download of one file can fetch. Nextcloud 35 redirects that download to the
    /// file's WebDAV path without encoding the name, so `#`, `%` and `?` there cut or break it, and they become `_`
    /// (docs/NEXTCLOUD.md, "Share links").
    static func folderShareName(_ name: String) -> String {
        String(name.map { "#%?".contains($0) ? "_" : $0 })
    }

    /// Replaces `/`, `\` and control characters, which can't be in a name, and trims spaces from the ends, and dots
    /// too for folders.
    static func clean(_ name: String, trimmingDots: Bool) -> String {
        let replaced = String(
            name.unicodeScalars.map { scalar -> Character in
                if scalar == "/" || scalar == "\\" {
                    return "-"
                }
                return CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
            })
        var trimmed = CharacterSet.whitespacesAndNewlines
        if trimmingDots {
            trimmed.insert(".")
        }
        return replaced.trimmingCharacters(in: trimmed)
    }

    /// `report (2).pdf` from `report.pdf`, keeping the extension.
    static func numbered(_ name: String, _ number: Int) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return "\(name) (\(number))"
        }
        return "\(name[..<dot]) (\(number))\(name[dot...])"
    }
}
