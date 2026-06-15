//
//  CompanionModelTests.swift
//  EmptyTests
//

import Foundation
import SwiftData
import Testing
@testable import Empty

@MainActor
struct CompanionModelTests {
    @Test func themePassagesUseOnlyAnsweredQuestions() {
        let messages: [CompanionModel.Message] = [
            .init(role: .ai, text: "欢迎回来"),
            .init(role: .user, text: "这一段在说什么？"),
            .init(role: .ai, text: "它在收束论点。", question: "这一段在说什么？"),
            .init(role: .ai, text: "减法是一种纪律。", question: "为什么一直谈减法？"),
        ]

        let passages = CompanionModel.themePassages(from: messages)

        #expect(passages.count == 2)
        #expect(passages[0].text.contains("Q: 这一段在说什么？"))
        #expect(passages[1].text.contains("Q: 为什么一直谈减法？"))
    }

    @Test func followUpQuestionKeepsLocalExcerptInsteadOfTinyPrefix() {
        let text = String(repeating: "甲", count: 70)
            + "关键尾巴"
            + String(repeating: "乙", count: 70)

        let question = CompanionModel.followUpQuestion(about: text, maxCharacters: 120)

        #expect(question.hasPrefix("关于这段原文："))
        #expect(question.contains("关键尾巴"))
        #expect(question.contains(String(repeating: "乙", count: 20)))
        #expect(question.hasSuffix("…」"))
    }

    @Test func transcriptPreludeUsesBookHeadingReadBoundaryAndFocusText() throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        let book = Book(title: "Walden", format: .epub)
        context.insert(book)
        context.insert(Chapter(bookID: book.id, index: 0, title: "Economy", text: "前章已经读完。"))
        context.insert(Chapter(bookID: book.id, index: 1, title: "Where I Lived", text: "此处已经读到这里，后面还没读。"))
        try context.save()

        let offset = "此处已经读到这里".utf16.count
        let prelude = try CompanionModel.transcriptPrelude(
            for: book,
            position: ReadingPosition(chapterIndex: 1, utf16Offset: offset),
            focusText: "he meant to live deep",
            modelContext: context
        )

