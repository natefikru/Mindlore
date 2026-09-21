import Foundation

// Server-sent events, the shape Chat Completions streams in. Fed whatever arrives, however it is
// split: bytes are held until a line is whole, so a multi-byte character landing across two
// network reads is decoded once rather than twice as replacement characters.
nonisolated struct SSEParser: Sendable {
    enum Event: Equatable, Sendable {
        case payload(String)
        // The server said it is done. Anything after it is not part of the answer.
        case done
    }

    private var bytes: [UInt8] = []
    private var dataLines: [String] = []

    init() {}

    mutating func consume(_ data: Data) -> [Event] {
        bytes.append(contentsOf: data)
        var events: [Event] = []
        while let newline = bytes.firstIndex(of: 0x0A) {
            let line = String(decoding: bytes[..<newline], as: UTF8.self)
            bytes.removeFirst(newline + 1)
            if let event = consume(line: line) { events.append(event) }
        }
        return events
    }

    // A stream that ends without its last blank line still has a frame in hand.
    mutating func finish() -> [Event] {
        var events: [Event] = []
        if !bytes.isEmpty {
            let line = String(decoding: bytes, as: UTF8.self)
            bytes.removeAll()
            if let event = consume(line: line) { events.append(event) }
        }
        if let event = flush() { events.append(event) }
        return events
    }

    private mutating func consume(line raw: String) -> Event? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        // A blank line ends the frame; a line starting with a colon is a comment, which is what
        // a keep-alive is.
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        guard line[..<colon] == "data" else { return nil }
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        dataLines.append(value)
        return nil
    }

    private mutating func flush() -> Event? {
        defer { dataLines = [] }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        return payload == "[DONE]" ? .done : .payload(payload)
    }
}
