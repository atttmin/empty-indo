//
//  LibraryTests.swift
//  EmptyTests
//

import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Empty

#if canImport(AppKit)
import AppKit
import CoreGraphics
import CoreText
#endif

@MainActor
struct LibraryTests {
    @Test func importCreatesBookAndCopiesFile() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let source = try fixture.writeSourceFile(named: "My Great Novel.epub")

        let book = try fixture.library.importBook(from: source)

        #expect(book.title == "My Great Novel")
        #expect(book.format == .epub)
        let relativePath = try #require(book.fileRelativePath)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.store.url(forRelativePath: relativePath).path
            )
        )
        #expect(try fixture.context.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func importRejectsUnsupportedTypes() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let source = try fixture.writeSourceFile(named: "notes.txt")

        #expect(throws: LibraryError.self) {
            try fixture.library.importBook(from: source)
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func importAcceptsPDF() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let source = try fixture.writeMinimalPDF(named: "paper.pdf")

        let book = try fixture.library.importBook(from: source)

        #expect(book.format == .pdf)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func deleteRemovesRecordsDerivedDataAndFiles() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let source = try fixture.writeSourceFile(named: "Doomed.epub")
        let book = try fixture.library.importBook(from: source)
        let context = fixture.context

        let chapter = Chapter(bookID: book.id, index: 0, text: "Chapter text")
        context.insert(chapter)
        let chunk = Chunk(
            bookID: book.id,
            ordinal: 0,
            anchor: TextAnchor(chapterIndex: 0, startUTF16: 0, endUTF16: 12),
            text: "Chapter text"
        )
        context.insert(chunk)
        chunk.chapter = chapter
        let highlight = Highlight(
            anchor: TextAnchor(chapterIndex: 0, startUTF16: 0, endUTF16: 7),
            textSnapshot: "Chapter"
        )
        context.insert(highlight)
        highlight.book = book
        try context.save()

        let bookDirectory = fixture.store.url(forRelativePath: book.id.uuidString)
        #expect(FileManager.default.fileExists(atPath: bookDirectory.path))

        try fixture.library.deleteBook(book)

        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Highlight>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Chapter>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Chunk>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: bookDirectory.path))
    }
}

/// Ephemeral container + temp-directory file store, torn down per test.
///
/// Holds the `ModelContainer` strongly: `ModelContext` references its
/// container unowned, so dropping it here leaves the context dangling and
/// SwiftData traps at a random later operation.
@MainActor
private struct Fixture {
    let container: ModelContainer
    let context: ModelContext
    let store: BookFileStore
    let library: Library
    private let tempDirectory: URL

    init() throws {
        container = try AppStores.makeContainer(ephemeral: true)
        context = container.mainContext
        tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "LibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        store = BookFileStore(
            rootDirectory: tempDirectory.appending(path: "store", directoryHint: .isDirectory)
        )
        library = Library(modelContext: context, fileStore: store)
    }

    func writeSourceFile(named name: String) throws -> URL {
        let url = tempDirectory.appending(path: name)
        try Data("placeholder book bytes".utf8).write(to: url)
        return url
    }

    func writeMinimalPDF(named name: String) throws -> URL {
        #if canImport(AppKit)
        let url = tempDirectory.appending(path: name)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            struct PDFWriteError: Error {}
            throw PDFWriteError()
        }
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(
            string: "PDF import test",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        context.translateBy(x: 72, y: 720)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return url
        #else
        let url = tempDirectory.appending(path: name)
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        document.insert(page, at: 0)
        guard document.write(to: url) else {
            struct PDFWriteError: Error {}
            throw PDFWriteError()
        }
        return url
        #endif
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}