        let resolved = try #require(prelude)
        #expect(resolved.contains("当前书: 《Walden》"))
        #expect(resolved.contains("当前读到: Where I Lived"))
        #expect(resolved.contains("读者此刻想追问的原文"))
        #expect(resolved.contains("he meant to live deep"))
        #expect(resolved.contains("前章已经读完。"))
        #expect(resolved.contains("此处已经读到这里"))
        #expect(!resolved.contains("后面还没读"))
    }
    @Test func sendUsesFocusTextAndAnnotatesReplyContext() async throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        let book = Book(title: "Walden", format: .epub)
        context.insert(book)
        context.insert(Chapter(bookID: book.id, index: 0, title: "Economy", text: "He meant to live deep and suck out all the marrow of life."))
        try context.save()

        let service = ScriptedThemeService(response: "这里在强调把注意力压到生活的骨头上。")
        let model = CompanionModel(resolveUsableService: { _ in
            (service: service, provider: AIProviderRegistry.localProvider, fellBack: false)
        })
        model.draft = "这句在说什么？"
        model.draftFocusText = "he meant to live deep"

        model.send(
            book: book,
            position: ReadingPosition(chapterIndex: 0, utf16Offset: "He meant to live deep".utf16.count),
            modelContext: context
        )
        await waitUntilSettled(model)

        #expect(model.draft.isEmpty)
        #expect(model.draftFocusText == nil)
        let reply = try #require(model.messages.last)
        #expect(reply.role == .ai)
        #expect(reply.focusText == "he meant to live deep")
        #expect(reply.source?.contains("Walden") == true)
        #expect(reply.citation == "he meant to live deep")
        #expect(reply.question == "这句在说什么？")
    }

    @Test func sendWithoutReadableContextStopsBeforeCallingAI() async throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        let book = Book(title: "Walden", format: .epub)
        context.insert(book)
        context.insert(Chapter(bookID: book.id, index: 0, title: "Economy", text: "Unread so far."))
        try context.save()

        let service = ScriptedThemeService(response: "unused")
        let model = CompanionModel(resolveUsableService: { _ in
            (service: service, provider: AIProviderRegistry.localProvider, fellBack: false)
        })
        model.draft = "这句在说什么？"
        model.draftFocusText = "Unread so far"

        model.send(
            book: book,
            position: ReadingPosition(chapterIndex: 0, utf16Offset: 0),
            modelContext: context
        )
        await waitUntilSettled(model)

        let reply = try #require(model.messages.last)
        #expect(reply.text.contains("先往后读一点"))
        #expect(service.seenTranscripts.isEmpty)
    }
    @Test func analysisSummaryAndPassageEvidenceBlocksReflectDirectEvidence() throws {
        let container = try AppStores.makeContainer(ephemeral: true)
        let context = container.mainContext
        let book = Book(title: "Walden", format: .epub)
        context.insert(book)
        let chapter = Chapter(
            bookID: book.id,
            index: 0,
            title: "Economy",
            text: "作者想把生活压到骨头上，只留下最硬的部分。"
        )
        context.insert(chapter)
        try context.save()
        _ = try BookIndexer(modelContext: context).ensureChunks(for: book)

        let chunk = try #require(context.fetch(FetchDescriptor<Chunk>()).first)
        let blocks = CompanionModel.passageEvidenceBlocks(from: [chunk], bookTitle: book.title)
        let summary = CompanionModel.analysisSummary(
            source: "《Walden》 · Economy · ¶1",
            steps: [],
            evidenceBlocks: blocks
        )

        #expect(summary == "直接证据 · 当前段落")
        #expect(blocks.count == 1)
        #expect(blocks.first?.title.contains("Walden") == true)
        #expect(blocks.first?.title.contains("¶") == true)
    }

    @Test func citationPreviewUsesFocusedExcerptFromEvidence() {
        let citation = CompanionModel.citationPreview(
            from: [
                CompanionEvidenceBlock(
                    kind: .passage,
                    title: "《Walden》 · Economy · ¶1",
                    body: "He meant to live deep and suck out all the marrow of life.",
                    emphasisTerms: ["marrow"]
                )
            ]
        )

        #expect(citation?.contains("marrow") == true)
    }
    @Test func evidenceSectionsSplitCurrentBookAndCrossBookEchoes() {
        let blocks = [
            CompanionEvidenceBlock(
                kind: .passage,
                title: "《Walden》 · Economy",
                body: "Simplicity, simplicity, simplicity.",
                scope: .currentBook,
                emphasisTerms: ["simplicity"]
            ),
            CompanionEvidenceBlock(
                kind: .memory,
                title: "Meditations · 第 1 章",
                body: "Stoic subtraction keeps attention calm.",
                scope: .crossBook,
                emphasisTerms: ["attention"]
            ),
        ]

        let sections = CompanionModel.evidenceSections(from: blocks)

        #expect(sections.map(\.title) == ["当前已读原文", "跨书回声"])
        #expect(sections[0].blocks.count == 1)
        #expect(sections[1].blocks.count == 1)
    }

    @Test func emphasisRangesFindCaseInsensitiveMatchesWithoutDuplicatingOverlaps() {
        let text = "Simplicity keeps simplicity honest."

        let ranges = CompanionModel.emphasisRanges(
            in: text,
            matching: ["simplicity", "simp"]
        )

        let matches = ranges.map { String(text[$0]) }
        #expect(matches == ["Simplicity", "simplicity"])
    }


    @Test func parseThemeDraftSplitsTitleBodyAndTags() {
        let parsed = CompanionModel.parseThemeDraft(
            """
            Title: 减法与专注
            Summary: 这轮追问反复围绕如何削掉噪音、留下重点。
            Tags: 减法, 专注, 本质
            """
        )

        #expect(parsed.title == "减法与专注")
        #expect(parsed.body.contains("削掉噪音"))
        #expect(parsed.tags == ["减法", "专注", "本质"])
    }

    @Test func makeThemeDraftRequiresAtLeastTwoAnsweredQuestions() async throws {
        let messages: [CompanionModel.Message] = [
            .init(role: .ai, text: "它在收束论点。", question: "这一段在说什么？")
        ]

        let draft = try await CompanionModel.makeThemeDraft(
            from: messages,
            targetLanguage: "Simplified Chinese",
            service: ScriptedThemeService(response: "unused")
        )

        #expect(draft == nil)
    }

    @Test func makeThemeDraftUsesServiceResponse() async throws {
        let messages: [CompanionModel.Message] = [
            .init(role: .ai, text: "减法是一种纪律。", question: "为什么一直谈减法？"),
            .init(role: .ai, text: "因为作者要把注意力留给本质。", question: "减法最后想得到什么？")
        ]

        let draft = try await CompanionModel.makeThemeDraft(
            from: messages,
            targetLanguage: "Simplified Chinese",
            service: ScriptedThemeService(
                response: """
                Title: 减法与本质
                Summary: 这些追问都在逼近一个长期兴趣：如何删去噪音，只保留真正重要的东西。
                Tags: 减法, 本质
                """
            )
        )

        let resolved = try #require(draft)
        #expect(resolved.title == "减法与本质")
        #expect(resolved.body.contains("长期兴趣"))
        #expect(resolved.tags == ["减法", "本质"])
    }

    @Test func autoThemeDraftReturnsSignatureAndDraft() async throws {
        let messages: [CompanionModel.Message] = [
            .init(role: .ai, text: "减法是一种纪律。", question: "为什么一直谈减法？"),
            .init(role: .ai, text: "因为作者要把注意力留给本质。", question: "减法最后想得到什么？")
        ]

        let proposal = try await CompanionModel.autoThemeDraft(
            from: messages,
            lastSignature: nil,
            targetLanguage: "Simplified Chinese",
            service: ScriptedThemeService(
                response: """
                Title: 减法与本质
                Summary: 这些追问都在逼近一个长期兴趣：如何删去噪音，只保留真正重要的东西。
                Tags: 减法, 本质
                """
            )
        )

        let resolved = try #require(proposal)
        #expect(!resolved.signature.isEmpty)
        #expect(resolved.draft.title == "减法与本质")
    }

    @Test func autoThemeDraftSkipsRepeatedSignature() async throws {
        let messages: [CompanionModel.Message] = [
            .init(role: .ai, text: "减法是一种纪律。", question: "为什么一直谈减法？"),
            .init(role: .ai, text: "因为作者要把注意力留给本质。", question: "减法最后想得到什么？")
        ]
        let signature = try #require(CompanionModel.themeProposalSignature(from: messages))

        let proposal = try await CompanionModel.autoThemeDraft(
            from: messages,
            lastSignature: signature,
            targetLanguage: "Simplified Chinese",
            service: ScriptedThemeService(response: "unused")
        )

        #expect(proposal == nil)
    }
}

private class ScriptedThemeService: AIService, @unchecked Sendable {
    let response: String
    nonisolated(unsafe) var seenTranscripts: [String] = []

    init(response: String) {
        self.response = response
    }

    var availability: AIAvailability { .available }

    func summarize(_ text: String, focus: SummaryFocus) async throws -> String {
        response
    }

    func answer(question: String, groundedIn passages: [GroundedPassage]) async throws -> GroundedAnswer {
        GroundedAnswer(text: response, citedPassageIDs: passages.map(\.id))
    }

    func inlineNote(
        for text: String,
        kind: AIInlineNoteKind,
        targetLanguage: String
    ) async throws -> String {
        response
    }

    func flashcards(from text: String, maxCount: Int) async throws -> [Flashcard] {
        []
    }

    func toolStep(toolDocs: String, transcript: String) async throws -> AgentStep {
        seenTranscripts.append(transcript)
        return .finish(answer: response)
    }
}


@MainActor
private func waitUntilSettled(_ model: CompanionModel) async {
    for _ in 0..<50 where model.thinking {
        await Task.yield()
    }
}
