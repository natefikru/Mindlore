import Foundation
import Testing
@testable import Mindlore

struct RecordingLiveActivityTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func noRecordingMeansNoActivity() {
        #expect(RecordingLiveActivity.content(isRecording: false, recorderState: .recording, elapsed: 30, now: now) == nil)
    }

    // A running clock counts from the banked time, so it picks up where a pause left it.
    @Test func aRunningRecordingCountsOnFromWhatItHasBanked() throws {
        let state = try #require(RecordingLiveActivity.content(isRecording: true, recorderState: .recording, elapsed: 90, now: now))
        #expect(!state.isPaused)
        #expect(state.timerStart == now.addingTimeInterval(-90))
    }

    @Test func aPausedOrInterruptedRecordingHoldsStill() throws {
        for recorderState in [AudioRecorder.State.paused, .interrupted] {
            let state = try #require(RecordingLiveActivity.content(isRecording: true, recorderState: recorderState, elapsed: 42, now: now))
            #expect(state.isPaused)
            #expect(state.elapsed == 42)
        }
    }
}

struct IntentURLTests {
    @Test func theRecordControlsLinkIsARecordRequest() throws {
        #expect(IntentAction(url: try #require(URL(string: "mindlore://record"))) == .record)
        #expect(IntentAction(url: try #require(URL(string: "mindlore://new"))) == .newEntry)
        #expect(IntentAction(url: try #require(URL(string: "mindlore://ask"))) == .ask(nil))
    }

    @Test func anythingElseIsNoAction() throws {
        #expect(IntentAction(url: try #require(URL(string: "mindlore://delete-everything"))) == nil)
        #expect(IntentAction(url: try #require(URL(string: "https://record"))) == nil)
    }
}

struct QuickActionTests {
    @Test func eachQuickActionIsTheRequestItsTitleSays() {
        #expect(QuickAction.action(forType: "com.natefikru.mindlore.record") == .record)
        #expect(QuickAction.action(forType: "com.natefikru.mindlore.new") == .newEntry)
        #expect(QuickAction.action(forType: "com.natefikru.mindlore.ask") == .ask(nil))
        #expect(QuickAction.action(forType: "com.example.other") == nil)
    }

    // Every type the Info.plist declares is one the app understands.
    @Test func everyDeclaredQuickActionIsHandled() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        #expect(items.count == 3)
        for item in items {
            let type = try #require(item["UIApplicationShortcutItemType"] as? String)
            #expect(QuickAction.action(forType: type) != nil, "\(type)")
        }
    }
}

