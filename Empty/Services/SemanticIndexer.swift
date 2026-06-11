//
//  SemanticIndexer.swift
//  Empty
//

import NaturalLanguage
import SwiftData

/// Background actor that computes on-device sentence embeddings for every
/// `Chunk` that lacks one.  Runs off the main thread so the 512-dim vector
/// math never blocks the reader UI.
///
/// Usage:
///     let indexer = SemanticIndexer(modelContainer: container)
///     let processed = try await indexer.indexChunks(for: bookID)
@ModelActor
actor SemanticIndexer {
    /// Embeds all un-indexed chunks for `bookID`, picking the embedding
    /// model from each chunk's language (Chinese text embeds with the
    /// zh-Hans model). Returns the number of chunks successfully processed
    /// (0 if no `NLEmbedding` model is available).
    func indexChunks(for bookID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<Chunk>(
            predicate: #Predicate { chunk in
                chunk.bookID == bookID && chunk.embedding == nil
            }
        )
        let chunks = try modelContext.fetch(descriptor)
        guard !chunks.isEmpty else { return 0 }

        var processed = 0
        for chunk in chunks {
            guard let (embedding, languageTag) = SemanticScorer.embeddingModel(for: chunk.text),
                  let vector = embedding.vector(for: chunk.text) else { continue }
            chunk.setEmbedding(vector: vector, languageTag: languageTag)
            processed += 1
        }
        guard processed > 0 else { return 0 }

        try modelContext.save()
        return processed
    }
}
