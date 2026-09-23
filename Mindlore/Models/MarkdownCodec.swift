import Foundation

// Markdown at the edges only. `render` writes an entry's text and formatting as Markdown for
// export; `parse` reads the Markdown a cleanup comes back as, so a dictated "first, second, third"
// can land as a numbered list. Nothing inside the app stores or shows the syntax. The subset is
// what EntryFormatting can hold: `#`/`##` headings, `- ` bullets, `1. ` numbers, `- [ ]`/`- [x]`
// checkboxes, `> ` quotes, two spaces per indent level, and `**`, `*`, `~~` inline. Anything else
// stays literal text.
nonisolated enum MarkdownCodec {
    static let indentUnit = "  "

    // MARK: Render

    static func render(text: String, formatting: EntryFormatting) -> String {
        guard !formatting.isEmpty else { return text }
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        var out: [String] = []
        var number = 0
        var lastNumberIndent = -1
        for (index, line) in lines.enumerated() {
            let paragraph = formatting.paragraph(at: index)
            let inline = renderInline(line, spans: formatting.spans, lineStart: offset)
            offset += line.utf16.count + 1
            let indent = String(repeating: indentUnit, count: paragraph.indent)
            if paragraph.block == .number && paragraph.indent == lastNumberIndent {
                number += 1
            } else {
                number = 1
            }
            lastNumberIndent = paragraph.block == .number ? paragraph.indent : -1
            switch paragraph.block {
            case .heading1: out.append("# " + inline)
            case .heading2: out.append("## " + inline)
            case .bullet: out.append(indent + "- " + inline)
            case .number: out.append(indent + "\(number). " + inline)
            case .check: out.append(indent + "- [ ] " + inline)
            case .checked: out.append(indent + "- [x] " + inline)
            case .quote: out.append("> " + inline)
            case nil: out.append(indent + inline)
            }
        }
        return out.joined(separator: "\n")
    }

    private static func renderInline(_ line: String, spans: [EntryFormatting.Span], lineStart: Int) -> String {
        let length = line.utf16.count
        let inside = spans.filter { $0.location >= lineStart && $0.location + $0.length <= lineStart + length }
        guard !inside.isEmpty else { return line }
        let utf16 = Array(line.utf16)
        var out = ""
        var cursor = 0
        for span in inside {
            let start = span.location - lineStart
            let end = start + span.length
            out += String(decoding: utf16[cursor..<start], as: UTF16.self)
            var piece = String(decoding: utf16[start..<end], as: UTF16.self)
            if span.strike { piece = "~~" + piece + "~~" }
            if span.italic { piece = "*" + piece + "*" }
            if span.bold { piece = "**" + piece + "**" }
            out += piece
            cursor = end
        }
        out += String(decoding: utf16[cursor..<utf16.count], as: UTF16.self)
        return out
    }

    // MARK: Parse

    struct Parsed: Equatable, Sendable {
        var text: String
        var formatting: EntryFormatting
    }

    static func parse(_ markdown: String) -> Parsed {
        var lines: [String] = []
        var paragraphs: [EntryFormatting.Paragraph] = []
        var spans: [EntryFormatting.Span] = []
        var offset = 0
        for (index, raw) in markdown.components(separatedBy: "\n").enumerated() {
            let (block, indent, rest) = parseLine(raw)
            let inline = parseInline(rest, lineStart: offset)
            lines.append(inline.text)
            spans.append(contentsOf: inline.spans)
            if block != nil || indent > 0 {
                paragraphs.append(.init(index: index, block: block, indent: indent))
            }
            offset += inline.text.utf16.count + 1
        }
        return Parsed(text: lines.joined(separator: "\n"), formatting: EntryFormatting(paragraphs: paragraphs, spans: spans))
    }

    private static func parseLine(_ line: String) -> (EntryFormatting.Block?, Int, String) {
        var rest = Substring(line)
        var indent = 0
        while rest.hasPrefix(indentUnit) && indent < EntryFormatting.maxIndent {
            rest = rest.dropFirst(indentUnit.count)
            indent += 1
        }
        // A tab counts as one level too, since some writers indent with it.
        while rest.hasPrefix("\t") && indent < EntryFormatting.maxIndent {
            rest = rest.dropFirst()
            indent += 1
        }
        if indent == 0 {
            if rest.hasPrefix("## ") { return (.heading2, 0, String(rest.dropFirst(3))) }
            if rest.hasPrefix("# ") { return (.heading1, 0, String(rest.dropFirst(2))) }
            if rest.hasPrefix("> ") { return (.quote, 0, String(rest.dropFirst(2))) }
        }
        for marker in ["- [ ] ", "* [ ] "] where rest.hasPrefix(marker) {
            return (.check, indent, String(rest.dropFirst(marker.count)))
        }
        for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] "] where rest.hasPrefix(marker) {
            return (.checked, indent, String(rest.dropFirst(marker.count)))
        }
        for marker in ["- ", "* ", "• "] where rest.hasPrefix(marker) {
            return (.bullet, indent, String(rest.dropFirst(marker.count)))
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let after = rest.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") {
                return (.number, indent, String(after.dropFirst(2)))
            }
        }
        return (nil, indent, String(rest))
    }

    // `**bold**`, `*italic*` or `_italic_`, `~~strike~~`, in one pass left to right, nested one
    // inside another in either order. A marker with no closing partner stays literal.
    private static func parseInline(_ line: String, lineStart: Int) -> (text: String, spans: [EntryFormatting.Span]) {
        let chars = Array(line.utf16)
        var out: [UInt16] = []
        var spans: [EntryFormatting.Span] = []
        var bold = false, italic = false, strike = false
        var runStart = 0
        var i = 0

        func closeRun() {
            if out.count > runStart, bold || italic || strike {
                spans.append(.init(location: lineStart + runStart, length: out.count - runStart, bold: bold, italic: italic, strike: strike))
            }
            runStart = out.count
        }

        func hasClosing(_ marker: [UInt16], from: Int) -> Bool {
            var j = from
            while j + marker.count <= chars.count {
                if Array(chars[j..<j + marker.count]) == marker, j > from { return true }
                j += 1
            }
            return false
        }

        let star = UInt16(UnicodeScalar("*").value), tilde = UInt16(UnicodeScalar("~").value), under = UInt16(UnicodeScalar("_").value)
        while i < chars.count {
            let c = chars[i]
            if c == star, i + 1 < chars.count, chars[i + 1] == star, bold || hasClosing([star, star], from: i + 2) {
                closeRun(); bold.toggle(); i += 2; continue
            }
            if c == tilde, i + 1 < chars.count, chars[i + 1] == tilde, strike || hasClosing([tilde, tilde], from: i + 2) {
                closeRun(); strike.toggle(); i += 2; continue
            }
            if c == star || c == under, italic || (i + 1 < chars.count && chars[i + 1] != c && chars[i + 1] != 32 && hasClosing([c], from: i + 1)) {
                // Only a marker at a word boundary: an underscore inside a name is a letter.
                let atBoundary = i == 0 || chars[i - 1] == 32 || italic
                if atBoundary { closeRun(); italic.toggle(); i += 1; continue }
            }
            out.append(c)
            i += 1
        }
        closeRun()
        return (String(decoding: out, as: UTF16.self), spans)
    }
}
