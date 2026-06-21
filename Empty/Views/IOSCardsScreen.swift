//
//  IOSCardsScreen.swift
//  Empty
//
//  iOS 卡片 from the 02 iOS prototype: one stream that mixes highlight
//  cards, saved study cards (复习卡 / 问答卡 / 链接卡), a compact
//  Ebbinghaus 生词复习 card, and the 朱批 · 发现关联 footer.
//

#if !os(macOS)

import SwiftData
import SwiftUI

private enum IOSCardFilter: Hashable, CaseIterable {
    case all
    case due
    case highlights
    case review
    case qa
    case links
    case vocab

    var title: String {
        switch self {
        case .all: "全部"
        case .due: "待复习"
        case .highlights: "高亮"
        case .review: "闪卡"
        case .qa: "问答"
        case .links: "链接"
        case .vocab: "生词"
        }
    }
}

struct IOSCardsScreen: View {
    var onOpenPosition: (Book, ReadingPosition) -> Void = { _, _ in }

    @Environment(\.emptyPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \StudyCardEntry.createdAt, order: .reverse)
    private var studyCards: [StudyCardEntry]
    @Query(sort: \VocabEntry.dueAt) private var vocabEntries: [VocabEntry]

    @State private var filterBookID: UUID?
    @State private var selectedFilter: IOSCardFilter = .all
    @State private var connections: [ThoughtLink] = []
    @State private var selectedHighlight: Highlight?
    @State private var selectedStudyCard: StudyCardEntry?
    @State private var selectedVocabEntry: VocabEntry?
    @State private var showFlashcardReview = false
    @State private var showGraph = false
    @State private var graphSuggestion = ""
    @State private var isLoadingGraphSuggestion = false

    private var filterableBooks: [Book] {
        var seen = Set<UUID>()
        let owners = highlights.compactMap(\.book) + studyCards.compactMap(\.book) + vocabEntries.compactMap(\.book)
        return owners.filter { seen.insert($0.id).inserted }
    }

    private var activeBookFilter: Book? {
        guard let filterBookID else { return nil }
        return filterableBooks.first { $0.id == filterBookID }
    }

    private var dueCount: Int {
        let now = Date()
        return studyCards.count { $0.dueAt <= now }
            + vocabEntries.count { $0.dueAt <= now }
    }

    private var dueVocabCount: Int {
        let now = Date()
        return vocabEntries.count { $0.dueAt <= now }
    }

    private var availableFlashcards: [StudyCardEntry] {
        let cards = studyCards.filter { $0.kind == .review }
        guard let filterBookID else { return cards }
        return cards.filter { $0.book?.id == filterBookID }
    }

    private var dueFlashcardCount: Int {
        let now = Date()
        return availableFlashcards.count { $0.dueAt <= now }
    }

