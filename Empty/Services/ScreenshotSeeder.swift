//
//  ScreenshotSeeder.swift
//  Empty
//
//  Imports a tiny demo EPUB when `-ScreenshotSeed` is passed (simulator
//  screenshots). No-op when the library already has books.
//

import Foundation
import PDFKit
import SwiftData

enum ScreenshotSeeder {
    @discardableResult
    @MainActor
    static func seedDemoBookIfNeeded(modelContext: ModelContext) throws -> Book? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-ScreenshotSeed") else { return nil }
        let descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\Book.lastOpenedAt, order: .reverse)]
        )
        let existing = try modelContext.fetch(descriptor)
        let book = try existing.first(where: isDemoBook) ?? importDemoBook(modelContext: modelContext)
        if book.lastOpenedAt == nil {
            book.lastOpenedAt = Date()
            try? modelContext.save()
        }
        if args.contains("-ScreenshotSeedHighlight") || args.contains("-ScreenshotSeedStudyData") {
            try seedDemoHighlightIfNeeded(book: book, modelContext: modelContext)
        }
        if args.contains("-ScreenshotSeedBookmark") {
            try seedDemoBookmarkIfNeeded(book: book, modelContext: modelContext)
        }
        if args.contains("-ScreenshotSeedStudyData") {
            try seedDemoStudyDataIfNeeded(book: book, modelContext: modelContext)
        }
        _ = try seedDemoPDFIfNeeded(modelContext: modelContext)
        return book
    }

    private static func isDemoBook(_ book: Book) -> Bool {
        book.title == "思维之书" && book.author == "测试作者"
    }

    @MainActor
    private static func importDemoBook(modelContext: ModelContext) throws -> Book {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "EmptyScreenshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let epubURL = temp.appending(path: "demo.epub")
        try DemoEPUB.data().write(to: epubURL)

        let store = try BookFileStore.makeDefault()
        return try Library(modelContext: modelContext, fileStore: store)
            .importBook(from: epubURL)
    }


    @discardableResult
    @MainActor
    static func seedDemoPDFIfNeeded(modelContext: ModelContext) throws -> Book? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-ScreenshotSeedPDF") else { return nil }
        if let existing = try modelContext.fetch(
            FetchDescriptor<Book>(
                predicate: #Predicate {
                    $0.title == "纸页样本" && $0.author == "测试作者"
                }
            )
        ).first {
            if existing.lastOpenedAt == nil {
                existing.lastOpenedAt = Date()
                try? modelContext.save()
            }
            return existing
        }

        let temp = FileManager.default.temporaryDirectory
            .appending(path: "EmptyScreenshotPDF-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let pdfURL = temp.appending(path: "demo.pdf")
        try DemoPDF.write(to: pdfURL)

        let store = try BookFileStore.makeDefault()
        let book = try Library(modelContext: modelContext, fileStore: store).importBook(from: pdfURL)
        book.lastOpenedAt = Date()
        try? modelContext.save()
        return book
    }
    @MainActor
    private static func seedDemoHighlightIfNeeded(
        book: Book,
        modelContext: ModelContext
    ) throws {
        let store = HighlightStore(modelContext: modelContext)
        if try store.highlights(for: book).contains(where: { $0.textSnapshot.contains("深读始于空白") }) {
            return
        }
        let highlight = try store.createHighlight(
            book: book,
            chapterIndex: 0,
            selection: "深读始于空白"
        )
        try store.updateNote(highlight, note: "第一条测试批注。")
    }

    @MainActor
    private static func seedDemoBookmarkIfNeeded(
        book: Book,
        modelContext: ModelContext
    ) throws {
        let existing = try BookmarkStore(modelContext: modelContext).bookmarks(for: book)
        guard !existing.contains(where: { $0.chapterIndex == 0 && $0.utf16Offset < 600 }) else {
            return
        }
        let bookmark = Bookmark(
            chapterIndex: 0,
            utf16Offset: 0,
            snippet: "深读始于空白。导入一本书，朱批落在页边。"
        )
        modelContext.insert(bookmark)
        bookmark.book = book
        try modelContext.save()
    }

    @MainActor
    private static func seedDemoStudyDataIfNeeded(
        book: Book,
        modelContext: ModelContext
    ) throws {
        let highlightStore = HighlightStore(modelContext: modelContext)
        let highlight = try highlightStore.highlights(for: book).first(where: {
            $0.textSnapshot.contains("深读始于空白")
        })

        if try modelContext.fetch(
            FetchDescriptor<StudyCardEntry>(
                predicate: #Predicate { $0.question == "空白处应该留给谁?" }
            )
        ).isEmpty {
            let review = StudyCardEntry(
                question: "空白处应该留给谁?",
                answer: "留给批注、停顿和下一次回读。",
                source: "\(book.title) · 第 1 章",
                highlightID: highlight?.id,
                kind: .review
            )
            review.book = book
            review.setSourcePosition(ReadingPosition(chapterIndex: 0, utf16Offset: 0))
            review.dueAt = Date().addingTimeInterval(-600)
            modelContext.insert(review)
        }

        if try modelContext.fetch(
            FetchDescriptor<VocabEntry>(
                predicate: #Predicate { $0.word == "空白" }
            )
        ).isEmpty {
            let vocab = VocabEntry(
                word: "空白",
                meaning: "留出来让思考发生的空间。",
                note: "这里不是空无，而是刻意留白。",
                sentence: "深读始于空白。导入一本书，朱批落在页边。",
                source: "\(book.title) · 第 1 章"
            )
            vocab.book = book
            vocab.setSourcePosition(ReadingPosition(chapterIndex: 0, utf16Offset: 0))
            vocab.dueAt = Date().addingTimeInterval(-600)
            modelContext.insert(vocab)
        }

        let relatedBook = try relatedGraphBookIfNeeded(modelContext: modelContext)
        if try modelContext.fetch(
            FetchDescriptor<StudyCardEntry>(
                predicate: #Predicate { $0.question == "空白如何让深读发生?" }
            )
        ).isEmpty {
            let link = StudyCardEntry(
                question: "空白如何让深读发生?",
                answer: "空白不是缺席，而是让深读和批注发生的空地。",
                source: "\(relatedBook.title) ⟷ \(book.title)",
                kind: .link
            )
            link.book = relatedBook
            modelContext.insert(link)
        }

        try modelContext.save()
    }

    @MainActor
    private static func relatedGraphBookIfNeeded(modelContext: ModelContext) throws -> Book {
        if let existing = try modelContext.fetch(
            FetchDescriptor<Book>(
                predicate: #Predicate { $0.title == "旁注之书" }
            )
        ).first {
            return existing
        }

        let related = Book(title: "旁注之书", author: "测试作者", format: .epub)
        related.languageTag = "zh"
        modelContext.insert(related)
        return related
    }
}

