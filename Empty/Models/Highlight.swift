//
//  Highlight.swift
//  Empty
//

import Foundation
import SwiftData

/// Marker colors. Raw values are stable storage identifiers; rendering
/// decides the actual appearance per platform and theme. The reader UI
/// offers the design system's trio — 金 (yellow) / 朱 (vermilion) /
/// 青 (celadon); the other cases are legacy storage values that still
/// render.
nonisolated enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case vermilion
    case celadon

    /// The picker trio, in design order.
    static let readerChoices: [HighlightColor] = [.yellow, .vermilion, .celadon]

    var title: String {
        switch self {
        case .yellow: "金"
        case .vermilion: "朱"
        case .celadon: "青"
        case .green: "绿"
        case .blue: "蓝"
        case .pink: "粉"
        }
    }

    /// Underline tint (高亮改为底线染色，不再整块涂底).
    var hex: UInt32 {
        switch self {
        case .yellow: 0xE5C55E
        case .vermilion: 0xC0532F
        case .celadon: 0x5E8C7B
        case .green: 0x6FA56F
        case .blue: 0x5B85A8
        case .pink: 0xC97A8E
        }
    }
}

/// A reader-created highlight with an optional note, anchored to book text.
/// Synced store — this is the data a reading app must never lose.
///
/// Set `book` after inserting into a context (SwiftData relationships are
/// only safe to wire between inserted models).
@Model
final class Highlight {
    var id: UUID = UUID()
    var book: Book?

    // Flattened `TextAnchor` so queries can filter by position.
    var chapterIndex: Int = 0
    var startUTF16: Int = 0
    var endUTF16: Int = 0

    /// Verbatim snapshot of the highlighted text. Survives extraction-offset
    /// drift (re-anchoring searches for this near the stale offset) and feeds
    /// AI features (flashcards, cross-book memory) without re-reading files.
    var textSnapshot: String = ""

    var note: String?

    private var colorRawValue: String = HighlightColor.yellow.rawValue
    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRawValue) ?? .yellow }
        set { colorRawValue = newValue.rawValue }
    }

    var createdAt: Date = Date()

    var anchor: TextAnchor {
        get {
            TextAnchor(
                chapterIndex: chapterIndex,
                startUTF16: startUTF16,
                endUTF16: endUTF16
            )
        }
        set {
            chapterIndex = newValue.chapterIndex
            startUTF16 = newValue.startUTF16
            endUTF16 = newValue.endUTF16
        }
    }

    init(
        anchor: TextAnchor,
        textSnapshot: String,
        color: HighlightColor = .yellow,
        note: String? = nil
    ) {
        self.chapterIndex = anchor.chapterIndex
        self.startUTF16 = anchor.startUTF16
        self.endUTF16 = anchor.endUTF16
        self.textSnapshot = textSnapshot
        self.colorRawValue = color.rawValue
        self.note = note
    }
}
