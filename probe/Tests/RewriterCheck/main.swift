import Foundation

// Command-line wrapper so check_rewriter.py can exercise the rewriter without Mail.
//   rewriter-check rewrite <input.eml> <output.eml> [limit in decoded bytes]
//   rewriter-check directive <subject>

let arguments = CommandLine.arguments

func printJSON(_ object: Any) throws {
    let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: json, as: UTF8.self))
}

switch arguments.dropFirst().first {
case "rewrite":
    let message = MimeMessage(try Data(contentsOf: URL(fileURLWithPath: arguments[2])))
    let outcome = message.rewritten(note: "ff call=2", removingOver: arguments.count > 4 ? Int(arguments[4]) : nil)
    try outcome.data.write(to: URL(fileURLWithPath: arguments[3]))
    try printJSON([
        "stripped": outcome.stripped.map(\.filename),
        "notedPlain": outcome.notedPlain,
        "notedHTML": outcome.notedHTML,
        "usesCRLF": message.usesCRLF,
        "structure": message.structure,
    ])
case "directive":
    guard let directive = ProbeDirective(subject: arguments[2]) else {
        try printJSON(["marked": false])
        break
    }
    try printJSON([
        "marked": true,
        "text": directive.text,
        "action": String(describing: directive.action),
        "delay": directive.delaySeconds,
        "noStatus": directive.reportsCannotEncode,
        "blocksSend": directive.blocksSend,
        "removalLimit": directive.removalLimitBytes ?? -1,
    ])
default:
    print("usage: rewriter-check rewrite <in> <out> | directive <subject>")
    exit(2)
}
