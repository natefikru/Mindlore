import AppIntents
import SwiftUI
import WidgetKit

// One press from anywhere to a recording: Control Center, the Lock Screen, or the Action button. A
// button, not a toggle, since a recording isn't a state to flip from outside the app (HIG,
// Controls). It opens the app through the same request Siri's Start Recording leaves.
struct RecordControl: ControlWidget {
    static let kind = "com.natefikru.mindlore.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenRecorderIntent()) {
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Record")
        .description("Start a voice entry in Mindlore.")
    }
}

// Runs in the extension and hands the app a link, so the extension carries none of the app's code.
// The app reads mindlore://record as a Start Recording request (`IntentAction(url:)`).
struct OpenRecorderIntent: AppIntent {
    static let title: LocalizedStringResource = "Record in Mindlore"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "mindlore://record")!))
    }
}
