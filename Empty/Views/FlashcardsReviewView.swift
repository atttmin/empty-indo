//
//  FlashcardsReviewView.swift
//  Empty
//

import SwiftData
import SwiftUI

/// Spaced-repetition review for AI-generated study cards.
struct FlashcardsReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.emptyPalette) private var palette
    @Query(sort: \StudyCardEntry.dueAt) private var cards: [StudyCardEntry]

    var bookFilter: Book?
    var accentColor: Color?
    var emptyTitle: String = "No Flashcards Yet"
    var emptyDescription: String = "Generate study cards from highlights while reading."

    @State private var now = Date()
    @State private var reviewIndex = 0
    @State private var revealed = false

    private var visibleCards: [StudyCardEntry] {
        guard let bookFilter else { return cards }
        return cards.filter { $0.book?.id == bookFilter.id }
    }

    private var dueCards: [StudyCardEntry] {
        visibleCards.filter { $0.dueAt <= now }
    }

    private var currentCard: StudyCardEntry? {
        guard !dueCards.isEmpty, reviewIndex < dueCards.count else { return nil }
        return dueCards[reviewIndex]
    }

    private var resolvedAccent: Color {
        accentColor ?? palette.accent
    }

    var body: some View {
        Group {
            if visibleCards.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "rectangle.on.rectangle.angled")
                } description: {
                    Text(emptyDescription)
                }
            } else if let card = currentCard {
                reviewCard(card)
            } else if !dueCards.isEmpty {
                completedState
            } else {
                ContentUnavailableView {
                    Label("All Caught Up", systemImage: "checkmark.circle")
                } description: {
                    Text("\(visibleCards.count) cards scheduled — none due today.")
                }
            }
        }
        .onAppear { now = Date() }
    }

    private func reviewCard(_ card: StudyCardEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Flashcard \(reviewIndex + 1) / \(dueCards.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let source = card.source {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(card.question)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if revealed {
                Divider()
                Text(card.answer)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                gradeButtons(for: card)
            } else {
                Button("Reveal Answer") {
                    withAnimation { revealed = true }
                }
                .buttonStyle(.borderedProminent)
                .tint(resolvedAccent)
            }
        }
        .padding()
        .emptyCard(palette, radius: 16)
    }

    private var completedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(resolvedAccent)
            Text("Today's flashcards complete")
                .font(.headline)
            Button("Review Again") {
                reviewIndex = 0
                revealed = false
                now = Date()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func gradeButtons(for card: StudyCardEntry) -> some View {
        HStack(spacing: 10) {
            gradeButton("Forgot", grade: .forgot, card: card)
            gradeButton("Fuzzy", grade: .fuzzy, card: card)
            gradeButton("Good", grade: .good, card: card)
        }
    }

    private func gradeButton(
        _ title: String,
        grade: VocabReviewGrade,
        card: StudyCardEntry
    ) -> some View {
        Button(title) {
            card.applyReview(grade, now: now)
            try? modelContext.save()
            revealed = false
            reviewIndex += 1
        }
        .buttonStyle(.bordered)
    }
}