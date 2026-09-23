import SwiftUI

// An entry's journal date: date and time by default, or only the day the user picked.
struct EntryDateText: View {
    let entry: Entry
    var style: Style = .row

    enum Style: Equatable {
        // The group header already says roughly when this was, so the row says only what the
        // header leaves out. That is where most of a row's height went.
        case row(JournalGroup?)
        case title

        static let row = Style.row(nil)
    }

    var body: some View {
        Text(formatted)
    }

    private var formatted: String {
        switch style {
        case .title:
            return entry.entryDate.formatted(.dateTime.month(.abbreviated).day().year())
        case .row(let group):
            return Self.rowText(entry.entryDate, dayOnly: entry.entryDateIsDayOnly, group: group)
        }
    }

    static func rowText(_ date: Date, dayOnly: Bool, group: JournalGroup?) -> String {
        switch group {
        case .recent, .yesterday:
            // A day-only entry has no meaningful time to show, so it says nothing more.
            return dayOnly ? "" : date.formatted(.dateTime.hour().minute())
        case .thisWeek:
            return dayOnly
                ? date.formatted(.dateTime.weekday(.abbreviated))
                : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .month:
            return date.formatted(.dateTime.weekday(.abbreviated).day())
        case .year, .later:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case nil:
            return dayOnly
                ? date.formatted(.dateTime.weekday(.abbreviated).month().day().year())
                : date.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        }
    }
}
