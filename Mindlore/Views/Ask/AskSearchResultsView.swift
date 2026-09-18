import SwiftData
import SwiftUI

// Search as you type: entries, entities, and tags, grouped. No AI, no network, and it works
// whether or not a provider is set up.
struct AskSearchResultsView: View {
    let results: JournalSearch.Results
    let tagFilter: String?
    let openEntry: (UUID) -> Void
    let openEntity: (UUID) -> Void
    let selectTag: (String) -> Void
    // How tall the rows may get. The "nothing matches" line ignores it and stays one line high,
    // so an empty panel doesn't reserve a screenful for a sentence.
    let maxHeight: CGFloat

    var body: some View {
        if results.isEmpty {
            // One line, not a full-height placeholder: at this point the user is usually writing
            // a question, not hunting for an entry, and a wall of empty state reads as an error.
            Label("Nothing in the journal matches that", systemImage: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .accessibilityIdentifier("askSearchEmpty")
        } else {
            list.frame(maxHeight: maxHeight)
        }
    }

    // An empty list still draws its row separators, which read as stray lines across the screen
    // behind "Nothing found", so the empty state replaces the list rather than sitting over it.
    private var list: some View {
        List {
            if !results.tags.isEmpty {
                Section("Tags") {
                    ForEach(results.tags) { tag in
                        Button { selectTag(tag.tag) } label: {
                            LabeledContent {
                                Text("^[\(tag.count) entry](inflect: true)")
                            } label: {
                                Label(tag.tag, systemImage: "number")
                            }
                        }
                        .accessibilityIdentifier("askSearchTag-\(tag.tag)")
                    }
                }
            }
            if !results.entities.isEmpty {
                Section("People and places") {
                    ForEach(results.entities) { entity in
                        Button { openEntity(entity.id) } label: {
                            LabeledContent {
                                Text("^[\(entity.linkCount) mention](inflect: true)")
                            } label: {
                                Text(entity.name)
                            }
                        }
                        .accessibilityIdentifier("askSearchEntity-\(entity.name)")
                    }
                }
            }
            if !results.entries.isEmpty {
                Section(tagFilter.map { "Entries tagged \($0)" } ?? "Entries") {
                    ForEach(results.entries) { entry in
                        Button { openEntry(entry.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.headline)
                                Text(AskEntryRefs.dateText(entry.date, dayOnly: entry.isDayOnly))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !entry.snippet.isEmpty {
                                    Text(entry.snippet)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                // An entry can rank on a tag, a life area, or a person who appears
                                // nowhere in its words, and the snippet is then just its opening: a
                                // row with no visible reason for being there.
                                if let reason = entry.reason {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .accessibilityIdentifier("askSearchReason")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("askSearchEntry-\(entry.id.uuidString)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("askSearchResults")
    }
}
