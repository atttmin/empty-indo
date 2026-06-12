//
//  SyncBackupProvider.swift
//  Empty
//

import Foundation

nonisolated struct SyncBackupReceipt: Equatable, Sendable {
    var locationDescription: String
    var updatedAt: Date?
    var etag: String?
}

nonisolated protocol SyncSnapshotBackupProvider {
    var providerTitle: String { get }
    func export(snapshot: SyncSnapshot) async throws -> SyncBackupReceipt
    func restoreLatest() async throws -> SyncSnapshot
}
