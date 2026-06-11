//
//  BookExporter.swift
//  Empty
//
//  P1 导出: highlights / notes / bookmarks as Markdown or plain text,
//  every entry carrying an empty:// deep link back to its exact place
//  in the book (book id + TextAnchor).
//

import Foundation
import SwiftData

/// `empty://book/<uuid>?c=<chapterIndex>&o=<utf16Offset>` — the stable
/// reference format exported notes carry back to the original passage.
nonisolated enum EmptyDeepLink {
    static func urlString(bookID: UUID, chapterIndex: Int, utf16Offset: Int) -> String {
        "empty://book/\(bookID.uuidString)?c=\(chapterIndex)&o=\(utf16Offset)"
    }

    static func parse(_ url: URL) -> (bookID: UUID, position: ReadingPosition)? {
        guard url.scheme == "empty", url.host == "book" else { return nil }
        let idPart = url.lastPathComponent
        guard let bookID = UUID(uuidString: idPart) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let chapter = items.first { $0.name == "c" }?.value.flatMap(Int.init) ?? 0
        let offset = items.first { $0.name == "o" }?.value.flatMap(Int.init) ?? 0
        return (bookID, ReadingPosition(chapterIndex: chapter, utf16Offset: offset))
    }
}

nonisolated struct BookExportOptions: Equatable {
    enum Format: String, CaseIterable {
        case markdown = "Markdown"
        case plainText = "纯文本"
    }

    var includeHighlights = true
    var includeNotes = true
    var includeBookmarks = true
    var format: Format = .markdown
}

/// Renders a book's reader data as a shareable document.
@MainActor
struct BookExporter {
    let modelContext: ModelContext

    func export(book: Book, options: BookExportOptions) throws -> String {
        let highlights = options.includeHighlights
            ? try HighlightStore(modelContext: modelContext).highlights(for: book)
            : []
        let bookmarks = options.includeBookmarks
            ? try BookmarkStore(modelContext: modelContext).bookmarks(for: book)
            : []
        let titles = try chapterTitles(book: book)
        let markdown = options.format == .markdown

        var lines: [String] = []
        if markdown {
            lines.append("# \(book.title) · 摘录")
            if !book.author.isEmpty { lines.append("_\(book.author)_") }
        } else {
            lines.append("\(book.title) · 摘录")
            if !book.author.isEmpty { lines.append(book.author) }
        }
        lines.append("")

        let chapterIndexes = Set(highlights.map(\.chapterIndex))
            .union(bookmarks.map(\.chapterIndex))
            .sorted()

        for chapterIndex in chapterIndexes {
            let title = titles[chapterIndex] ?? "第 \(chapterIndex + 1) 章"
            lines.append(markdown ? "## \(title)" : "◇ \(title)")
            lines.append("")

            for highlight in highlights where highlight.chapterIndex == chapterIndex {
                let link = EmptyDeepLink.urlString(
                    bookID: book.id,
                    chapterIndex: highlight.chapterIndex,
                    utf16Offset: highlight.startUTF16
                )
                if markdown {
                    lines.append("> \(highlight.textSnapshot)")
                    if options.includeNotes,
                       let note = highlight.note, !note.isEmpty {
                        lines.append(">")
                        lines.append("> 批注：\(note)")
                    }
                    lines.append("")
                    lines.append("[回到原文](\(link))")
                } else {
                    lines.append("“\(highlight.textSnapshot)”")
                    if options.includeNotes,
                       let note = highlight.note, !note.isEmpty {
                        lines.append("批注：\(note)")
                    }
                    lines.append(link)
                }
                lines.append("")
            }

            for bookmark in bookmarks where bookmark.chapterIndex == chapterIndex {
                let link = EmptyDeepLink.urlString(
                    bookID: book.id,
                    chapterIndex: bookmark.chapterIndex,
                    utf16Offset: bookmark.utf16Offset
                )
                if markdown {
                    lines.append("- 🔖 \(bookmark.snippet) — [回到原文](\(link))")
                } else {
                    lines.append("🔖 \(bookmark.snippet)")
                    lines.append(link)
                }
                lines.append("")
            }
        }

        if chapterIndexes.isEmpty {
            lines.append(markdown ? "_这本书还没有摘录。_" : "这本书还没有摘录。")
        }
        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func chapterTitles(book: Book) throws -> [Int: String] {
        let bookID = book.id
        let chapters = try modelContext.fetch(FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.bookID == bookID }
        ))
        return Dictionary(
            uniqueKeysWithValues: chapters.compactMap { chapter -> (Int, String)? in
                guard let title = chapter.title,
                      !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return nil
                }
                return (chapter.index, title)
            }
        )
    }
}
