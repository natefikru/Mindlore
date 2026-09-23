import Foundation

// Which of an entry's parts a name belongs to, so the map connects two names only when they were
// written about together (owner, 2026-09-23). Before parts, everything named in one entry was
// joined to everything else in it, because it was all written at the same sitting: a morning at
// work with Dana and an evening call with Maya made Dana and Maya neighbours.
//
// Read at snapshot time, never stored: an entry indexed before parts existed, a name the user
// added by hand, and a rerun that changed the parts all read correctly with nothing to migrate.
// Plain values only, like EntityGraph; GraphServices fetches and hands them in.
nonisolated enum EntryParts {
    struct Context: Sendable {
        let sections: [EntrySection]
        // The text the parts were read from, or nil once the entry has been edited since: the
        // offsets no longer point at the same words, and only the model's own lists are trusted.
        let text: String?
        // Each placed part's span, in characters, as [start, end).
        private let spans: [(part: Int, start: Int, end: Int)]

        init(sections: [EntrySection], text: String?) {
            self.sections = sections
            self.text = text
            guard let text else {
                spans = []
                return
            }
            let length = text.count
            let placed: [(Int, Int)] = sections.enumerated()
                .compactMap { index, section in section.offset.map { (index, min(max(0, $0), length)) } }
                .sorted { $0.1 < $1.1 }
            var built: [(part: Int, start: Int, end: Int)] = placed.enumerated().map { position, item in
                let end = position + 1 < placed.count ? placed[position + 1].1 : length
                return (part: item.0, start: item.1, end: end)
            }
            // The words before the first placed part belong to someone: the opening part when
            // its first words weren't found, otherwise the first placed part itself. Left out,
            // a name in the entry's first sentence would be in no part and lose every edge.
            if let first = built.first, first.start > 0 {
                if sections.first?.offset == nil, first.part != 0 {
                    built.insert((part: 0, start: 0, end: first.start), at: 0)
                } else {
                    built[0].start = 0
                }
            }
            spans = built
        }

        // Nil means the whole entry: it has fewer than two parts, so there is nothing narrower to
        // go on and every name in it connects as it always did. An empty set means the entry has
        // parts and this name is in none of them, and it connects to nothing from this entry
        // (owner, 2026-09-23: the map's problem was clutter). It stays on the map all the same:
        // a node shows for its mentions, not its edges, and other entries still link it.
        func parts(surfaces: [String], isTag: Bool) -> Set<Int>? {
            guard sections.count > 1 else { return nil }
            let names = Set(surfaces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            guard !names.isEmpty else { return [] }
            var found: Set<Int> = []
            for (index, section) in sections.enumerated() {
                let listed = isTag ? section.tags : section.names
                if listed.contains(where: { names.contains($0.lowercased()) }) {
                    found.insert(index)
                }
            }
            // Tags are labels, not words the entry wrote, so only the model's lists place them.
            // Every form of the name goes in one pattern, with NameMatching's word boundaries,
            // so a long entry is scanned once per link rather than once per alias.
            if !isTag, let text, !spans.isEmpty,
               let regex = try? NSRegularExpression(
                   pattern: "(?<![\\p{L}\\p{N}])(?:" + names.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")(?![\\p{L}\\p{N}])",
                   options: [.caseInsensitive]
               ) {
                let starts = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .compactMap { Range($0.range, in: text)?.lowerBound }
                for start in starts {
                    let at = text.distance(from: text.startIndex, to: start)
                    if let span = spans.first(where: { at >= $0.start && at < $0.end }) {
                        found.insert(span.part)
                    }
                }
            }
            return found
        }
    }
}
