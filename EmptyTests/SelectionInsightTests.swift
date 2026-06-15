//
//  SelectionInsightTests.swift
//  EmptyTests
//

import Testing
@testable import Empty

struct SelectionInsightTests {
    @Test func kindProvidesStableTitlesAndPrompts() {
        #expect(SelectionInsightKind.explain.title == "朱批 · 划词解释")
        #expect(SelectionInsightKind.translate.title == "朱批 · 划词翻译")
        let sentence = ReaderSelection(text: "The pond was calm.", prefix: "", suffix: "")
        #expect(SelectionInsightKind.explain.question(for: sentence).contains("Explain the selected passage"))
        #expect(SelectionInsightKind.translate.question(for: sentence).contains("Translate ONLY the selected passage"))
    }
    @Test func translateWordUsesWordOnlyAsGroundingAndContextOnlyForDisambiguation() {
        let selection = ReaderSelection(
            text: "resignation",
            prefix: "A kind of ",
            suffix: " in the face of fate."
        )

        let question = SelectionInsightKind.translate.question(for: selection)
        let grounded = SelectionInsightKind.translate.groundedText(for: selection)

        #expect(question.contains("selected word or short phrase"))
        #expect(question.contains("Do not translate the surrounding context"))
        #expect(grounded == "resignation")
    }

    @Test func explainStillUsesSurroundingContextAsGrounding() {
        let selection = ReaderSelection(
            text: "he meant to live deep",
            prefix: "Thoreau says ",
            suffix: " and suck out all the marrow of life."
        )

        let question = SelectionInsightKind.explain.question(for: selection)
        let grounded = SelectionInsightKind.explain.groundedText(for: selection)

        #expect(question.contains("surrounding context"))
        #expect(grounded.contains("Thoreau says"))
        #expect(grounded.contains("marrow of life"))
    }

    @Test func insightPreservesSelectionAndAnswer() {
        let insight = ReaderSelectionInsight.make(
            kind: .explain,
            subject: "删去噪音，只留本质",
            body: "这里强调减法不是消极，而是把注意力留给最重要的东西。"
        )

        #expect(insight.title == "朱批 · 划词解释")
        #expect(insight.subject == "删去噪音，只留本质")
        #expect(insight.body.contains("注意力"))
    }
}
