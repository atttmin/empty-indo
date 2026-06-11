//
//  Chapter.swift
//  Empty
//

import Foundation
import SwiftData

/// Extracted plain text of one reading-order chapter (EPUB spine item,
/// PDF section).
///
/// Local store only: chapter text is derived from the imported file and
/// always re-extractable, so it never syncs — CloudKit quota, and the source
/// file doesn't sync either. References its book by `bookID`; cross-store
/// relationships don't exist.
@Model
final class Chapter {
    #Index<Chapter>([\.bookID], [\.bookID, \.index])

    var bookID: UUID
    /// Zero-based reading-order index; `ReadingPosition.chapterIndex`
    /// points here.
    var index: Int
    var title: String?
    /// Where the text came from in the source file (EPUB spine href,
    /// PDF page range).
    var sourceReference: String?

    /// UTF-8 bytes of the extracted plain text, kept out of row storage.
    @Attribute(.externalStorage) private var textData: Data
    /// Cached `text.utf16.count` so position math never decodes the blob.
    private(set) var utf16Length: Int
    /// Lazily cached AI condensation of this chapter (the expensive "map"
    /// half of recap); cleared implicitly when the chapter row is rebuilt.
    var cachedSummary: String?

    var text: String {
        get { String(decoding: textData, as: UTF8.self) }
        set {
            textData = Data(newValue.utf8)
            utf16Length = newValue.utf16.count
        }
    }

    @Relationship(deleteRule: .cascade, inverse: \Chunk.chapter)
    var chunks: [Chunk] = []

    init(
        bookID: UUID,
        index: Int,
        title: String? = nil,
        sourceReference: String? = nil,
        text: String
    ) {
        self.bookID = bookID
        self.index = index
        self.title = title
        self.sourceReference = sourceReference
        self.textData = Data(text.utf8)
        self.utf16Length = text.utf16.count
    }
}

extension Chapter {
    /// Concatenated plain text of every chapter the reader has fully passed
    /// (`index < position.chapterIndex`), in reading order, each prefixed
    /// with its title so map-reduce condense passes keep chapter identity.
    /// Empty when nothing lies behind the position.
    ///
    /// Includes fully read prior chapters plus the in-progress chapter up to
    /// `position.utf16Offset` when the offset is non-zero.
    static func fullyReadText(
        forBookID bookID: UUID,
        before position: ReadingPosition,
        in context: ModelContext
    ) throws -> String {
        var parts: [String] = []

        if position.chapterIndex > 0 {
            let prior = FetchDescriptor<Chapter>(
                predicate: #Predicate {
                    $0.bookID == bookID && $0.index < position.chapterIndex
                },
                sortBy: [SortDescriptor(\.index)]
            )
            for chapter in try context.fetch(prior) {
                if let block = formattedBlock(for: chapter) {
                    parts.append(block)
                }
            }
        }

        if position.utf16Offset > 0 {
            let current = FetchDescriptor<Chapter>(
                predicate: #Predicate {
                    $0.bookID == bookID && $0.index == position.chapterIndex
                }
            )
            if let chapter = try context.fetch(current).first,
               let slice = partialText(of: chapter, throughUTF16Offset: position.utf16Offset) {
                let heading: String
                if let title = chapter.title, !title.isEmpty {
                    heading = title
                } else {
                    heading = "Chapter \(chapter.index + 1)"
                }
                parts.append("\(heading)\n\(slice)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private static func formattedBlock(for chapter: Chapter) -> String? {
        let text = chapter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let heading: String
        if let title = chapter.title, !title.isEmpty {
            heading = title
        } else {
            heading = "Chapter \(chapter.index + 1)"
        }
        return "\(heading)\n\(text)"
    }

    private static func partialText(
        of chapter: Chapter,
        throughUTF16Offset offset: Int
    ) -> String? {
        let utf16 = Array(chapter.text.utf16)
        let clamped = min(max(offset, 0), utf16.count)
        let slice = String(decoding: utf16[..<clamped], as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slice.isEmpty else { return nil }
        return slice
    }
}
