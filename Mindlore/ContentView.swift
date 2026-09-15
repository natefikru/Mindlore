//
//  ContentView.swift
//  Mindlore
//
//  Created by Nate Fikru on 9/15/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Text(entry.text.isEmpty ? "Empty entry" : entry.text)
                    .lineLimit(1)
            }
            .navigationTitle("Mindlore")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Entry.self, inMemory: true)
        .environment(SettingsStore(store: UserDefaults(suiteName: "preview")!))
}
