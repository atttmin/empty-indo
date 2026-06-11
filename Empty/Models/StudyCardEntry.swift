//
//  StudyCardEntry.swift
//  Empty
//

import Foundation
import SwiftData

/// What kind of card a `StudyCardEntry` is — the prototype's 复习卡 /
/// 问答卡 / 链接卡. Stored raw so CloudKit records stay plain strings.
nonisolated enum StudyCardKind: String, CaseIterable, Sendable {
    /// Spaced-repetition Q&A generated from a highlight (复习卡).
    case review
    /// A companion-chat exchange the reader chose to keep (问答卡).
    case qa
    /// A saved thought link between two passages (链接卡).
    case link
}

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

    /// Raw `StudyCardKind`; optional so records created before the field
    /// existed (and CloudKit-synced ones) default to `.review`.
    private var kindRawValue: String?
    var kind: StudyCardKind {
        get { kindRawValue.flatMap(StudyCardKind.init(rawValue:)) ?? .review }
        set { kindRawValue = newValue.rawValue }
    }

    var stage: Int = 1
    var dueAt: Date = Date()
    var createdAt: Date = Date()
    var lastReviewedAt: Date?

    init(
        question: String,
        answer: String,
        source: String? = nil,
        highlightID: UUID? = nil,
        kind: StudyCardKind = .review
    ) {
        self.question = question
        self.answer = answer
        self.source = source
        self.highlightID = highlightID
        self.kindRawValue = kind.rawValue
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