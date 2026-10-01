import Foundation
import Testing
@testable import BoschCameraTV

struct RetryPolicyTests {
    let policy = RetryPolicy(initialDelay: 1, multiplier: 2, maximumDelay: 30, maximumAttempts: 8, jitterFraction: 0.2)

    @Test func growsExponentiallyUpToMaximumDelay() {
        let delays = (1...8).map { policy.delay(forAttempt: $0, randomUnit: 0) }

        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30])
    }

    @Test func appliesJitterSymmetrically() {
        #expect(abs(policy.delay(forAttempt: 3, randomUnit: 1) - 4.8) < 0.000_001)
        #expect(abs(policy.delay(forAttempt: 3, randomUnit: -1) - 3.2) < 0.000_001)
    }

    @Test func neverExceedsMaximumDelay() {
        #expect(policy.delay(forAttempt: 50, randomUnit: 1) == 30)
    }

    @Test func randomDelaysStayWithinJitterRange() {
        for _ in 0..<200 {
            let delay = policy.delay(forAttempt: 2)
            #expect(delay >= 1.6 && delay <= 2.4)
        }
    }

    @Test func limitsNumberOfAttempts() {
        #expect(policy.canRetry(afterAttempts: 0))
        #expect(policy.canRetry(afterAttempts: 7))
        #expect(!policy.canRetry(afterAttempts: 8))
    }
}
