//
//  SemanticScorer.swift
//  Empty
//

import Foundation
import NaturalLanguage

/// On-device sentence-embedding relevance, language-aware: the model is
/// picked from the text's dominant language (Chinese books embed with the
/// zh-Hans model, not the English one). Falls back silently when
/// `NLEmbedding` is unavailable (simulator, models-not-downloaded,
/// unsupported language).
nonisolated enum SemanticScorer {
    /// A query embedded together with the model that produced it. Cosine
    /// comparisons are only meaningful against chunk vectors from the same
    /// model (`Chunk.embeddingLanguage`).
    struct EmbeddedQuery {
        let vector: [Float]
        let languageTag: String
    }

    /// Whether the device can produce sentence embeddings for `text`.
    static func isAvailable(for text: String = "") -> Bool {
        embeddingModel(for: text) != nil
    }

    /// The dominant language of `text`, defaulting to English when the
    /// recognizer is unsure (very short queries, mixed scripts).
    static func dominantLanguage(of text: String) -> NLLanguage {
        NLLanguageRecognizer.dominantLanguage(for: text) ?? .english
    }

    /// The sentence-embedding model for `text`'s language, falling back to
    /// English (the most broadly trained model) when the detected language
    /// has no on-device model.
    static func embeddingModel(for text: String) -> (embedding: NLEmbedding, languageTag: String)? {
        let language = dominantLanguage(of: text)
        if let model = NLEmbedding.sentenceEmbedding(for: language) {
            return (model, language.rawValue)
        }
        if language != .english,
           let fallback = NLEmbedding.sentenceEmbedding(for: .english) {
            return (fallback, NLLanguage.english.rawValue)
        }
        return nil
    }

    /// Embeds `text` with its language's model, or `nil` if no model is
    /// available or the text is empty.
    static func queryVector(for text: String) -> EmbeddedQuery? {
        guard !text.isEmpty,
              let (embedding, languageTag) = embeddingModel(for: text),
              let vector = embedding.vector(for: text) else {
            return nil
        }
        return EmbeddedQuery(
            vector: vector.map { Float($0) },
            languageTag: languageTag
        )
    }

    /// Cosine similarity of two same-length Float vectors, 0…1.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in a.indices {
            let av = Double(a[i])
            let bv = Double(b[i])
            dot += av * bv
            normA += av * av
            normB += bv * bv
        }
        let denom = sqrt(normA * normB)
        return denom == 0 ? 0 : dot / denom
    }
}
