//
//  LiveSyncContract.swift
//  Empty
//

import Foundation

nonisolated enum LiveSyncFeature: String, Codable, CaseIterable, Sendable {
    case readerSnapshotsV1 = "reader-snapshots-v1"
    case readerLiveSyncV1 = "reader-live-sync-v1"
}

nonisolated enum LiveSyncRecordKind: String, Codable, CaseIterable, Sendable {
    case book
    case highlight
    case readingSession
    case vocabEntry
    case studyCard
    case bookmark
    case memoryItem
}

nonisolated struct LiveSyncCursor: Codable, Equatable, Sendable {
    var opaqueValue: String
    var serverTime: Date?

    init(opaqueValue: String, serverTime: Date? = nil) {
        self.opaqueValue = opaqueValue
        self.serverTime = serverTime
    }
}

nonisolated struct LiveSyncTombstone: Codable, Equatable, Sendable {
    var kind: LiveSyncRecordKind
    var recordID: UUID
    var deletedAt: Date

    init(kind: LiveSyncRecordKind, recordID: UUID, deletedAt: Date) {
        self.kind = kind
        self.recordID = recordID
        self.deletedAt = deletedAt
    }
}

nonisolated struct ReaderLiveSyncDelta: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var emittedAt: Date = Date()
    var isFullSnapshot: Bool = false
    var books: [BookRecord] = []
    var highlights: [HighlightRecord] = []
    var sessions: [ReadingSessionRecord] = []
    var vocab: [VocabEntryRecord] = []
    var studyCards: [StudyCardRecord] = []
    var bookmarks: [BookmarkRecord] = []
    var memoryItems: [MemoryItemRecord] = []
    var tombstones: [LiveSyncTombstone] = []

    static func bootstrap(from snapshot: SyncSnapshot) -> ReaderLiveSyncDelta {
        ReaderLiveSyncDelta(
            schemaVersion: snapshot.schemaVersion,
            emittedAt: snapshot.exportedAt,
            isFullSnapshot: true,
            books: snapshot.books,
            highlights: snapshot.highlights,
            sessions: snapshot.sessions,
            vocab: snapshot.vocab,
            studyCards: snapshot.studyCards,
            bookmarks: snapshot.bookmarks,
            memoryItems: snapshot.memoryItems,
            tombstones: []
        )
    }
}

nonisolated struct ReaderLiveSyncPullRequest: Codable, Equatable, Sendable {
    var cursor: LiveSyncCursor?
    var wantsFullSnapshot: Bool
    var schemaVersion: Int

    init(cursor: LiveSyncCursor?, wantsFullSnapshot: Bool, schemaVersion: Int = ReaderLiveSyncDelta.currentSchemaVersion) {
        self.cursor = cursor
        self.wantsFullSnapshot = wantsFullSnapshot
        self.schemaVersion = schemaVersion
    }
}

nonisolated struct ReaderLiveSyncPullResponse: Codable, Equatable, Sendable {
    var delta: ReaderLiveSyncDelta
    var nextCursor: LiveSyncCursor?
    var resetRequired: Bool
}

nonisolated struct ReaderLiveSyncPushRequest: Codable, Equatable, Sendable {
    var baseCursor: LiveSyncCursor?
    var delta: ReaderLiveSyncDelta

    init(baseCursor: LiveSyncCursor?, delta: ReaderLiveSyncDelta) {
        self.baseCursor = baseCursor
        self.delta = delta
    }
}

nonisolated struct ReaderLiveSyncPushResponse: Codable, Equatable, Sendable {
    var acceptedCursor: LiveSyncCursor?
    var serverTime: Date?
    var resetRequired: Bool
}
