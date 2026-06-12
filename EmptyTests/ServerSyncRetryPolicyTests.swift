//
//  ServerSyncRetryPolicyTests.swift
//  EmptyTests
//

import Foundation
import Testing
@testable import Empty

struct ServerSyncRetryPolicyTests {
    @Test func retryDelayBacksOffByFailureCount() {
        #expect(ServerSyncRetryPolicy.delayAfterFailure(1) == 30)
        #expect(ServerSyncRetryPolicy.delayAfterFailure(2) == 60)
        #expect(ServerSyncRetryPolicy.delayAfterFailure(3) == 120)
        #expect(ServerSyncRetryPolicy.delayAfterFailure(4) == 300)
        #expect(ServerSyncRetryPolicy.delayAfterFailure(5) == 600)
        #expect(ServerSyncRetryPolicy.delayAfterFailure(8) == 900)
    }

    @Test func nextRetryDateAddsComputedDelay() {
        let now = Date(timeIntervalSince1970: 1_000)
        let retryAt = ServerSyncRetryPolicy.nextRetryDate(afterFailure: 3, now: now)
        #expect(retryAt == now.addingTimeInterval(120))
    }
}
