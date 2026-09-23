import SwiftUI

// Offered at the top of the journal when entries the safety copy holds are gone from the store
// after iCloud changed underneath it. Restore puts back their words and dates; Not now hides it
// until the next launch, and the iCloud section in Settings keeps a way back to it meanwhile.
struct RestoreBanner: View {
    @Environment(JournalRecovery.self) private var recovery
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(RestoreCopy.title(count: recovery.missing.count), systemImage: "arrow.counterclockwise.icloud")
                .font(.headline)
            Text(RestoreCopy.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Restore") { recovery.restoreAll(in: modelContext) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ember)
                    .accessibilityIdentifier("restoreMissingEntries")
                Button("Not now") { recovery.bannerDismissed = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("restoreNotNow")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restoreBanner")
    }
}

nonisolated enum RestoreCopy {
    static func title(count: Int) -> String {
        count == 1 ? "1 entry is missing from this iPhone" : "\(count) entries are missing from this iPhone"
    }

    static func button(count: Int) -> String {
        count == 1 ? "Restore 1 missing entry" : "Restore \(count) missing entries"
    }

    static let detail = "iCloud changed and took them off this iPhone. Mindlore kept a copy of their words and dates, so they can come back. Recordings, page photos, and insights aren't in the copy."
}
