import AppIntents
import SwiftUI
import WidgetKit

// One press from anywhere to a recording: Control Center, the Lock Screen, or the Action button. A
// button, not a toggle, since a recording isn't a state to flip from outside the app (HIG,
// Controls). It opens the app and leaves the same request Siri's Start Recording does.
struct RecordControl: ControlWidget {
    static let kind = "com.natefikru.mindlore.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RecordFromControlIntent()) {
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Record")
        .description("Start a voice entry in Mindlore.")
    }
}