    private var hasFlashcards: Bool {
        !availableFlashcards.isEmpty
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var cardGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: isRegularWidth ? 2 : 1
        )
    }

    private var graphNodes: [String] {
        let seeds = visibleHighlights.prefix(3).map { highlight in
            String(highlight.textSnapshot.prefix(24))
        }
        return seeds.isEmpty ? ["阅读", "思考", "关联"] : Array(seeds)
    }

    private var suggestionTaskKey: String {
        visibleHighlights.prefix(5).map { $0.id.uuidString }.joined(separator: "|")
            + "|\(filterBookID?.uuidString ?? "all")"
    }

    private var showVocabReview: Bool {
        !visibleVocabEntries.isEmpty
    }

    private var visibleVocabEntries: [VocabEntry] {
        let entries: [VocabEntry]
        switch selectedFilter {
        case .all, .due:
            let now = Date()
            entries = vocabEntries.filter { $0.dueAt <= now }
        case .vocab:
            entries = vocabEntries
        case .highlights, .review, .qa, .links:
            entries = []
        }
        guard let filterBookID else { return entries }
        return entries.filter { $0.book?.id == filterBookID }
    }

    private var showsConnection: Bool {
        selectedFilter == .all || selectedFilter == .highlights
    }

    private var visibleHighlights: [Highlight] {
        guard selectedFilter == .all || selectedFilter == .highlights else { return [] }
        guard let filterBookID else { return highlights }
        return highlights.filter { $0.book?.id == filterBookID }
    }

    private var visibleStudyCards: [StudyCardEntry] {
        let cards: [StudyCardEntry]
        switch selectedFilter {
        case .all:
            cards = studyCards
        case .due:
            let now = Date()
            cards = studyCards.filter { $0.dueAt <= now }
        case .review:
            cards = studyCards.filter { $0.kind == .review }
        case .qa:
            cards = studyCards.filter { $0.kind == .qa }
        case .links:
            cards = studyCards.filter { $0.kind == .link }
        case .highlights, .vocab:
            cards = []
        }
        guard let filterBookID else { return cards }
        return cards.filter { $0.book?.id == filterBookID }
    }

    private var hasVisibleContent: Bool {
        showVocabReview || !visibleStudyCards.isEmpty || !visibleHighlights.isEmpty
            || (showsConnection && !connections.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("卡片")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("\(highlights.count + studyCards.count + vocabEntries.count) 张 · 今日待复习 \(dueCount) 张")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink3)
                    .padding(.top, 2)

                filterRow
                    .padding(.top, 16)

                if hasFlashcards {
                    immersiveReviewBanner
                        .padding(.top, 12)
                }

                if highlights.isEmpty && studyCards.isEmpty && vocabEntries.isEmpty {
                    emptyState
                        .padding(.top, 48)
                } else if !hasVisibleContent {
                    filteredEmptyState
                        .padding(.top, 42)
                } else {
                    cardStream
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .task(id: highlights.first?.id) {
            await loadConnections()
        }
        .task(id: suggestionTaskKey) {
            await loadGraphSuggestion()
        }

        .sheet(item: $selectedHighlight) { highlight in
            IOSHighlightDetailSheet(
                highlight: highlight,
                onOpenSource: highlight.book.map { book in
                    {
                        onOpenPosition(
                            book,
                            ReadingPosition(
                                chapterIndex: highlight.chapterIndex,
                                utf16Offset: highlight.startUTF16
                            )
                        )
                    }
                }
            )
        }
        .sheet(item: $selectedStudyCard) { card in
            IOSStudyCardDetailSheet(
                card: card,
                onOpenSource: sourceJumpAction(for: card)
            )
        }
        .sheet(item: $selectedVocabEntry) { entry in
            IOSVocabDetailSheet(
                entry: entry,
                onOpenSource: sourceJumpAction(for: entry)
            )
        }
        .sheet(isPresented: $showGraph) {
            IOSGraphSheet(
                highlights: Array(visibleHighlights.prefix(8)),
                nodes: graphNodes,
                suggestion: isLoadingGraphSuggestion ? "AI 正在分析你的高亮主题…" : graphSuggestion
            )
        }
        .fullScreenCover(isPresented: $showFlashcardReview) {
            IOSFlashcardReviewScreen(bookFilter: activeBookFilter)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IOSCardFilter.allCases, id: \.self) { filter in
                    if shouldShow(filter) {
                        filterChip(filter)
                    }
                }
                ForEach(filterableBooks.prefix(4)) { book in
                    bookFilterChip(book.title, bookID: book.id)
                }
            }
        }
    }

    private func shouldShow(_ filter: IOSCardFilter) -> Bool {
        switch filter {
        case .all, .highlights:
            true
        case .due:
            dueCount > 0
        case .review:
            studyCards.contains { $0.kind == .review }
        case .qa:
            studyCards.contains { $0.kind == .qa }
        case .links:
            studyCards.contains { $0.kind == .link }
        case .vocab:
            !vocabEntries.isEmpty
        }
    }

    private func filterChip(_ filter: IOSCardFilter) -> some View {
        let isActive = selectedFilter == filter && filterBookID == nil
        let badge = filter == .due && dueCount > 0 ? " \(dueCount)" : ""
        return Button {
            selectedFilter = filter
            filterBookID = nil
        } label: {
            Text("\(filter.title)\(badge)")
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.onAccent : palette.ink2)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(isActive ? palette.accent : .clear, in: Capsule())
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.line2, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func bookFilterChip(_ title: String, bookID: UUID?) -> some View {
        let isActive = filterBookID == bookID
        return Button {
            selectedFilter = .all
            filterBookID = bookID
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.onAccent : palette.ink2)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(isActive ? palette.accent : .clear, in: Capsule())
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.line2, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var immersiveReviewBanner: some View {
        Button {
            showFlashcardReview = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("沉浸式闪卡")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text(
                        dueFlashcardCount > 0
                            ? "还有 \(dueFlashcardCount) 张待复习，进入全屏专注过卡。"
                            : "所有闪卡都在这里，进全屏连续复习。"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
            }
            .padding(15)
            .emptyCard(palette, radius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cards.flashcards.open")
    }

    private var cardStream: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showVocabReview {
                IOSVocabReviewCard(
                    entries: visibleVocabEntries,
                    reviewAll: selectedFilter == .vocab,
                    onOpenSource: sourceJumpAction(for:),
                    onShowDetail: { selectedVocabEntry = $0 }
                )
            }

            LazyVGrid(columns: cardGridColumns, spacing: 14) {
                ForEach(visibleStudyCards) { card in
                    IOSStudyCard(
                        card: card,
                        onOpenSource: sourceJumpAction(for: card),
                        onOpenDetail: { selectedStudyCard = card }
                    )
                }

                ForEach(visibleHighlights) { highlight in
                    highlightCard(highlight)
                }
            }

            if showsConnection && !connections.isEmpty {
                connectionList
            }
        }
    }

    private func highlightCard(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(highlight.textSnapshot.count < 28 ? "概念卡" : "我的高亮")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(chipColor(for: highlight))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(chipBackground(for: highlight), in: Capsule())
                Text(sourceLine(for: highlight))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("“\(highlight.textSnapshot)”")
                .font(.system(size: 13.5, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(palette.ink)
            if let note = highlight.note, !note.isEmpty {
                Text("你的批注:\(note)")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink3)
            }
            HStack(spacing: 8) {
                if let book = highlight.book {
                    Button {
                        onOpenPosition(
                            book,
                            ReadingPosition(
                                chapterIndex: highlight.chapterIndex,
                                utf16Offset: highlight.startUTF16
                            )
                        )
                    } label: {
                        Label("跳回原文", systemImage: "arrow.turn.up.backward")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cards.highlight.jump")
                }

                Button {
                    selectedHighlight = highlight
                } label: {
                    Text("详情")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(palette.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cards.highlight.detail")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .emptyCard(palette)
    }

    private func chipColor(for highlight: Highlight) -> Color {
        highlight.textSnapshot.count < 28
            ? palette.accent
            : (palette.isDark ? Color(hex: 0xDEB248) : Color(hex: 0x7A6320))
    }

    private func chipBackground(for highlight: Highlight) -> Color {
        highlight.textSnapshot.count < 28 ? palette.accentSoft : palette.highlight
    }

    private func sourceLine(for highlight: Highlight) -> String {
        var parts: [String] = []
        if let title = highlight.book?.title { parts.append(title) }
        parts.append("第 \(highlight.chapterIndex + 1) 章")
        return parts.joined(separator: " · ")
    }

    private func sourceJumpAction(for card: StudyCardEntry) -> (() -> Void)? {
        guard let book = card.book else { return nil }
        if let position = card.sourcePosition {
            return { onOpenPosition(book, position) }
        }
        if let highlightID = card.highlightID,
           let highlight = highlights.first(where: { $0.id == highlightID }) {
            return {
                onOpenPosition(
                    highlight.book ?? book,
                    ReadingPosition(
                        chapterIndex: highlight.chapterIndex,
                        utf16Offset: highlight.startUTF16
                    )
                )
            }
        }
        return nil
    }

    private func sourceJumpAction(for entry: VocabEntry) -> (() -> Void)? {
        guard let book = entry.book, let position = entry.sourcePosition else { return nil }
        return { onOpenPosition(book, position) }
    }

    private var connectionList: some View {
        ZhupiCallout(title: "朱批 · 相关联想") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(connections) { link in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(link.theme ?? link.relatedBookTitle)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(palette.accent)
                            Text(link.relatedSource)
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.ink3)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        Text("“\(link.relatedText.prefix(38))…”")
                            .font(.system(size: 12.5, design: .serif))
                            .lineSpacing(4)
                            .foregroundStyle(palette.ink)
                            .lineLimit(2)
                        Text(link.explanation)
                            .font(.system(size: 11.5))
                            .lineSpacing(4)
                            .foregroundStyle(palette.ink2)
                        if let onOpenRelated = relatedJumpAction(for: link) {
                            Button {
                                onOpenRelated()
                            } label: {
                                Label("打开关联原文", systemImage: "arrow.turn.up.right")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, link.id == connections.last?.id ? 0 : 8)
                }
                HStack(spacing: 10) {
                    Text("完整知识图谱仍在 Mac 端；手机先给你最近 3 条可回跳关联。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                    Spacer(minLength: 0)
                    Button("打开移动图谱") {
                        showGraph = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("cards.graph.open")
                }
                .padding(.top, 2)
            }
        }
    }

    private func relatedJumpAction(for link: ThoughtLink) -> (() -> Void)? {
        guard let highlightID = link.relatedHighlightID,
              let highlight = highlights.first(where: { $0.id == highlightID }),
              let book = highlight.book
        else { return nil }
        return {
            onOpenPosition(
                book,
                ReadingPosition(
                    chapterIndex: highlight.chapterIndex,
                    utf16Offset: highlight.startUTF16
                )
            )
        }
    }

    /// Quick cross-book echoes from the latest highlight — first few results
    /// on iPhone, full graph on reader / Mac.
    private func loadConnections() async {
        guard let latest = highlights.first, let book = latest.book else {
            connections = []
            return
        }
        connections = (try? ThoughtLinkFinder(modelContext: modelContext).findLinks(
            passage: latest.textSnapshot,
            book: book,
            chapterIndex: latest.chapterIndex,
            limit: 3
        )) ?? []
    }

    private func loadGraphSuggestion() async {
        guard !visibleHighlights.isEmpty else {
            graphSuggestion = ""
            return
        }
        isLoadingGraphSuggestion = true
        defer { isLoadingGraphSuggestion = false }

        let fallback =
            "AI 建议:你的 \(min(visibleHighlights.count, 3)) 条高亮已收录。继续阅读时留意跨书呼应，图谱会随笔记生长。"
        let samples = visibleHighlights.prefix(5).map(\.textSnapshot).joined(separator: "\n")
        let resolution = AIProviderRegistry.load().resolveUsableService(feature: .chat)
        guard resolution.service.availability.isAvailable else {
            graphSuggestion = fallback
            return
        }
        do {
            let summary = try await resolution.service.summarize(
                samples,
                focus: .digest
            )
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            graphSuggestion = trimmed.isEmpty ? fallback : "AI 建议:\(trimmed)"
        } catch {
            graphSuggestion = fallback
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            EnsoMark(size: 44)
                .opacity(0.5)
            Text("还没有卡片")
                .font(.system(size: 18, weight: .black, design: .serif))
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
            Text("阅读时的高亮、向 AI 的追问、查过的生词,都会沉淀到这里复习。")
                .font(.system(size: 13))
                .foregroundStyle(palette.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 9) {
            Text("这一类暂时没有内容")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(palette.ink)
            Text("换个筛选,或回到阅读器继续高亮、提问、生成卡片。")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mobile graph

private struct IOSGraphSheet: View {
    let highlights: [Highlight]
    let nodes: [String]
    let suggestion: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("移动图谱")
                        .font(.system(size: 28, weight: .black, design: .serif))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Button("完成") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("知识图谱")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.ink)
                        Text("跨书概念关联")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.ink3)
                    }

                    Canvas { context, size in
                        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.33)
                        let left = CGPoint(x: size.width * 0.24, y: size.height * 0.64)
                        let right = CGPoint(x: size.width * 0.76, y: size.height * 0.61)
                        let bottom = CGPoint(x: size.width * 0.5, y: size.height * 0.84)

                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: left)
                        path.move(to: center)
                        path.addLine(to: right)
                        path.move(to: center)
                        path.addLine(to: bottom)
                        path.move(to: left)
                        path.addLine(to: bottom)
                        context.stroke(
                            path,
                            with: .color(palette.accent.opacity(0.55)),
                            lineWidth: 1.5
                        )

                        drawNode(context, at: center, radius: 40, filled: true, label: nodes.first ?? "概念")
                        drawNode(context, at: left, radius: 30, filled: false, label: nodes.dropFirst().first ?? "关联")
                        drawNode(context, at: right, radius: 30, filled: false, label: nodes.dropFirst(2).first ?? "主题")
                        drawNode(context, at: bottom, radius: 24, filled: false, label: "?", dashed: true)
                    }
                    .frame(height: 220)

                    if !suggestion.isEmpty {
                        Text(suggestion)
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .foregroundStyle(palette.ink2)
                            .padding(.top, 6)
                            .overlay(alignment: .top) {
                                Rectangle().fill(palette.line).frame(height: 1).offset(y: -6)
                            }
                    }
                }
                .padding(20)
                .emptyCard(palette)

                if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("图谱种子")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.ink)
                        ForEach(highlights) { highlight in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("“\(highlight.textSnapshot)”")
                                    .font(.system(size: 12.5, design: .serif))
                                    .lineSpacing(4)
                                    .foregroundStyle(palette.ink)
                                Text(sourceLine(for: highlight))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.ink3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.line, lineWidth: 1))
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .background(palette.window)
    }

    private func drawNode(
        _ context: GraphicsContext,
        at point: CGPoint,
        radius: CGFloat,
        filled: Bool,
        label: String,
        dashed: Bool = false
    ) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let shape = Path(ellipseIn: rect)
        if filled {
            context.fill(shape, with: .color(palette.accentSoft))
        }
        context.stroke(
            shape,
            with: .color(palette.accent),
            style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 4] : [])
        )
        context.draw(
            Text(label)
                .font(.system(size: radius > 30 ? 12 : 10, weight: .bold))
                .foregroundColor(palette.ink),
            at: point,
            anchor: .center
        )
    }

    private func sourceLine(for highlight: Highlight) -> String {
        var parts: [String] = []
        if let title = highlight.book?.title { parts.append(title) }
        parts.append("第 \(highlight.chapterIndex + 1) 章")
        return parts.joined(separator: " · ")
    }
}


