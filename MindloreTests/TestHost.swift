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

    // The fourteen tests that took 125 of the unit job's 175 seconds on a runner: 300-node
    // simulations, seeding the demo and story journals, timing budgets, the paraphrase rate. They
    // guard seeds and performance rather than behaviour a pull request is likely to break, so CI
    // runs them nightly (ci.yml sets TEST_RUNNER_MINDLORE_SLOW=1 on the schedule). A Mac runs them always.
    static let runsSlowTests = !isCI || ProcessInfo.processInfo.environment["MINDLORE_SLOW"] == "1"
}
