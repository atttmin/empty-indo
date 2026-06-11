//
//  StudyCardEntry.swift
//  Empty
//

import Foundation
import SwiftData

/// An AI-generated Q&A study card, usually sourced from a highlight.
/// Uses the same Ebbinghaus ladder as `VocabEntry`.
@Model
final class StudyCardEntry {
    static let ladderDays = VocabEntry.ladderDays

    var id: UUID = UUID()
    var question: String = ""
    var answer: String = ""
    /// e.g. "Walden · Ch.2"
    var source: String?
    var highlightID: UUID?
    var book: Book?

    var stage: Int = 1
    var dueAt: Date = Date()
    var createdAt: Date = Date()
    var lastReviewedAt: Date?

    init(
        question: String,
        answer: String,
        source: String? = nil,
        highlightID: UUID? = nil
    ) {
        self.question = question
        self.answer = answer
        self.source = source
        self.highlightID = highlightID
    }

    private var clampedStage: Int {
        min(max(stage, 1), Self.ladderDays.count)
    }

    var intervalDays: Int {
        Self.ladderDays[clampedStage - 1]
    }

    func applyReview(_ grade: VocabReviewGrade, now: Date = Date()) {
        switch grade {
        case .forgot:
            stage = 1
        case .fuzzy:
            stage = clampedStage
        case .good:
            stage = min(clampedStage + 1, Self.ladderDays.count)
        }
        lastReviewedAt = now
        dueAt = Calendar.current.date(byAdding: .day, value: intervalDays, to: now)
            ?? now.addingTimeInterval(Double(intervalDays) * 86_400)
    }
}