// MARK: - Full-screen flashcard review

private struct IOSFlashcardReviewScreen: View {
    let bookFilter: Book?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        ZStack {
            palette.window.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("沉浸式闪卡")
                            .font(.system(size: 28, weight: .black, design: .serif))
                            .foregroundStyle(palette.ink)
                        Text(bookFilter?.title ?? "全部书籍")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.ink3)
                    }
                    Spacer()
                    Button("完成") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                }

                FlashcardsReviewView(
                    bookFilter: bookFilter,
                    accentColor: palette.accent,
                    emptyTitle: "还没有闪卡",
                    emptyDescription: "在阅读器里保存复习卡，这里会进入连续复习。"
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("cards.flashcards.screen")
    }
}

// MARK: - Vocab detail

private struct IOSVocabDetailSheet: View {
    let entry: VocabEntry
    let onOpenSource: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.word)
                            .font(.system(size: 26, weight: .black, design: .serif))
                            .foregroundStyle(palette.ink)
                        HStack(spacing: 8) {
                            if let partOfSpeech = entry.partOfSpeech {
                                Text(partOfSpeech)
                            }
                            if let phonetic = entry.phonetic {
                                Text(phonetic)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink3)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 32, height: 32)
                                .background(palette.accentSoft, in: Circle())
                        }
                        Button("完成") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    }
                }

                section("释义") {
                    Text(entry.meaning)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12.5))
                            .lineSpacing(5)
                            .foregroundStyle(palette.ink2)
                            .padding(.top, 6)
                    }
                }

                if let sentence = entry.sentence, !sentence.isEmpty {
                    section("原句") {
                        Text("“\(sentence)”")
                            .font(.system(size: 13, design: .serif))
                            .italic()
                            .lineSpacing(5)
                            .foregroundStyle(palette.ink2)
                    }
                }

                section("复习节奏") {
                    Text("第 \(entry.stage) 轮 · 下次 \(entry.dueAt.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("记得后会推迟到 \(entry.nextIntervalDays) 天后；模糊保持当前间隔。")
                        .font(.system(size: 11.5))
                        .lineSpacing(4)
                        .foregroundStyle(palette.ink3)
                        .padding(.top, 4)
                }

                if let source = entry.source {
                    section("来源") {
                        Text(source)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.ink2)
                        if let onOpenSource {
                            Button {
                                dismiss()
                                onOpenSource()
                            } label: {
                                Label("跳回原文", systemImage: "arrow.turn.up.backward")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(palette.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                            .accessibilityIdentifier("cards.vocab.detail.jump")
                        }
                    }
                }

                HStack(spacing: 8) {
                    gradeButton("忘了", grade: .forgot, emphasized: false)
                    gradeButton("模糊", grade: .fuzzy, emphasized: false)
                    gradeButton("记得", grade: .good, emphasized: true)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .background(palette.window)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.line, lineWidth: 1))
    }

    private var shareText: String {
        var lines = ["生词：\(entry.word)", entry.meaning]
        if let note = entry.note, !note.isEmpty { lines.append(note) }
        if let sentence = entry.sentence, !sentence.isEmpty { lines.append("“\(sentence)”") }
        if let source = entry.source { lines.append(source) }
        if let deepLink { lines.append(deepLink) }
        return lines.joined(separator: "\n\n")
    }

    private var deepLink: String? {
        guard let book = entry.book, let position = entry.sourcePosition else { return nil }
        return EmptyDeepLink.urlString(
            bookID: book.id,
            chapterIndex: position.chapterIndex,
            utf16Offset: position.utf16Offset
        )
    }

    private func gradeButton(_ title: String, grade: VocabReviewGrade, emphasized: Bool) -> some View {
        Button {
            entry.applyReview(grade)
            try? modelContext.save()
            dismiss()
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .bold : .semibold))
                .foregroundStyle(emphasized ? palette.onAccent : palette.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    emphasized ? palette.accent : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    if !emphasized {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(palette.line2, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Highlight / study detail

private struct IOSHighlightDetailSheet: View {
    let highlight: Highlight
    let onOpenSource: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("高亮详情")
                        .font(.system(size: 24, weight: .black, design: .serif))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 32, height: 32)
                            .background(palette.accentSoft, in: Circle())
                    }
                    Button("完成") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }

                detailSection("摘录") {
                    Text("“\(highlight.textSnapshot)”")
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(palette.ink)
                }

                if let note = highlight.note, !note.isEmpty {
                    detailSection("批注") {
                        Text(note)
                            .font(.system(size: 12.5))
                            .lineSpacing(5)
                            .foregroundStyle(palette.ink2)
                    }
                }

                detailSection("来源") {
                    Text(sourceLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink2)
                    if let onOpenSource {
                        Button {
                            dismiss()
                            onOpenSource()
                        } label: {
                            Label("跳回原文", systemImage: "arrow.turn.up.backward")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(palette.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .accessibilityIdentifier("cards.highlight.detail.jump")
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .background(palette.window)
    }

    private var sourceLine: String {
        var parts: [String] = []
        if let title = highlight.book?.title { parts.append(title) }
        parts.append("第 \(highlight.chapterIndex + 1) 章")
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        var lines = ["高亮", "“\(highlight.textSnapshot)”", sourceLine]
        if let note = highlight.note, !note.isEmpty { lines.append(note) }
        if let book = highlight.book {
            lines.append(
                EmptyDeepLink.urlString(
                    bookID: book.id,
                    chapterIndex: highlight.chapterIndex,
                    utf16Offset: highlight.startUTF16
                )
            )
        }
        return lines.joined(separator: "\n\n")
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.line, lineWidth: 1))
    }
}

private struct IOSStudyCardDetailSheet: View {
    let card: StudyCardEntry
    let onOpenSource: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.kind == .review ? "复习卡详情" : (card.kind == .qa ? "问答卡详情" : "链接卡详情"))
                        .font(.system(size: 24, weight: .black, design: .serif))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 32, height: 32)
                            .background(palette.accentSoft, in: Circle())
                    }
                    Button("完成") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }

                detailSection("问题") {
                    Text(card.question)
                        .font(.system(size: 14, weight: .semibold))
                        .lineSpacing(5)
                        .foregroundStyle(palette.ink)
                }

                detailSection(card.kind == .review ? "答案" : "内容") {
                    Text(card.answer)
                        .font(.system(size: 12.5))
                        .lineSpacing(5)
                        .foregroundStyle(palette.ink2)
                }

                if let source = card.source {
                    detailSection("来源") {
                        Text(source)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.ink2)
                        if let onOpenSource {
                            Button {
                                dismiss()
                                onOpenSource()
                            } label: {
                                Label("跳回原文", systemImage: "arrow.turn.up.backward")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(palette.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                            .accessibilityIdentifier("cards.study.detail.jump")
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 26)
        }
        .background(palette.window)
    }

    private var shareText: String {
        var lines = [card.question, card.answer]
        if let source = card.source { lines.append(source) }
        if let deepLink { lines.append(deepLink) }
        return lines.joined(separator: "\n\n")
    }

    private var deepLink: String? {
        guard let book = card.book, let position = card.sourcePosition else { return nil }
        return EmptyDeepLink.urlString(
            bookID: book.id,
            chapterIndex: position.chapterIndex,
            utf16Offset: position.utf16Offset
        )
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.line, lineWidth: 1))
    }
}

