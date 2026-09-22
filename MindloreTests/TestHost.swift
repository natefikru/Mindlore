import Foundation
@testable import Mindlore

// Where the tests are running. scripts/ci/test.sh sets TEST_RUNNER_MINDLORE_CI=1 on GitHub Actions,
// which reaches the test process as MINDLORE_CI.
//
// Only for what CI genuinely cannot measure. The on-device model reports itself available inside a
// runner's simulator, but a quality measurement taken on a small virtual machine is not a reading
// of Apple's model on a phone: the first hosted run filed seven of twelve creative pieces wrong
// where a Mac files two, and generation failed outright on a real entry. Those tests keep running
// on every Mac with Apple Intelligence.
enum TestHost {
    static let isCI = ProcessInfo.processInfo.environment["MINDLORE_CI"] == "1"

    static let canMeasureOnDeviceModel = FoundationModelsAvailability.isAvailable && !isCI
}
