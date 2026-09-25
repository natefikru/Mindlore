import SwiftUI

// The moment between closing the journal and opening it again the other way. Usually well under a
// second; it exists so nothing of the old journal is on screen while its container goes.
struct SyncSwitchingView: View {
    let turningOn: Bool

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(turningOn ? "Turning on iCloud sync…" : "Turning off iCloud sync…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .accessibilityIdentifier("syncSwitching")
    }
}

#Preview {
    SyncSwitchingView(turningOn: false)
}
