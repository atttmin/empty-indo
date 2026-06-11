//
//  PDFTests.swift
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
struct PDFTests {
    // MARK: - Selection context

    @Test func selectionContextTakesSurroundingPageText() {
        let pageText = String(repeating: "a", count: 100)
            + "the murder weapon"
            + String(repeating: "b", count: 100)
        let range = NSRange(location: 100, length: 17)

        let selection = PDFSelectionContext.readerSelection(
            pageText: pageText,
            selectedText: "the murder weapon",
            range: range
        )

        #expect(selection.text == "the murder weapon")
        #expect(selection.prefix == String(repeating: "a", count: 40))
        #expect(selection.suffix == String(repeating: "b", count: 40))
    }

    @Test func selectionContextClampsAtPageEdges() {
        let pageText = "short page"
        let selection = PDFSelectionContext.readerSelection(
            pageText: pageText,
            selectedText: "short",
            range: NSRange(location: 0, length: 5)
        )
        #expect(selection.prefix.isEmpty)
        #expect(selection.suffix == " page")
    }

    @Test func selectionContextSurvivesInvalidRange() {
        let selection = PDFSelectionContext.readerSelection(
            pageText: "anything",
            selectedText: "  selected  ",
            range: NSRange(location: NSNotFound, length: 0)
        )
        #expect(selection.text == "selected")
        #expect(selection.prefix.isEmpty)
        #expect(selection.suffix.isEmpty)
    }

    @Test func selectionContextKeepsSurrogatePairsIntact() {
        // Each "🜁" is 2 UTF-16 units. Layout below puts the 40-unit prefix
        // window's start (offset 10) in the middle of the pair spanning
        // 9–10, and the suffix window's end mid-pair symmetrically — the
        // boundaries must round to composed-character edges instead of
        // slicing pairs into U+FFFD.
        let pageText = "a" + String(repeating: "🜁", count: 24) + "z"
            + "needle"
            + "z" + String(repeating: "🜁", count: 24) + "a"
        let range = NSRange(location: 50, length: 6)

        let selection = PDFSelectionContext.readerSelection(
            pageText: pageText,
            selectedText: "needle",
            range: range
        )

        #expect(!selection.prefix.contains("\u{FFFD}"))
        #expect(!selection.suffix.contains("\u{FFFD}"))
        #expect(selection.prefix.hasSuffix("z"))
        #expect(selection.suffix.hasPrefix("z"))
    }

    @Test func parserExtractsPerPageText() throws {
        let fixture = try PDFFixture()
        defer { fixture.tearDown() }

        let source = try fixture.writePDF(
            named: "sample.pdf",
            pageTexts: ["First page text.", "Second page text."]
        )
        let parsed = try PDFParser().parseBook(at: source)

        #expect(parsed.pages.count == 2)
        #expect(parsed.pages[0].text.contains("First"))
        #expect(parsed.pages[1].text.contains("Second"))
        #expect(parsed.pages[0].title == "Page 1")
    }

    @Test func importCreatesChaptersPerPage() throws {
        let fixture = try PDFFixture()
        defer { fixture.tearDown() }

        let source = try fixture.writePDF(
            named: "Paper.pdf",
            pageTexts: ["Alpha", "Beta"]
        )
        let book = try fixture.library.importBook(from: source)

        #expect(book.format == .pdf)
        let bookID = book.id
        let chapters = try fixture.context.fetch(
            FetchDescriptor<Chapter>(
                predicate: #Predicate { $0.bookID == bookID },
                sortBy: [SortDescriptor(\.index)]
            )
        )
        #expect(chapters.count == 2)
        #expect(chapters[0].text.contains("Alpha"))
        #expect(chapters[1].text.contains("Beta"))
        #expect(chapters[0].sourceReference == "0")
    }

    @Test func ensurePDFChaptersBackfillsMissingRows() throws {
        let fixture = try PDFFixture()
        defer { fixture.tearDown() }

        let source = try fixture.writePDF(
            named: "Backfill.pdf",
            pageTexts: ["Only page"]
        )
        let book = Book(title: "Backfill", format: .pdf)
        book.fileRelativePath = try fixture.store.importFile(at: source, bookID: book.id)
        fixture.context.insert(book)
        try fixture.context.save()

        let titles = try Library.ensurePDFChapters(
            for: book,
            at: fixture.store.url(forRelativePath: try #require(book.fileRelativePath)),
            in: fixture.context
        )

        #expect(titles.count == 1)
        let bookID = book.id
        let chapters = try fixture.context.fetch(
            FetchDescriptor<Chapter>(predicate: #Predicate { $0.bookID == bookID })
        )
        #expect(chapters.count == 1)
        #expect(chapters[0].text.contains("Only"))
    }
}

#if canImport(AppKit)
@MainActor
private struct PDFFixture {
    let container: ModelContainer
    let context: ModelContext
    let store: BookFileStore
    let library: Library
    private let tempDirectory: URL

    init() throws {
        container = try AppStores.makeContainer(ephemeral: true)
        context = container.mainContext
        tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "PDFTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        store = BookFileStore(
            rootDirectory: tempDirectory.appending(path: "store", directoryHint: .isDirectory)
        )
        library = Library(modelContext: context, fileStore: store)
    }

    func writePDF(named name: String, pageTexts: [String]) throws -> URL {
        let url = tempDirectory.appending(path: name)
        try TestPDFWriter.write(pages: pageTexts, to: url)
        return url
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

private enum TestPDFWriter {
    static func write(pages: [String], to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            struct PDFWriteError: Error {}
            throw PDFWriteError()
        }
        for text in pages {
            context.beginPDFPage(nil)
            let attributed = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.systemFont(ofSize: 14)]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            context.textMatrix = .identity
            context.translateBy(x: 72, y: 720)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
    }
}
#else
@MainActor
private struct PDFFixture {
    let container: ModelContainer
    let context: ModelContext
    let store: BookFileStore
    let library: Library
    private let tempDirectory: URL

    init() throws {
        container = try AppStores.makeContainer(ephemeral: true)
        context = container.mainContext
        tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "PDFTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        store = BookFileStore(
            rootDirectory: tempDirectory.appending(path: "store", directoryHint: .isDirectory)
        )
        library = Library(modelContext: context, fileStore: store)
    }

    func writePDF(named name: String, pageTexts: [String]) throws -> URL {
        let document = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            let annotation = PDFAnnotation(
                bounds: CGRect(x: 72, y: 650, width: 400, height: 40),
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = text
            page.addAnnotation(annotation)
            document.insert(page, at: index)
        }
        let url = tempDirectory.appending(path: name)
        guard document.write(to: url) else {
            struct PDFWriteError: Error {}
            throw PDFWriteError()
        }
        return url
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}
#endif