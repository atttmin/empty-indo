//
//  SyncSnapshotTests.swift
//  EmptyTests
//

import Foundation
import SwiftData
import Testing
@testable import Empty

@MainActor
struct SyncSnapshotTests {
    @Test func snapshotCapturesAndRestoresSyncedModelsOnly() throws {
        let source = try AppStores.makeContainer(ephemeral: true)
        let sourceContext = source.mainContext

        let book = Book(title: "Walden", author: "Thoreau", format: .epub)
        book.languageTag = "en"
        book.position = ReadingPosition(chapterIndex: 2, utf16Offset: 88)
        book.progressFraction = 0.42
        book.cachedHeroRecap = "前两章已经读完。"
        book.cachedHeroRecapChapterIndex = 2
        sourceContext.insert(book)

        let highlight = Highlight(
            anchor: TextAnchor(chapterIndex: 1, startUTF16: 4, endUTF16: 16),
            textSnapshot: "Simplify, simplify.",
            color: .vermilion,
            note: "核心主题"
        )
        sourceContext.insert(highlight)
        highlight.book = book

        let session = ReadingSession(startPosition: .start, startedAt: .distantPast)
        session.endPosition = ReadingPosition(chapterIndex: 2, utf16Offset: 88)
        session.activeSeconds = 1_234
        sourceContext.insert(session)
        session.book = book

        let vocab = VocabEntry(
            word: "deliberately",
            meaning: "审慎地",
            note: "梭罗的关键语气",
            sentence: "I wished to live deliberately.",
            source: "Walden · Ch.2"
        )
        sourceContext.insert(vocab)

        let card = StudyCardEntry(
            question: "梭罗为什么强调 deliberately?",
            answer: "因为他想主动筛掉生活里的噪音。",
            source: "Walden · Ch.2",
            kind: .qa
        )
        sourceContext.insert(card)
        card.book = book

        let bookmark = Bookmark(chapterIndex: 2, utf16Offset: 88, snippet: "I wished to live deliberately")
        sourceContext.insert(bookmark)
        bookmark.book = book

        let memory = MemoryItem(
            kind: .theme,
            title: "减法生活",
            body: "读者反复把 simplicity 和 deliberate life 连在一起。",
            bookID: book.id,
            chapterIndex: 1,
            sourceLabel: "Walden · 第 2 章",
            tags: ["simplicity", "theme"],
            isUserConfirmed: true
        )
        sourceContext.insert(memory)

        let chapter = Chapter(bookID: book.id, index: 0, title: "Economy", text: "Local正文不应进入快照。")
        sourceContext.insert(chapter)
        try sourceContext.save()

        let snapshot = try SyncSnapshot.capture(from: sourceContext)
        #expect(snapshot.schemaVersion == SyncSnapshot.currentSchemaVersion)
        #expect(snapshot.books.count == 1)
        #expect(snapshot.highlights.count == 1)
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.vocab.count == 1)
        #expect(snapshot.studyCards.count == 1)
        #expect(snapshot.bookmarks.count == 1)
        #expect(snapshot.memoryItems.count == 1)

        let destination = try AppStores.makeContainer(ephemeral: true)
        let destinationContext = destination.mainContext
        try snapshot.merge(into: destinationContext)

        #expect(try destinationContext.fetchCount(FetchDescriptor<Book>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<Highlight>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<ReadingSession>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<VocabEntry>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<StudyCardEntry>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<Bookmark>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<MemoryItem>()) == 1)
        #expect(try destinationContext.fetchCount(FetchDescriptor<Chapter>()) == 0)

        let restoredBook = try #require(try destinationContext.fetch(FetchDescriptor<Book>()).first)
        #expect(restoredBook.title == "Walden")
        #expect(restoredBook.position == ReadingPosition(chapterIndex: 2, utf16Offset: 88))
        #expect(restoredBook.progressFraction == 0.42)
        #expect(restoredBook.cachedHeroRecap == "前两章已经读完。")

        let restoredHighlight = try #require(try destinationContext.fetch(FetchDescriptor<Highlight>()).first)
        #expect(restoredHighlight.book?.id == restoredBook.id)
        #expect(restoredHighlight.note == "核心主题")

        let restoredMemory = try #require(try destinationContext.fetch(FetchDescriptor<MemoryItem>()).first)
        #expect(restoredMemory.kind == .theme)
        #expect(restoredMemory.tags == ["simplicity", "theme"])
    }

    @Test func folderProviderWritesAndReadsStableSnapshotFile() throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        context.insert(Book(title: "备份测试", format: .epub))
        try context.save()

        let snapshot = try SyncSnapshot.capture(from: context)
        let folderURL = FileManager.default.temporaryDirectory
            .appending(path: "SyncSnapshotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let bookmark = try folderURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let provider = FolderBackupProvider(
            target: .init(bookmarkData: bookmark, displayName: "tmp", lastSnapshotAt: nil)
        )

        let fileURL = try provider.writeSnapshot(snapshot)
        #expect(fileURL.lastPathComponent == FolderBackupProvider.snapshotFilename)

        let restored = try provider.readLatestSnapshot()
        #expect(restored.schemaVersion == snapshot.schemaVersion)
        #expect(abs(restored.exportedAt.timeIntervalSince(snapshot.exportedAt)) < 1)
        #expect(restored.books.count == 1)
        #expect(restored.books.first?.title == snapshot.books.first?.title)
        #expect(restored.books.first?.id == snapshot.books.first?.id)
        #expect(abs((restored.books.first?.addedAt ?? .distantPast).timeIntervalSince(snapshot.books.first?.addedAt ?? .distantPast)) < 1)
        #expect(restored.highlights.isEmpty)
    }
}
