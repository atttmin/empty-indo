//
//  VocabReviewView.swift
//  Empty
//

import SwiftData
import SwiftUI

/// Cross-platform spaced-repetition review for vocabulary entries.
struct VocabReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.emptyPalette) private var palette
    @Query(sort: \VocabEntry.dueAt) private var entries: [VocabEntry]

    @State private var now = Date()
    @State private var reviewIndex = 0
    @State private var revealed = false

    private var dueEntries: [VocabEntry] {
        entries.filter { $0.dueAt <= now }
    }

    private var currentEntry: VocabEntry? {
        guard !dueEntries.isEmpty, reviewIndex < dueEntries.count else { return nil }
        return dueEntries[reviewIndex]
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No Vocabulary Yet", systemImage: "character.book.closed")
                } description: {
                    Text("Look up words while reading to add them here.")
                }
            } else if let entry = currentEntry {
                reviewCard(entry)
            } else if !dueEntries.isEmpty {
                completedState
            } else {
                ContentUnavailableView {
                    Label("All Caught Up", systemImage: "checkmark.circle")
                } description: {
                    Text("\(entries.count) words scheduled — none due today.")
                }
            }
        }
        .onAppear { now = Date() }
    }

    private func reviewCard(_ entry: VocabEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Review \(reviewIndex + 1) / \(dueEntries.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Stage \(entry.stage) · \(entry.intervalDays)d")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.word)
                .font(.largeTitle.weight(.bold))

            if let phonetic = entry.phonetic {
                Text(phonetic)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let sentence = entry.sentence, !sentence.isEmpty {
                Text("\"\(sentence)\"")
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
            }

            if revealed {
                Divider()
                Text(entry.meaning)
                    .font(.body.weight(.semibold))
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                gradeButtons(for: entry)
            } else {
                Button("Reveal Meaning") {
                    withAnimation { revealed = true }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }
        }
        .padding()
        .emptyCard(palette, radius: 16)
    }

    private var completedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(palette.accent)
            Text("Today's vocabulary review complete")
                .font(.headline)
            Button("Review Again") {
                reviewIndex = 0
                revealed = false
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private func gradeButtons(for entry: VocabEntry) -> some View {
        HStack(spacing: 10) {
            gradeButton("Forgot", grade: .forgot, entry: entry)
            gradeButton("Fuzzy", grade: .fuzzy, entry: entry)
            gradeButton("Good", grade: .good, entry: entry)
        }
    }

    private func gradeButton(
        _ title: String,
        grade: VocabReviewGrade,
        entry: VocabEntry
    ) -> some View {
        Button(title) {
            entry.applyReview(grade, now: now)
            try? modelContext.save()
            revealed = false
            reviewIndex += 1
        }
        .buttonStyle(.bordered)
    }
}