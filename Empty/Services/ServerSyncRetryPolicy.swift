//
//  ServerSyncRetryPolicy.swift
//  Empty
//

import Foundation

nonisolated enum ServerSyncRetryPolicy {
    static func delayAfterFailure(_ failureCount: Int) -> TimeInterval {
        switch min(max(failureCount, 1), 6) {
        case 1:
            30
        case 2:
            60
        case 3:
            120
        case 4:
            300
        case 5:
            600
        default:
            900
        }
    }

    static func nextRetryDate(afterFailure failureCount: Int, now: Date = Date()) -> Date {
        now.addingTimeInterval(delayAfterFailure(failureCount))
    }
}
