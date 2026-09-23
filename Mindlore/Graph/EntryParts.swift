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
            let placed = sections.enumerated()
                .compactMap { index, section in section.offset.map { (index, min(max(0, $0), length)) } }
                .sorted { $0.1 < $1.1 }
            spans = placed.enumerated().map { position, item in
                let end = position + 1 < placed.count ? placed[position + 1].1 : length
                return (item.0, item.1, end)
            }
        }

        // Nil means the whole entry: it has fewer than two parts, or the name couldn't be placed
        // in any of them. A nil name keeps its old behaviour and connects to everything in the
        // entry, so a part the model missed never costs the map an edge it used to have.
        func parts(surfaces: [String], isTag: Bool) -> Set<Int>? {
            guard sections.count > 1 else { return nil }
            let names = Set(surfaces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            guard !names.isEmpty else { return nil }
            var found: Set<Int> = []
            for (index, section) in sections.enumerated() {
                let listed = isTag ? section.tags : section.names
                if listed.contains(where: { names.contains($0.lowercased()) }) {
                    found.insert(index)
                }
            }
            // Tags are labels, not words the entry wrote, so only the model's lists place them.
            if !isTag, let text, !spans.isEmpty {
                for name in names {
                    for range in NameMatching.ranges(of: name, in: text) {
                        let at = text.distance(from: text.startIndex, to: range.lowerBound)
                        if let span = spans.first(where: { at >= $0.start && at < $0.end }) {
                            found.insert(span.part)
                        }
                    }
                }
            }
            return found.isEmpty ? nil : found
        }
    }
}
