import Foundation

/// Decoding and encoding of MIME bodies: base64, quoted-printable and text charsets.
enum TransferEncoding {
    /// Decodes a body in the given `Content-Transfer-Encoding`. Unknown encodings are returned as they are.
    static func decode(_ body: Data, encoding: String) -> Data {
        switch encoding {
        case "base64":
            return Data(base64Encoded: body, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body
        }
    }

    /// The decoded size of a body, without decoding base64 in full.
    static func decodedSize(_ body: Data, encoding: String) -> Int {
        guard encoding == "base64" else {
            return decode(body, encoding: encoding).count
        }
        var characters = 0
        var padding = 0
        for byte in body {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"):
                characters += 1
            case UInt8(ascii: "="):
                characters += 1
                padding += 1
            default:
                continue
            }
        }
        return characters / 4 * 3 - padding
    }

    static func decodeQuotedPrintable(_ body: Data) -> Data {
        let bytes = [UInt8](body)
        var output = Data(capacity: bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "=") else {
                output.append(byte)
                index += 1
                continue
            }
            if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                index += 2
            } else if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A {
                index += 3
            } else if index + 2 < bytes.count, let high = hexValue(bytes[index + 1]),
                let low = hexValue(bytes[index + 2])
            {
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(byte)
                index += 1
            }
        }
        return output
    }

    /// Encodes text as quoted-printable UTF-8, with lines ending in `eol` and soft breaks keeping lines to 76.
    static func encodeQuotedPrintable(_ text: String, eol: String) -> Data {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output = ""
        for (number, line) in lines.enumerated() {
            let bytes = [UInt8](line.utf8)
            var current = ""
            for (position, byte) in bytes.enumerated() {
                let isLast = position == bytes.count - 1
                let encoded: String
                if byte == UInt8(ascii: "=") || byte > 126 || (byte < 32 && byte != 9)
                    || (isLast && (byte == 32 || byte == 9))
                {
                    encoded = String(format: "=%02X", byte)
                } else {
                    encoded = String(UnicodeScalar(byte))
                }
                if current.count + encoded.count > 75 {
                    output += current + "=" + eol
                    current = ""
                }
                current += encoded
            }
            output += current
            if number < lines.count - 1 {
                output += eol
            }
        }
        return Data(output.utf8)
    }

    /// Encodes data as base64, in lines of 76 characters ending in `eol`.
    static func encodeBase64(_ data: Data, eol: String) -> Data {
        let encoded = data.base64EncodedString()
        var lines: [Substring] = []
        var start = encoded.startIndex
        while start < encoded.endIndex {
            let end = encoded.index(start, offsetBy: 76, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(encoded[start..<end])
            start = end
        }
        return Data(lines.joined(separator: eol).utf8)
    }

    /// Decodes text in a MIME charset, or returns nil for a charset this code doesn't handle.
    static func text(_ data: Data, charset: String?) -> String? {
        switch (charset ?? "us-ascii").lowercased() {
        case "utf-8", "utf8":
            return String(bytes: data, encoding: .utf8)
        case "us-ascii", "ascii":
            return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1)
        case "iso-8859-1", "latin1", "iso-8859-15":
            return String(bytes: data, encoding: .isoLatin1)
        case "windows-1252", "cp1252":
            return String(bytes: data, encoding: .windowsCP1252)
        default:
            return nil
        }
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return byte - UInt8(ascii: "a") + 10
        default:
            return nil
        }
    }
}
