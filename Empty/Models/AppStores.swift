//
//  AppStores.swift
//  Empty
//

import Foundation
import SwiftData

/// Two-store local persistence layout. The split is the architecture:
/// keep the reader's small authored data separate from bulky derived book content.
///
/// - **Reader data** — library metadata, reading positions, highlights, notes,
///   vocab, study cards, bookmarks, and ReaderMemory. Small, precious, and the
///   future backup/export surface.
/// - **Local derived data** — chapter text, chunks, translation cache, and
///   on-device semantic vectors. Rebuildable from imported files or reader data.
///
/// Cross-store references go through `Book.id` only. SwiftData cannot relate
/// models across stores, and that constraint is load-bearing: it keeps imported
/// book content out of the future notes-backup pipeline by construction.
enum AppStores {
    /// Kept as `Synced` to reopen existing local SQLite files created before
    /// the cloud path was removed. Despite the historical name, this store is
    /// local-only.
    private static let readerDataStoreName = "Synced"

    static let readerDataSchema = Schema([
        Book.self,
        Highlight.self,
        ReadingSession.self,
        VocabEntry.self,
        StudyCardEntry.self,
        Bookmark.self,
        MemoryItem.self,
    ])

    static let localSchema = Schema([
        Chapter.self,
        Chunk.self,
        ParagraphTranslation.self,
        MemoryEmbedding.self,
    ])

    enum StorePlacement {
        case readerData
        case local
    }

    static func placement(for model: Any.Type) -> StorePlacement? {
        switch model {
        case is Book.Type, is Highlight.Type, is ReadingSession.Type,
             is VocabEntry.Type, is StudyCardEntry.Type, is Bookmark.Type,
             is MemoryItem.Type:
            .readerData
        case is Chapter.Type, is Chunk.Type, is ParagraphTranslation.Type,
             is MemoryEmbedding.Type:
            .local
        default:
            nil
        }
    }

    /// - Parameter ephemeral: throwaway per-container stores for tests and
    ///   previews. Not `isStoredInMemoryOnly`: that backs every store with
    ///   the same `/dev/null` pseudo-file, and concurrent containers
    ///   (parallel tests) trip over the shared SQLite locks. Unique temp
    ///   files keep ephemeral containers fully isolated.
    static func makeContainer(ephemeral: Bool = false) throws -> ModelContainer {
        let readerData: ModelConfiguration
        let local: ModelConfiguration
        if ephemeral {
            let base = FileManager.default.temporaryDirectory
                .appending(path: "EmptyStores-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            readerData = ModelConfiguration(
                readerDataStoreName,
                schema: readerDataSchema,
                url: base.appending(path: "Synced.store"),
                cloudKitDatabase: .none
            )
            local = ModelConfiguration(
                "Local",
                schema: localSchema,
                url: base.appending(path: "Local.store"),
                cloudKitDatabase: .none
            )
        } else {
            readerData = ModelConfiguration(
                readerDataStoreName,
                schema: readerDataSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            local = ModelConfiguration(
                "Local",
                schema: localSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }
        let allModels = Schema([
            Book.self,
            Highlight.self,
            ReadingSession.self,
            VocabEntry.self,
            StudyCardEntry.self,
            Bookmark.self,
            MemoryItem.self,
            Chapter.self,
            Chunk.self,
            ParagraphTranslation.self,
            MemoryEmbedding.self,
        ])
        return try ModelContainer(for: allModels, configurations: readerData, local)
    }
}
