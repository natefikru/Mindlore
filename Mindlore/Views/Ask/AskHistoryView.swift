import SwiftData
import SwiftUI

// Past conversations, most recently touched first, titled by the question that started them.
struct AskHistoryView: View {
    let open: (AskConversation) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AskService.self) private var ask
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [AskConversation] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(conversations) { conversation in
                    Button { open(conversation) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: conversation.title)
                                .lineLimit(2)
                            Text(conversation.updatedAt.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("askHistoryRow")
                }
                .onDelete { offsets in
                    for conversation in offsets.map({ conversations[$0] }) {
                        ask.delete(conversation, in: modelContext)
                    }
                    refresh()
                }
            }
            .paperBackground()
            .overlay {
                if conversations.isEmpty {
                    ContentUnavailableView("No conversations yet", systemImage: "clock.arrow.circlepath")
                        .accessibilityIdentifier("askHistoryEmpty")
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: refresh)
        .accessibilityIdentifier("askHistorySheet")
    }

    private func refresh() {
        conversations = ask.conversations(in: modelContext)
    }
}
