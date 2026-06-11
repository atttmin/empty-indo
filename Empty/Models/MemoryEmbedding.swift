//
//  MemoryEmbedding.swift
//  Empty
//

import Foundation
import SwiftData

/// Local-only sentence embedding for a synced `MemoryItem`. Cross-store by
/// `itemID` only: the vector is re-derivable and never leaves the device.
@Model
final class MemoryEmbedding {
    #Index<MemoryEmbedding>([\.itemID])

    var itemID: UUID
    /// `MemoryItem.updatedAt` at the moment this vector was produced.
    var sourceUpdatedAt: Date
    var languageTag: String?
    var embedding: Data?
    var updatedAt: Date = Date()

    init(itemID: UUID, sourceUpdatedAt: Date, languageTag: String? = nil) {
        self.itemID = itemID
        self.sourceUpdatedAt = sourceUpdatedAt
        self.languageTag = languageTag
    }

    var embeddingVector: [Float]? {
        guard let embedding, !embedding.isEmpty else { return nil }
        return embedding.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return nil }
            let count = bytes.count / MemoryLayout<Float>.size
            let buffer = base.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: buffer, count: count))
        }
    }

    func setEmbedding(vector: [Float], languageTag: String? = nil) {
        var mutable = vector
        embedding = Data(bytes: &mutable, count: mutable.count * MemoryLayout<Float>.size)
        self.languageTag = languageTag
        updatedAt = Date()
    }
}