private enum DemoPDF {
    static func write(to url: URL) throws {
        let document = PDFDocument()
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "纸页样本",
            PDFDocumentAttribute.authorAttribute: "测试作者",
        ]
        for (index, text) in [
            "第一页：PDF 阅读器应该稳定打开、翻页，并保留回到原文的能力。",
            "第二页：即使是纸页，也要把 AI、检索与批注接在同一条阅读链路里。"
        ].enumerated() {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            let annotation = PDFAnnotation(
                bounds: CGRect(x: 72, y: 650, width: 440, height: 80),
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = text
            page.addAnnotation(annotation)
            document.insert(page, at: index)
        }
        guard document.write(to: url) else {
            struct PDFWriteError: Error {}
            throw PDFWriteError()
        }
    }
}


// MARK: - Minimal EPUB bytes (mirrors EmptyTests fixture)

private enum DemoEPUB {
    static func data() -> Data {
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>思维之书</dc:title>
            <dc:creator>测试作者</dc:creator>
            <dc:language>zh</dc:language>
            <dc:identifier id="uid">demo-epub</dc:identifier>
          </metadata>
          <manifest>
            <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
          </spine>
        </package>
        """
        // Long enough that the paged reader produces several pages —
        // page-turn smoke tests and screenshots need real pagination.
        let fillerParagraphs = (1...18).map { index in
            """
            <p>第\(index)节。读书不是把字看完，而是让一段文字在心里站住。空白处\
            才放得下批注，节奏慢下来，问题才会浮出。这一段是排版与翻页的演示文本，\
            用来撑起完整的一页，再多读一行，就再翻一页。</p>
            """
        }.joined()
        let chapter = """
        <html><head><title>第一章</title></head>\
        <body><h1>第一章</h1><p>深读始于空白。导入一本书，朱批落在页边。</p>\
        \(fillerParagraphs)<p>第一章在此收束：合上扉页，故事才真正开始。</p></body></html>
        """
        let chapter2 = """
        <html><head><title>第二章</title></head>\
        <body><h1>第二章</h1><p>第二章自此开始：换一页纸，换一种问法。</p>\
        <p>翻页跨过章节边界时，阅读器应当无缝接上，而不是把读者丢回开头。</p></body></html>
        """
        return storedZIP(entries: [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(containerXML.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/ch1.xhtml", Data(chapter.utf8)),
            ("OEBPS/ch2.xhtml", Data(chapter2.utf8)),
        ])
    }

    private static func storedZIP(entries: [(name: String, data: Data)]) -> Data {
        var zip = Data()
        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            zip.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
            appendLE16(&zip, 20)
            appendLE16(&zip, 0)
            appendLE16(&zip, 0)
            appendLE16(&zip, 0)
            appendLE16(&zip, 0)
            appendLE32(&zip, 0)
            appendLE32(&zip, UInt32(entry.data.count))
            appendLE32(&zip, UInt32(entry.data.count))
            appendLE16(&zip, UInt16(nameBytes.count))
            appendLE16(&zip, 0)
            zip.append(contentsOf: nameBytes)
            zip.append(entry.data)
        }
        return zip
    }

    private static func appendLE16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private static func appendLE32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}