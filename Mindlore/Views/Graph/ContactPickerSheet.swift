import SwiftUI

// Picking which contact a person in the journal is. Search only, seeded with the entity's name:
// the app never scans the address book on its own and never matches a name without being asked.
struct ContactPickerSheet: View {
    @Environment(\.contactDirectory) private var contacts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let entityName: String
    let onPick: (ContactMatch) -> Void

    @State private var query = ""
    @State private var access: ContactAccess = .notDetermined
    @State private var matches: [ContactMatch] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .notDetermined:
                    ProgressView()
                case .denied, .restricted:
                    ContentUnavailableView {
                        Label("Contacts access is off", systemImage: "person.crop.circle.badge.xmark")
                    } description: {
                        Text("Mindlore shows a contact's photo next to the people in your journal. \(entityName) works fine without one.")
                    } actions: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Button("Open Settings") { openURL(url) }
                        }
                    }
                    .accessibilityIdentifier("contactAccessOff")
                case .limited, .authorized:
                    list
                }
            }
            .navigationTitle("Link a contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            access = await contacts.access
            if access == .notDetermined { access = await contacts.requestAccess() }
            query = entityName
            await search()
        }
    }

    private var list: some View {
        List {
            if access == .limited {
                Section {
                    Text("You've given Mindlore access to some of your contacts. Only those can be searched.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if searching {
                    ProgressView()
                } else if matches.isEmpty {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "Type a name to search your contacts."
                         : "No contacts match \"\(query)\".")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { match in
                        Button {
                            onPick(match)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ContactThumbnail(data: match.thumbnail)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.name).foregroundStyle(.primary)
                                    if let secondary = match.secondary {
                                        Text(secondary).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("contactMatch")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search contacts")
        .onSubmit(of: .search) { Task { await search() } }
        .task(id: query) {
            // A beat so a fast typist doesn't fetch on every keystroke.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        searching = true
        matches = await contacts.search(query)
        searching = false
    }
}

private struct ContactThumbnail: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(Color(.secondarySystemFill))
                    .overlay(Image(systemName: "person").foregroundStyle(.secondary))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(.circle)
    }
}
