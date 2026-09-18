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

    var body: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView("Nothing found", systemImage: "magnifyingglass")
                    .accessibilityIdentifier("askSearchEmpty")
            }
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
