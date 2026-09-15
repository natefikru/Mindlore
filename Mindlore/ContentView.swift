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

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Text(entry.text.isEmpty ? "Empty entry" : entry.text)
                    .lineLimit(1)
            }
            .navigationTitle("Mindlore")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Entry.self, inMemory: true)
}
