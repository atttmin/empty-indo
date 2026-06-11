//
//  ChunkRetriever.swift
//  Empty
//

import Foundation
import SwiftData

/// Spoiler-safe retrieval: ranks the chunks the reader has actually passed
/// (`Chunk.fullyReadPredicate`).  When sentence embeddings are available the
/// score blends cosine similarity (70 %) with lexical overlap (30 %) so
/// conceptual questions ("why did he leave?") still hit passages that don't
/// share exact words; when embeddings are missing it falls back to pure
/// lexical scoring.
@MainActor
struct ChunkRetriever {
    let modelContext: ModelContext

    /// Top-`limit` fully-read chunks for `question`, lexically ranked
    /// (recency breaks ties). When nothing matches lexically — "总结一下现在
    /// 的情况" shares no tokens with anything — falls back to the most
    /// recently read chunks so grounded answering still has context.
    func retrieve(
        question: String,
        bookID: UUID,
        position: ReadingPosition,
        limit: Int = 8
    ) throws -> [Chunk] {
        let candidates = try modelContext.fetch(
            FetchDescriptor<Chunk>(
                predicate: Chunk.fullyReadPredicate(bookID: bookID, position: position)
            )
        )
        guard !candidates.isEmpty else { return [] }

        let query = SemanticScorer.queryVector(for: question)

        var scored: [(chunk: Chunk, score: Double)] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            let lexical = LexicalScorer.score(query: question, text: candidate.text)
            // Blend only when both sides were embedded by the same language
            // model — vectors from different models live in different
            // spaces, and un-indexed chunks must not get penalised.
            let score: Double
            if let query,
               candidate.embeddingLanguage == query.languageTag,
               let cv = candidate.embeddingVector {
                let semantic = SemanticScorer.cosineSimilarity(query.vector, cv)
                score = semantic * 0.7 + lexical * 0.3
            } else {
                score = lexical
            }
            if score > 0 {
                scored.append((candidate, score))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.chunk.ordinal > rhs.chunk.ordinal
            }
            return lhs.score > rhs.score
        }

        if scored.isEmpty {
            let recent = candidates
                .sorted { (a: Chunk, b: Chunk) in a.ordinal > b.ordinal }
                .prefix(limit)
            return recent.reversed()
        }
        return scored.prefix(limit).map { $0.chunk }
    }
}
