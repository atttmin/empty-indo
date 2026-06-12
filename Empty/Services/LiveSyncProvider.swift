//
//  LiveSyncProvider.swift
//  Empty
//

import Foundation

nonisolated enum LiveSyncProviderKind: String, Codable, CaseIterable, Sendable {
    case cloudKit
    case server
}

nonisolated enum LiveSyncProviderState: String, Codable, CaseIterable, Sendable {
    case active
    case available
    case setupRequired
    case snapshotOnly
    case contractReady
    case unavailable

    var badgeTitle: String {
        switch self {
        case .active: "当前"
        case .available: "可用"
        case .setupRequired: "待配置"
        case .snapshotOnly: "仅快照"
        case .contractReady: "契约就绪"
        case .unavailable: "不可用"
        }
    }
}

nonisolated struct LiveSyncProviderStatus: Equatable, Sendable {
    var kind: LiveSyncProviderKind
    var title: String
    var state: LiveSyncProviderState
    var detail: String
    var features: [String]
    var checkedAt: Date

    init(
        kind: LiveSyncProviderKind,
        title: String,
        state: LiveSyncProviderState,
        detail: String,
        features: [String] = [],
        checkedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.state = state
        self.detail = detail
        self.features = features
        self.checkedAt = checkedAt
    }
}

nonisolated protocol LiveSyncProvider {
    var kind: LiveSyncProviderKind { get }
    var title: String { get }
    func status(selectedMode: SyncLiveMode) async -> LiveSyncProviderStatus
}
