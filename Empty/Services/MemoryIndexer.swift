//
//  MemoryIndexer.swift
//  Empty
//

import Foundation
import SwiftData

/// Local semantic index for `MemoryItem` rows. Keeps vectors in the local
/// store so cross-book memory recall can blend lexical and semantic
/// routes without recomputing every candidate on each query.
@MainActor
enum MemoryEmbeddingIndex {
    static func syncEmbeddings(
        for itemIDs: Set<UUID>? = nil,
        in modelContext: ModelContext
    ) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<MemoryItem>())
        let candidates = items.filter { item in
            item.isUserConfirmed && (itemIDs == nil || itemIDs?.contains(item.id) == true)
        }
        let allowedIDs = Set(candidates.map(\.id))

        let embeddings = try modelContext.fetch(FetchDescriptor<MemoryEmbedding>())
        var byItemID: [UUID: MemoryEmbedding] = [:]
        byItemID.reserveCapacity(embeddings.count)

        var touched = 0
        for entry in embeddings {
            if let itemIDs, !itemIDs.contains(entry.itemID) {
                byItemID[entry.itemID] = entry
                continue
            }
            if !allowedIDs.contains(entry.itemID) {
                modelContext.delete(entry)
                touched += 1
                continue
            }
            byItemID[entry.itemID] = entry
        }

        for item in candidates {
            let text = memoryText(for: item)
            guard let query = SemanticScorer.queryVector(for: text) else {
                if let stale = byItemID[item.id] {
                    modelContext.delete(stale)
                    touched += 1
                }
                continue
            }
            if let entry = byItemID[item.id],
               entry.sourceUpdatedAt >= item.updatedAt,
               entry.languageTag == query.languageTag,
               entry.embeddingVector != nil {
                continue
            }
            let entry = byItemID[item.id] ?? MemoryEmbedding(itemID: item.id, sourceUpdatedAt: item.updatedAt)
            if byItemID[item.id] == nil {
                modelContext.insert(entry)
                byItemID[item.id] = entry
            }
            entry.sourceUpdatedAt = item.updatedAt
            entry.setEmbedding(vector: query.vector, languageTag: query.languageTag)
            touched += 1
        }

        guard touched > 0 else { return 0 }
        try modelContext.save()
        return touched
    }

    static func memoryText(for item: MemoryItem) -> String {
        let tags = item.tags.joined(separator: " ")
        return [item.title, item.body, tags]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

@MainActor
struct MemoryIndexer {
    let modelContext: ModelContext

    func indexAll() throws -> Int {
        try MemoryEmbeddingIndex.syncEmbeddings(in: modelContext)
    }

    func index(itemIDs: Set<UUID>) throws -> Int {
        try MemoryEmbeddingIndex.syncEmbeddings(for: itemIDs, in: modelContext)
    }
}
