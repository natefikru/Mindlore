import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The recording in progress on the Lock Screen and in the Dynamic Island: that it is recording, for
// how long, and a Stop button. Time and state only, never a word of what was said.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack(spacing: 14) {
                RecordingDot(isPaused: context.state.isPaused)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isPaused ? "Paused" : "Recording")
                        .font(.headline)
                    Text("Mindlore")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ElapsedText(state: context.state)
                    .font(.title2.monospacedDigit().weight(.semibold))
                StopButton()
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.isPaused ? "Paused" : "Recording")
                    } icon: {
                        RecordingDot(isPaused: context.state.isPaused)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StopButton()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } compactLeading: {
                RecordingDot(isPaused: context.state.isPaused)
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                RecordingDot(isPaused: context.state.isPaused)
            }
            .keylineTint(.ember)
        }
    }
}

private struct RecordingDot: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle.fill")
            .foregroundStyle(Color.ember)
            .accessibilityHidden(true)
    }
}

// A running clock counts on its own, with no updates from the app; a paused one holds still.
private struct ElapsedText: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(Duration.seconds(state.elapsed).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct StopButton: View {
    var body: some View {
        Button(intent: StopRecordingIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color.ember, in: Circle())
        .foregroundStyle(.black)
        .accessibilityLabel("Stop recording")
    }
}
