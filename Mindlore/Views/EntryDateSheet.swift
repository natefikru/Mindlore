import SwiftUI

// Picks the day an entry belongs to. Only the day matters; the time is fixed at noon and hidden.
struct EntryDateSheet: View {
    let entry: Entry
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date

    init(entry: Entry, onChange: @escaping () -> Void) {
        self.entry = entry
        self.onChange = onChange
        _day = State(initialValue: entry.entryDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Entry date", selection: $day, in: ...Date.distantFuture, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("entryDatePicker")
                } footer: {
                    Text("Added \(entry.createdAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))")
                }
                if entry.entryDateIsDayOnly {
                    Section {
                        Button("Use original date") {
                            let previous = entry.entryDate
                            entry.useOriginalEntryDate()
                            onChange()
                            Self.recordChange(entry: entry, from: previous, reason: "reset")
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Entry Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Keeping the same day leaves the original date and time untouched.
                        if !EntryDates.isSameDay(day, entry.entryDate) {
                            let previous = entry.entryDate
                            entry.setEntryDay(day)
                            onChange()
                            Self.recordChange(entry: entry, from: previous, reason: "manual")
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("entryDateDoneButton")
                }
            }
        }
    }

    static func recordChange(entry: Entry, from previous: Date, reason: String) {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: previous), to: Calendar.current.startOfDay(for: entry.entryDate)).day ?? 0
        DiagnosticsLog.shared.record("entryDate.changed", ["id": .id(entry.id), "reason": .string(reason), "daysMoved": .int(days)])
    }
}
