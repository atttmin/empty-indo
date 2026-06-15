//
//  SelectionInsightSheet.swift
//  Empty
//

import SwiftUI

nonisolated enum SelectionInsightKind: String, Equatable, Sendable {
    case explain
    case translate

    var title: String {
        switch self {
        case .explain: "朱批 · 划词解释"
        case .translate: "朱批 · 划词翻译"
        }
    }

    func question(for selection: ReaderSelection) -> String {
        switch self {
        case .explain:
            return """
            Explain the selected passage to a thoughtful reader. Use the surrounding context only when needed to clarify references or tone. Reply in Chinese with etymology or nuance when helpful.
            """
        case .translate:
            if selection.isLikelyWordOrShortPhrase {
                return """
                Translate ONLY the selected word or short phrase into natural Chinese as used here. Do not translate the surrounding context. If it is a single word, give the shortest accurate Chinese gloss first, then at most one short nuance note if needed.
                """
            }
            return """
            Translate ONLY the selected passage into natural Chinese, preserving literary tone. Use the surrounding context only to disambiguate references. Do not add explanation.
            """
        }
    }

    func groundedText(for selection: ReaderSelection) -> String {
        switch self {
        case .explain:
            return selection.contextualText
        case .translate:
            return selection.trimmedText
        }
    }
}

extension ReaderSelection {
    nonisolated var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var contextualText: String {
        [prefix, text, suffix]
            .joined()
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var isLikelyWordOrShortPhrase: Bool {
        let trimmed = trimmedText
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("\n") { return false }
        if trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?。！？；;:")) != nil {
            return false
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        return words.count <= 4 && trimmed.count <= 40
    }
}

nonisolated struct ReaderSelectionInsight: Identifiable, Equatable, Sendable {
    let id = UUID()
    var kind: SelectionInsightKind
    var subject: String
    var body: String

    var title: String { kind.title }

    static func make(kind: SelectionInsightKind, subject: String, body: String) -> ReaderSelectionInsight {
        ReaderSelectionInsight(kind: kind, subject: subject, body: body)
    }
}

struct SelectionInsightSheet<Actions: View>: View {
    let insight: ReaderSelectionInsight
    let actions: Actions

    init(insight: ReaderSelectionInsight, @ViewBuilder actions: () -> Actions) {
        self.insight = insight
        self.actions = actions()
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text("单独看解释，不再压住正文。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink3)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("×")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink3)
                        .frame(width: 28, height: 28)
                        .background(palette.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("“\(insight.subject)”")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(palette.ink2)
                .lineLimit(4)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.side, in: RoundedRectangle(cornerRadius: 12))

            ScrollView {
                Text(insight.body)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(6)
                    .foregroundStyle(palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180)
            .padding(12)
            .background(palette.window, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.line2, lineWidth: 1)
            )

            HStack(spacing: 10) {
                actions
                Spacer()
                Button("收起") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.ink3)
            }
        }
        .padding(20)
        .background(palette.window)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 560, minHeight: 420)
        #endif
    }
}
