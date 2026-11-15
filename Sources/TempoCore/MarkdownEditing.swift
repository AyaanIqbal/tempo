import Foundation

public struct MarkdownNewline {
    public let insertion: String
    public let removeBeforeCursor: Int
}
public enum MarkdownEditing {
    /// Continue jot notes, nested bullets, numbered lists, and unchecked task lists.
    public static func newline(after line: String) -> MarkdownNewline {
        let source = line as NSString
        let regex = try! NSRegularExpression(pattern: #"^([\t ]*)([-*+]|\d+[.)]) +(\[[ xX]\] +)?(.*)$"#)
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return MarkdownNewline(insertion: "\n", removeBeforeCursor: 0) }
        let indent = source.substring(with: match.range(at: 1))
        let marker = source.substring(with: match.range(at: 2))
        let content = source.substring(with: match.range(at: 4))
        if content.trimmingCharacters(in: .whitespaces).isEmpty { return MarkdownNewline(insertion: "", removeBeforeCursor: source.length) }
        var nextMarker = marker
        if let last = marker.last, let number = Int(marker.dropLast()) { nextMarker = "\(number + 1)\(last)" }
        let checkbox = match.range(at: 3).location == NSNotFound ? "" : "[ ] "
        return MarkdownNewline(insertion: "\n" + indent + nextMarker + " " + checkbox, removeBeforeCursor: 0)
    }
}
