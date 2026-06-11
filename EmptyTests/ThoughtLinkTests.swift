//
//  ThoughtLinkTests.swift
//  EmptyTests
//
//  活思维链接: insight parsing and the 不相关 negative-feedback rules.
//

import Foundation
import SwiftData
import Testing
@testable import Empty

struct ThoughtLinkInsightTests {
    @Test func parsesThemeAndWhyLines() {
        let parsed = ThoughtLinkFinder.parseInsight("""
        主题：不争之争
        为什么：两段都主张以退为进。柔弱是策略而非软弱。
        """)
        #expect(parsed.theme == "不争之争")
        #expect(parsed.why.contains("以退为进"))
    }

    @Test func unstructuredReplyBecomesWhy() {
        let parsed = ThoughtLinkFinder.parseInsight("这两段都在谈论放下控制。")
        #expect(parsed.theme == nil)
        #expect(parsed.why == "这两段都在谈论放下控制。")
    }
}

struct ThoughtLinkFeedbackTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "thoughtlink-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func dismissedPairNeverResurfaces() {
        let defaults = makeDefaults()
        let highlightID = UUID()
        #expect(!ThoughtLinkFeedback.isBlocked(
            passage: "段落甲", highlightID: highlightID, defaults: defaults
        ))

        ThoughtLinkFeedback.dismiss(
            passage: "段落甲", highlightID: highlightID, defaults: defaults
        )
        #expect(ThoughtLinkFeedback.isBlocked(
            passage: "段落甲", highlightID: highlightID, defaults: defaults
        ))
        // A different passage against the same highlight still allowed
        // after one dismissal…
        #expect(!ThoughtLinkFeedback.isBlocked(
            passage: "段落乙", highlightID: highlightID, defaults: defaults
        ))
    }

    @Test func twoDismissalsQuietTheHighlightEntirely() {
        let defaults = makeDefaults()
        let highlightID = UUID()
        ThoughtLinkFeedback.dismiss(
            passage: "段落甲", highlightID: highlightID, defaults: defaults
        )
        ThoughtLinkFeedback.dismiss(
            passage: "段落乙", highlightID: highlightID, defaults: defaults
        )
        // …but two dismissals anywhere silence the highlight for all
        // passages (同主题降频).
        #expect(ThoughtLinkFeedback.isBlocked(
            passage: "段落丙", highlightID: highlightID, defaults: defaults
        ))
    }
}

@MainActor
struct ThoughtLinkMemoryRouteTests {
    @Test func linkCardsSurfaceThroughReaderMemoryWhenNoHighlightsMatch() throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext

        let priorBook = Book(title: "道德经", format: .epub)
        let currentBook = Book(title: "马斯克传", format: .epub)
        context.insert(priorBook)
        context.insert(currentBook)
        let card = StudyCardEntry(
            question: "不争之争：道德经与马斯克传的呼应",
            answer: "两者都把退让看作竞争策略。",
            source: "道德经 ⟷ 马斯克传",
            kind: .link
        )
        card.book = priorBook
        context.insert(card)
        try context.save()

        let found = try ThoughtLinkFinder(modelContext: context).findLink(
            passage: "这一段讨论以退让换取长期竞争优势。",
            book: currentBook,
            chapterIndex: 0
        )
        let link = try #require(found)

        #expect(link.relatedSource == "道德经 ⟷ 马斯克传")
        #expect(link.relatedText.contains("退让"))
        #expect(link.explanation.contains("读者记忆"))
        _ = container
    }
}
