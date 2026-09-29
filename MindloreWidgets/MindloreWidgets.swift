import SwiftUI
import WidgetKit

// Mindlore outside its own screens: a Record control for Control Center, the Lock Screen, and the
// Action button, and the Live Activity a recording shows while it runs. Nothing here reads the
// journal, so the extension needs no App Group. `Color.ember` is generated from its own catalog's
// Ember set, a copy of the app's accent.
@main
struct MindloreWidgets: WidgetBundle {
    var body: some Widget {
        RecordControl()
        RecordingLiveActivity()
    }
}

