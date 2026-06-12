//
//  SyncMutationJournal.swift
//  Empty
//

import CryptoKit
import Foundation

private protocol SyncMutationRecord: Sendable {
    nonisolated var id: UUID { get }
}

extension BookRecord: SyncMutationRecord {}
extension HighlightRecord: SyncMutationRecord {}
extension ReadingSessionRecord: SyncMutationRecord {}
extension VocabEntryRecord: SyncMutationRecord {}
extension StudyCardRecord: SyncMutationRecord {}
extension BookmarkRecord: SyncMutationRecord {}
extension MemoryItemRecord: SyncMutationRecord {}

nonisolated struct SyncMutationSummary: Equatable, Sendable {
    var upsertCount: Int
    var tombstoneCount: Int
    var isFullSnapshot: Bool

    var changeCount: Int {
        upsertCount + tombstoneCount
    }

    init(upsertCount: Int, tombstoneCount: Int, isFullSnapshot: Bool) {
        self.upsertCount = upsertCount
        self.tombstoneCount = tombstoneCount
        self.isFullSnapshot = isFullSnapshot
    }

    init(delta: ReaderLiveSyncDelta) {
        self.init(
            upsertCount: delta.recordCount,
            tombstoneCount: delta.tombstones.count,
            isFullSnapshot: delta.isFullSnapshot
        )
    }

    static func bootstrap(from snapshot: SyncSnapshot) -> SyncMutationSummary {
        SyncMutationSummary(delta: .bootstrap(from: snapshot))
    }
}

nonisolated struct SyncMutationJournal: Codable, Equatable, Sendable {
    var baselineSnapshot: SyncSnapshot
    var savedAt: Date = Date()

    func makeDelta(to current: SyncSnapshot) -> ReaderLiveSyncDelta {
        let emittedAt = current.exportedAt
        let bookChanges = diffRecords(
            baseline: baselineSnapshot.books,
            current: current.books,
            kind: .book,
            deletedAt: emittedAt
        )
        let highlightChanges = diffRecords(
            baseline: baselineSnapshot.highlights,
            current: current.highlights,
            kind: .highlight,
            deletedAt: emittedAt
        )
        let sessionChanges = diffRecords(
            baseline: baselineSnapshot.sessions,
            current: current.sessions,
            kind: .readingSession,
            deletedAt: emittedAt
        )
        let vocabChanges = diffRecords(
            baseline: baselineSnapshot.vocab,
            current: current.vocab,
            kind: .vocabEntry,
            deletedAt: emittedAt
        )
        let studyCardChanges = diffRecords(
            baseline: baselineSnapshot.studyCards,
            current: current.studyCards,
            kind: .studyCard,
            deletedAt: emittedAt
        )
        let bookmarkChanges = diffRecords(
            baseline: baselineSnapshot.bookmarks,
            current: current.bookmarks,
            kind: .bookmark,
            deletedAt: emittedAt
        )
        let memoryChanges = diffRecords(
            baseline: baselineSnapshot.memoryItems,
            current: current.memoryItems,
            kind: .memoryItem,
            deletedAt: emittedAt
        )

        return ReaderLiveSyncDelta(
            schemaVersion: max(baselineSnapshot.schemaVersion, current.schemaVersion),
            emittedAt: emittedAt,
            isFullSnapshot: false,
            books: bookChanges.upserts,
            highlights: highlightChanges.upserts,
            sessions: sessionChanges.upserts,
            vocab: vocabChanges.upserts,
            studyCards: studyCardChanges.upserts,
            bookmarks: bookmarkChanges.upserts,
            memoryItems: memoryChanges.upserts,
            tombstones: (
                bookChanges.tombstones
                    + highlightChanges.tombstones
                    + sessionChanges.tombstones
                    + vocabChanges.tombstones
                    + studyCardChanges.tombstones
                    + bookmarkChanges.tombstones
                    + memoryChanges.tombstones
            ).sorted { lhs, rhs in
                if lhs.kind == rhs.kind {
                    return lhs.recordID.uuidString < rhs.recordID.uuidString
                }
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
        )
    }

    func pendingSummary(for current: SyncSnapshot) -> SyncMutationSummary {
        SyncMutationSummary(delta: makeDelta(to: current))
    }

    private func diffRecords<Record: SyncMutationRecord & Equatable>(
        baseline: [Record],
        current: [Record],
        kind: LiveSyncRecordKind,
        deletedAt: Date
    ) -> (upserts: [Record], tombstones: [LiveSyncTombstone]) {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        let upserts = current
            .filter { baselineByID[$0.id] != $0 }
            .sorted { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }

        let tombstones = baselineByID.keys
            .filter { currentByID[$0] == nil }
            .sorted { $0.uuidString < $1.uuidString }
            .map { LiveSyncTombstone(kind: kind, recordID: $0, deletedAt: deletedAt) }

        return (upserts, tombstones)
    }
}

nonisolated struct SyncMutationJournalStore {
    let fileManager: FileManager
    let directoryURL: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        let root = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appending(path: "ApplicationSupport", directoryHint: .isDirectory)
        self.directoryURL = root.appending(path: "SyncMutationJournals", directoryHint: .isDirectory)
    }

    func load(for target: SyncSettings.ServerBackupTarget) throws -> SyncMutationJournal? {
        let url = fileURL(for: target)
        guard fileManager.fileExists(atPath: url.path()) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        do {
            return try SyncSnapshotCodec.makeDecoder().decode(SyncMutationJournal.self, from: data)
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func save(_ journal: SyncMutationJournal, for target: SyncSettings.ServerBackupTarget) throws {
        try ensureDirectoryExists()
        let data = try SyncSnapshotCodec.makeEncoder().encode(journal)
        try data.write(to: fileURL(for: target), options: .atomic)
    }

    func clear(for target: SyncSettings.ServerBackupTarget) throws {
        let url = fileURL(for: target)
        guard fileManager.fileExists(atPath: url.path()) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directoryURL.path()) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for target: SyncSettings.ServerBackupTarget) -> URL {
        let key = "\(target.baseURLString)|\(target.namespace)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        return directoryURL.appending(path: fileName, directoryHint: .notDirectory)
    }
}
