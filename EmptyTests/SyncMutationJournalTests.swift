//
//  SyncMutationJournalTests.swift
//  EmptyTests
//

import Foundation
import SwiftData
import Testing
@testable import Empty

@MainActor
struct SyncMutationJournalTests {
    @Test func journalDiffTracksUpsertsAndDeletes() throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext

        let book = Book(title: "Walden", author: "Thoreau", format: .epub)
        context.insert(book)
        let bookmark = Bookmark(chapterIndex: 0, utf16Offset: 8, snippet: "first")
        bookmark.book = book
        context.insert(bookmark)
        try context.save()

        let baseline = try SyncSnapshot.capture(from: context)
        let journal = SyncMutationJournal(baselineSnapshot: baseline, savedAt: Date(timeIntervalSince1970: 10))

        book.title = "Walden · annotated"
        context.delete(bookmark)
        try context.save()

        let current = try SyncSnapshot.capture(from: context)
        let delta = journal.makeDelta(to: current)

        #expect(delta.isFullSnapshot == false)
        #expect(delta.recordCount == 1)
        #expect(delta.books.first?.id == book.id)
        #expect(delta.tombstones.count == 1)
        #expect(delta.tombstones.first?.kind == .bookmark)
        #expect(delta.tombstones.first?.recordID == bookmark.id)
    }

    @Test func journalStoreRoundTripsPerServerTarget() throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        context.insert(Book(title: "Store Test", format: .epub))
        try context.save()

        let snapshot = try SyncSnapshot.capture(from: context)
        let journal = SyncMutationJournal(baselineSnapshot: snapshot, savedAt: Date(timeIntervalSince1970: 20))
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SyncMutationJournalTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = SyncMutationJournalStore(baseDirectoryURL: root)
        let target = SyncSettings.ServerBackupTarget(
            baseURLString: "https://sync.example.com",
            namespace: "reader-main",
            authMode: .none,
            lastSnapshotAt: nil,
            lastValidatedAt: nil,
            liveCursor: LiveSyncCursor(opaqueValue: "cursor-9"),
            lastLivePullAt: nil,
            lastLivePushAt: nil,
            autoSyncEnabled: false,
            autoSyncIntervalSeconds: 120,
            lastAutoSyncAt: nil,
            lastAutoSyncFingerprint: nil
        )

        try store.save(journal, for: target)
        let loadedJournal = try store.load(for: target)
        let loaded = try #require(loadedJournal)
        #expect(loaded.baselineSnapshot.books.first?.id == journal.baselineSnapshot.books.first?.id)
        #expect(loaded.baselineSnapshot.books.first?.title == journal.baselineSnapshot.books.first?.title)
        #expect(abs(loaded.savedAt.timeIntervalSince(journal.savedAt)) < 0.001)

        try store.clear(for: target)
        #expect(try store.load(for: target) == nil)
    }
}
