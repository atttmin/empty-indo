//
//  StudyCardStore.swift
//  Empty
//

import Foundation
import SwiftData

@MainActor
struct StudyCardStore {
    let modelContext: ModelContext

    func generate(
        from highlight: Highlight,
        book: Book,
        maxCount: Int = 3
    ) async throws -> [StudyCardEntry] {
        let resolution = AIProviderSettings.load().resolveUsableService()
        let cards = try await resolution.service.flashcards(
            from: highlight.textSnapshot,
            maxCount: maxCount
        )
        guard !cards.isEmpty else { return [] }

        let source = "\(book.title) · 第 \(highlight.chapterIndex + 1) 章"
        var created: [StudyCardEntry] = []
        created.reserveCapacity(cards.count)
        for card in cards {
            let entry = StudyCardEntry(
                question: card.question,
                answer: card.answer,
                source: source,
                highlightID: highlight.id
            )
            entry.book = book
            modelContext.insert(entry)
            created.append(entry)
        }
        try modelContext.save()
        return created
    }

    func cards(for book: Book? = nil) throws -> [StudyCardEntry] {
        if let book {
            let bookID = book.id
            return try modelContext.fetch(
                FetchDescriptor<StudyCardEntry>(
                    predicate: #Predicate { $0.book?.id == bookID },
                    sortBy: [SortDescriptor(\.dueAt)]
                )
            )
        }
        return try modelContext.fetch(
            FetchDescriptor<StudyCardEntry>(sortBy: [SortDescriptor(\.dueAt)])
        )
    }

    func delete(_ card: StudyCardEntry) throws {
        modelContext.delete(card)
        try modelContext.save()
    }
}