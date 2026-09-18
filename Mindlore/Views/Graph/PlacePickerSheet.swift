import SwiftUI

// Which real place this is. Search only, seeded with the entity's name, with no region bias and
// no location permission: the app never asks where the user is.
struct PlacePickerSheet: View {
    @Environment(\.placeDirectory) private var places
    @Environment(\.dismiss) private var dismiss

    let entityName: String
    let onPick: (PlaceMatch) -> Void

    @State private var query = ""
    @State private var matches: [PlaceMatch] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if searching {
                        ProgressView()
                    } else if matches.isEmpty {
                        Text(searched ? "Nothing on the map matches \"\(query)\"." : "Search for where this is.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matches) { match in
                            Button {
                                onPick(match)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.name).foregroundStyle(.primary)
                                    if let locality = match.locality {
                                        Text(locality).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("placeMatch")
                        }
                    }
                } footer: {
                    // Nothing is stored and nothing is logged, but the search does leave the
                    // phone, so say so rather than implying otherwise.
                    Text("Searching sends this name to Apple Maps. Mindlore saves only where the place is, never its name or address.")
                }
            }
            .searchable(text: $query, prompt: "Search places")
                .navigationTitle("Find this place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { query = entityName }
        .task(id: query) {
            // A beat so a fast typist doesn't send a request on every keystroke. The only search
            // path: seeding the query on open re-keys this task rather than searching twice, and
            // each search leaves the phone.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matches = []
            searched = false
            return
        }
        searching = true
        matches = await places.search(trimmed)
        searching = false
        searched = true
    }
}
