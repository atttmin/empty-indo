//
//  StudyView.swift
//  Empty
//

import SwiftUI

private enum StudyMode: String, CaseIterable {
    case vocab = "Vocabulary"
    case flashcards = "Flashcards"
}

/// iOS study hub: vocabulary and flashcard review.
struct StudyView: View {
    @State private var mode: StudyMode = .vocab

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Study mode", selection: $mode) {
                    ForEach(StudyMode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .vocab:
                    VocabReviewView()
                case .flashcards:
                    FlashcardsReviewView()
                }
            }
            .padding(.vertical)
            .navigationTitle("Study")
        }
    }
}