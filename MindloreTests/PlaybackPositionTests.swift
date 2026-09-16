import Foundation
import Testing
@testable import Mindlore

struct PlaybackPositionTests {
    @Test func skipsMoveTenSecondsInsideTheRecording() {
        #expect(PlaybackPosition.skipped(from: 12, by: 10, duration: 60) == 22)
        #expect(PlaybackPosition.skipped(from: 22, by: -10, duration: 60) == 12)
    }

    // Near either end, a skip stops at the edge rather than wrapping or going negative.
    @Test func skipsStopAtTheEnds() {
        #expect(PlaybackPosition.skipped(from: 4, by: -10, duration: 60) == 0)
        #expect(PlaybackPosition.skipped(from: 55, by: 10, duration: 60) == 60)
        #expect(PlaybackPosition.skipped(from: 3, by: 10, duration: 8) == 8)
    }

    @Test func aRecordingWithNoKnownLengthStaysAtTheStart() {
        #expect(PlaybackPosition.skipped(from: 0, by: 10, duration: 0) == 0)
        #expect(PlaybackPosition.skipped(from: 0, by: 10, duration: -1) == 0)
    }

    // Seconds are cut, not rounded, so the label never runs ahead of what has played.
    @Test func labelsReadAsMinutesAndSeconds() {
        #expect(PlaybackPosition.label(0) == "0:00")
        #expect(PlaybackPosition.label(9.9) == "0:09")
        #expect(PlaybackPosition.label(75) == "1:15")
        #expect(PlaybackPosition.label(-3) == "0:00")
        #expect(PlaybackPosition.label(.nan) == "0:00")
    }
}
