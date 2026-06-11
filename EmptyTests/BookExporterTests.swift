//
//  BookExporterTests.swift
//  EmptyTests
//
//  P1 导出: markdown/plain rendering, option toggles, and the empty://
//  deep-link round trip.
//

import Foundation
import SwiftData
import Testing
@testable import Empty

struct EmptyDeepLinkTests {
    @Test func roundTripsBookAndPosition() throws {
        let bookID = UUID()
        let urlString = EmptyDeepLink.urlString(
            bookID: bookID, chapterIndex: 4, utf16Offset: 1234
        )
        let url = try #require(URL(string: urlString))
        let parsed = try #require(EmptyDeepLink.parse(url))
        #expect(parsed.bookID == bookID)
        #expect(parsed.position.chapterIndex == 4)
        #expect(parsed.position.utf16Offset == 1234)
    }

    @Test func rejectsForeignURLs() {
        #expect(EmptyDeepLink.parse(URL(string: "https://example.com/book/x")!) == nil)
        #expect(EmptyDeepLink.parse(URL(string: "empty://card/abc")!) == nil)
    }
}

@MainActor
struct BookExporterTests {
    private func makeFixture() throws -> (ModelContainer, Book) {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        let book = Book(title: "思维之书", author: "测试作者", format: .epub)
        context.insert(book)
        context.insert(Chapter(bookID: book.id, index: 0, title: "起 · 空白", text: "第一章正文，深读始于空白。"))
        try context.save()

        let highlight = try HighlightStore(modelContext: context).createHighlight(
            book: book, chapterIndex: 0, selection: "深读始于空白"
        )
        try HighlightStore(modelContext: context).updateNote(highlight, note: "第一条批注")
        try BookmarkStore(modelContext: context).toggle(
            book: book, chapterIndex: 0, utf16Offset: 3, snippet: "一章正文"
        )
        return (container, book)
    }

    @Test func markdownIncludesQuotesNotesBookmarksAndLinks() throws {
        let (container, book) = try makeFixture()
        let exporter = BookExporter(modelContext: container.mainContext)

        let markdown = try exporter.export(book: book, options: BookExportOptions())

        #expect(markdown.contains("# 思维之书 · 摘录"))
        #expect(markdown.contains("## 起 · 空白"))
        #expect(markdown.contains("> 深读始于空白"))
        #expect(markdown.contains("> 批注：第一条批注"))
        #expect(markdown.contains("🔖 一章正文"))
        #expect(markdown.contains("empty://book/\(book.id.uuidString)?c=0&o="))

        _ = container
    }

    @Test func togglesDropSectionsAndPlainTextHasNoMarkdown() throws {
        let (container, book) = try makeFixture()
        let exporter = BookExporter(modelContext: container.mainContext)

        var options = BookExportOptions()
        options.includeNotes = false
        options.includeBookmarks = false
        options.format = .plainText
        let plain = try exporter.export(book: book, options: options)

        #expect(!plain.contains("批注"))
        #expect(!plain.contains("🔖"))
        #expect(!plain.contains("# "))
        #expect(plain.contains("“深读始于空白”"))
        #expect(plain.contains("empty://book/"))

        _ = container
    }
}
