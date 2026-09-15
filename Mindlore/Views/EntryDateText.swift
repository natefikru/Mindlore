import SwiftUI

// An entry's journal date: date and time by default, or only the day the user picked.
struct EntryDateText: View {
    let entry: Entry
    var style: Style = .row

    enum Style {
        case row
        case title
    }

    var body: some View {
        Text(formatted)
    }

    private var formatted: String {
        switch (style, entry.entryDateIsDayOnly) {
        case (.row, false):
            entry.entryDate.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        case (.row, true):
            entry.entryDate.formatted(.dateTime.weekday(.abbreviated).month().day().year())
        case (.title, _):
            entry.entryDate.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}

struct EntryAddedText: View {
    let entry: Entry

    var body: some View {
        if entry.entryDateDiffersFromCreation() {
            Text("Added \(entry.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))")
        }
    }
}
