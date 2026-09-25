import Foundation

// What the welcome screen says about iCloud. A new install and a second device look the same at
// launch (no entries yet), so the line follows the sync status and the entries iCloud has brought
// in while the screen is up: a second device should say its journal is arriving, never look empty.
nonisolated struct WelcomeSyncLine: Equatable, Sendable {
    let symbol: String
    let title: String
    let detail: String
    let busy: Bool

    static func line(status: SyncStatus, entries: Int) -> WelcomeSyncLine? {
        if entries > 0, status.reachesICloud || status == .checking {
            let count = entries == 1 ? "1 entry has" : "\(entries) entries have"
            return WelcomeSyncLine(
                symbol: "icloud.and.arrow.down",
                title: "Your journal is here",
                detail: "\(count) come in from iCloud" + (status == .syncing ? ", and more are on the way." : "."),
                busy: status == .syncing
            )
        }
        switch status {
        case .notSynced, .off:
            return nil
        case .checking, .syncing:
            return WelcomeSyncLine(
                symbol: "icloud",
                title: "Checking iCloud",
                detail: "If you've used Mindlore on another device, your journal comes in here.",
                busy: true
            )
        case .upToDate, .paused:
            return WelcomeSyncLine(
                symbol: "icloud",
                title: "Kept in your iCloud",
                detail: "Your journal is saved on this iPhone and in your private iCloud, so it's on your other devices too. Never on a server of ours.",
                busy: false
            )
        case .deviceOnly, .storeFailed:
            return WelcomeSyncLine(
                symbol: "iphone",
                title: "On this iPhone",
                detail: "Sign in to iCloud in the Settings app to keep your journal on your other devices too.",
                busy: false
            )
        }
    }
}
