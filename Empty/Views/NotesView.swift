//
//  NotesView.swift
//  Empty
//

import SwiftData
import SwiftUI

/// Cross-platform highlight cards across the whole library.
struct NotesView: View {
    @Environment(\.emptyPalette) private var palette
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]

    @State private var filterBookID: UUID?

    private var filterableBooks: [Book] {
        var seen = Set<UUID>()
        return highlights.compactMap { highlight in
            guard let book = highlight.book, seen.insert(book.id).inserted else {
                return nil
            }
            return book
        }
    }

    private var visibleHighlights: [Highlight] {
        guard let filterBookID else { return highlights }
        return highlights.filter { $0.book?.id == filterBookID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes Yet", systemImage: "note.text")
                    } description: {
                        Text("Highlights you make while reading appear here as cards.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            filterRow
                            LazyVStack(spacing: 12) {
                                ForEach(visibleHighlights) { highlight in
                                    highlightCard(highlight)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Notes")
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", bookID: nil)
                ForEach(filterableBooks) { book in
                    filterChip(title: book.title, bookID: book.id)
                }
            }
        }
    }

    private func filterChip(title: String, bookID: UUID?) -> some View {
        let selected = filterBookID == bookID
        return Button(title) { filterBookID = bookID }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                selected ? palette.accentSoft : palette.card,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? palette.accent.opacity(0.4) : palette.line,
                    lineWidth: 1
                )
            )
    }

    private func highlightCard(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let book = highlight.book {
                Text(book.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }
            Text(highlight.textSnapshot)
                .font(.body)
                .foregroundStyle(palette.ink)
                .lineSpacing(4)
            Text("Chapter \(highlight.chapterIndex + 1)")
                .font(.caption2)
                .foregroundStyle(palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .emptyCard(palette, radius: 12)
    }
}