// MARK: - Study card (复习卡 / 问答卡 / 链接卡)

private struct IOSStudyCard: View {
    let card: StudyCardEntry
    let onOpenSource: (() -> Void)?
    let onOpenDetail: () -> Void

    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(chipTitle)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(palette.accentSoft, in: Capsule())
                Text(metaLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(card.kind == .qa ? "Q:\(card.question)" : card.question)
                .font(.system(size: 13.5, weight: .bold))
                .lineSpacing(4)
                .foregroundStyle(palette.ink)
                .padding(.top, 10)

            if card.kind == .review {
                if revealed {
                    Text(card.answer)
                        .font(.system(size: 12.5))
                        .lineSpacing(5)
                        .foregroundStyle(palette.ink2)
                        .padding(.top, 8)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(palette.accent).frame(width: 2)
                        }
                }
                HStack(spacing: 8) {
                    Button(revealed ? "收起答案" : "显示答案") {
                        withAnimation { revealed.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(palette.line2, lineWidth: 1))

                    Button("记得 ✓") {
                        card.applyReview(.good)
                        try? modelContext.save()
                        revealed = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(palette.accentSoft, in: Capsule())
                }
                .padding(.top, 12)
                HStack(spacing: 8) {
                    if let onOpenSource {
                        Button {
                            onOpenSource()
                        } label: {
                            Label("跳回原文", systemImage: "arrow.turn.up.backward")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(palette.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cards.study.jump")
                    }
                    Button("详情") {
                        onOpenDetail()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(palette.line2, lineWidth: 1))
                    .accessibilityIdentifier("cards.study.detail")
                }
                .padding(.top, 10)
            } else {
                Text(card.answer)
                    .font(.system(size: 12.5))
                    .lineSpacing(5)
                    .foregroundStyle(palette.ink2)
                    .padding(.top, 8)
                if let source = card.source {
                    Text(source)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                        .padding(.top, 8)
                }
                HStack(spacing: 8) {
                    if let onOpenSource {
                        Button {
                            onOpenSource()
                        } label: {
                            Label("跳回原文", systemImage: "arrow.turn.up.backward")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(palette.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cards.study.jump")
                    }
                    Button("详情") {
                        onOpenDetail()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(palette.line2, lineWidth: 1))
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .emptyCard(palette)
        .contextMenu {
            Button("删除", systemImage: "trash", role: .destructive) {
                modelContext.delete(card)
                try? modelContext.save()
            }
        }
    }

    private var chipTitle: String {
        switch card.kind {
        case .review: "复习卡"
        case .qa: "问答卡"
        case .link: "⟲ 链接卡"
        }
    }

    private var metaLine: String {
        switch card.kind {
        case .review: "间隔复习 · 第 \(card.stage) 轮"
        case .qa: "来自你的追问"
        case .link: "AI 发现关联"
        }
    }
}

// MARK: - Compact vocab review (艾宾浩斯)

private struct IOSVocabReviewCard: View {
    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext
    let entries: [VocabEntry]
    let reviewAll: Bool
    let onOpenSource: (VocabEntry) -> (() -> Void)?
    let onShowDetail: (VocabEntry) -> Void
    @State private var now = Date()
    @State private var reviewIndex = 0
    @State private var revealed = false

    private var reviewEntries: [VocabEntry] {
        entries
    }

    private var current: VocabEntry? {
        guard reviewIndex < reviewEntries.count else { return nil }
        return reviewEntries[reviewIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(reviewAll ? "生词本" : "生词复习")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(palette.accentSoft, in: Capsule())
                Text("\(reviewAll ? "全部词条" : "艾宾浩斯间隔") · \(progressLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
                Spacer(minLength: 0)
            }

            if let entry = current {
                activeReview(entry)
            } else {
                doneState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .emptyCard(palette)
        .onAppear { now = Date() }
    }

    private var progressLabel: String {
        reviewEntries.isEmpty || current == nil
            ? "完成"
            : "\(min(reviewIndex + 1, reviewEntries.count)) / \(reviewEntries.count)"
    }

    @ViewBuilder
    private func activeReview(_ entry: VocabEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.word)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .foregroundStyle(palette.ink)
            if let phonetic = entry.phonetic {
                Text("\(phonetic) · 第 \(entry.stage) 轮")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            } else {
                Text("第 \(entry.stage) 轮")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            }
        }
        .padding(.top, 10)

        if let sentence = entry.sentence, !sentence.isEmpty {
            Text("\u{201C}\(revealed ? sentence : VocabCloze.blank(sentence, word: entry.word))\u{201D}")
                .font(.system(size: 12.5, design: .serif))
                .italic()
                .lineSpacing(5)
                .foregroundStyle(palette.ink2)
                .padding(.top, 6)
        }

        if let source = entry.source {
            Text(source)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.ink3)
                .lineLimit(1)
                .padding(.top, 7)
        }

        HStack(spacing: 8) {
            if let jump = onOpenSource(entry) {
                Button {
                    jump()
                } label: {
                    Label("跳回原文", systemImage: "arrow.turn.up.backward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(palette.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cards.vocab.jump")
            }

            Button {
                onShowDetail(entry)
            } label: {
                Text("详情")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(palette.line2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cards.vocab.detail")
        }
        .padding(.top, 8)

        if revealed {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.meaning)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.ink2)
                }
            }
            .padding(.top, 8)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(palette.accent).frame(width: 2)
            }

            HStack(spacing: 8) {
                gradeButton("忘了 · 明天再见", grade: .forgot, entry: entry, emphasized: false)
                gradeButton(
                    "记得 ✓ · \(entry.nextIntervalDays) 天后",
                    grade: .good,
                    entry: entry,
                    emphasized: true
                )
            }
            .padding(.top, 10)
        } else {
            Button("显示释义") {
                withAnimation { revealed = true }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(palette.window)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(palette.ink, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 10)
        }
    }

    private var doneState: some View {
        VStack(spacing: 4) {
            Text("✓")
                .font(.system(size: 18))
                .foregroundStyle(palette.accent)
            Text(reviewAll ? "生词本已到末尾" : "今日生词复习完成")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(palette.ink)
            let forecast = VocabQueueForecast.describe(dueDates: entries.map(\.dueAt), now: now)
            if !forecast.isEmpty {
                Text("下次队列:\(forecast)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            }
            Button("↻ 再练一轮") {
                reviewIndex = 0
                revealed = false
                now = Date()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(palette.ink2)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(palette.line2, lineWidth: 1))
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func gradeButton(
        _ title: String,
        grade: VocabReviewGrade,
        entry: VocabEntry,
        emphasized: Bool
    ) -> some View {
        Button {
            entry.applyReview(grade)
            try? modelContext.save()
            revealed = false
            // `now` stays frozen for the session, so the queue keeps its
            // members and the index walks it — same semantics as the Mac
            // review (and what makes ↻ 再练一轮 meaningful).
            reviewIndex += 1
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: emphasized ? .bold : .semibold))
                .foregroundStyle(emphasized ? palette.onAccent : palette.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    emphasized ? palette.accent : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    if !emphasized {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(palette.line2, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#endif
