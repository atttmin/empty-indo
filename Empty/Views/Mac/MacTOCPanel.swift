//
//  MacTOCPanel.swift
//  Empty
//

#if os(macOS)

import SwiftData
import SwiftUI

// MARK: - 章节目录 (TOC panel)

/// The prototype's in-reader TOC: roman numerals, bilingual chapter
/// titles, per-chapter reading progress / 朱批 count / estimated length,
/// the chapter's 预译 state, and the whole-book translation-cache footer.
struct MacTOCPanel: View {
    let bookTitle: String
    let titles: [String]
    let cnTitles: [Int: String]
    let currentIndex: Int
    let intraChapterFraction: Double
    let progressByChapter: [Int: MacChapterTransStatus]
    /// Changing this re-fetches cache statistics.
    let statsTick: Int
    let book: Book
    var onSelect: (Int) -> Void
    var onClose: () -> Void
    /// Jump to an exact in-chapter position (bookmark / search hit).
    var onJump: (ReadingPosition) -> Void = { _ in }

    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext

    private enum DrawerTab: String, CaseIterable {
        case toc = "目录"
        case bookmarks = "书签"
        case search = "搜索"
    }

    @State private var tab: DrawerTab = .toc
    @State private var bookmarks: [Bookmark] = []
    @State private var searchQuery = ""
    @State private var searchRead: [BookSearchHit] = []
    @State private var searchUnread: [BookSearchHit] = []
    @State private var unreadExpanded = false

    private struct ChapterFacts {
        var utf16Length = 0
        var pretranslated = false
        var cachedCount = 0
        var highlightCount = 0
    }

    @State private var facts: [Int: ChapterFacts] = [:]
    @State private var footprint: (count: Int, bytes: Int) = (0, 0)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(DrawerTab.allCases, id: \.self) { choice in
                    Button {
                        tab = choice
                    } label: {
                        Text(choice.rawValue)
                            .font(.system(size: 12, weight: tab == choice ? .bold : .regular))
                            .foregroundStyle(tab == choice ? palette.accent : palette.ink3)
                            .padding(.vertical, 2)
                            .overlay(alignment: .bottom) {
                                if tab == choice {
                                    Rectangle().fill(palette.accent).frame(height: 2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onClose) {
                    Text("×")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink3)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 10, trailing: 14))

            switch tab {
            case .toc:
                tocList
                footer
            case .bookmarks:
                bookmarkList
            case .search:
                searchPane
            }
        }
        .background(palette.side)
        .task(id: statsTick) {
            refreshFacts()
        }
    }

    private var tocList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        row(index: index, title: title)
                            .id(index)
                    }
                }
                .padding(EdgeInsets(top: 2, leading: 10, bottom: 10, trailing: 10))
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    // MARK: 书签

    private var bookmarkList: some View {
        ScrollView {
            VStack(spacing: 4) {
                if bookmarks.isEmpty {
                    Text("还没有书签 — 阅读时按 ⌘D 在当前位置留一枚。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .padding(.horizontal, 16)
                }
                ForEach(bookmarks) { bookmark in
                    bookmarkRow(bookmark)
                }
            }
            .padding(EdgeInsets(top: 2, leading: 10, bottom: 10, trailing: 10))
        }
        .task(id: statsTick) { reloadBookmarks() }
        .onAppear { reloadBookmarks() }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            onJump(ReadingPosition(
                chapterIndex: bookmark.chapterIndex,
                utf16Offset: bookmark.utf16Offset
            ))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.accent)
                    Text(chapterLabel(bookmark.chapterIndex))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.ink2)
                    Spacer()
                    Button {
                        try? BookmarkStore(modelContext: modelContext).delete(bookmark)
                        reloadBookmarks()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.ink3)
                    }
                    .buttonStyle(.plain)
                }
                Text(bookmark.snippet)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func reloadBookmarks() {
        bookmarks = (try? BookmarkStore(modelContext: modelContext).bookmarks(for: book)) ?? []
    }

    // MARK: 搜索（未读折叠防剧透）

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
                TextField("全文搜索…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(searchRead) { hit in
                        searchHitRow(hit)
                    }
                    if !searchUnread.isEmpty {
                        if unreadExpanded {
                            Text("未读章节（小心剧透）")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(palette.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                            ForEach(searchUnread) { hit in
                                searchHitRow(hit)
                            }
                        } else {
                            Button {
                                unreadExpanded = true
                            } label: {
                                Text("未读章节中还有 \(searchUnread.count) 处 · 点开（可能剧透）")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.ink3)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(palette.line2, style: StrokeStyle(dash: [4, 4]))
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        }
                    }
                    if searchRead.isEmpty && searchUnread.isEmpty
                        && searchQuery.trimmingCharacters(in: .whitespaces).count >= 2 {
                        Text("没有找到「\(searchQuery)」")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.ink3)
                            .padding(.top, 24)
                    }
                }
                .padding(EdgeInsets(top: 2, leading: 10, bottom: 10, trailing: 10))
            }
        }
        .task(id: searchQuery) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func searchHitRow(_ hit: BookSearchHit) -> some View {
        Button {
            onJump(ReadingPosition(
                chapterIndex: hit.chapterIndex,
                utf16Offset: hit.utf16Offset
            ))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapterLabel(hit.chapterIndex))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.ink3)
                Text(hit.snippet)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func runSearch() {
        unreadExpanded = false
        let result = (try? BookTextSearch(modelContext: modelContext).search(
            book: book,
            query: searchQuery,
            maxReadChapter: max(currentIndex, book.position.chapterIndex)
        )) ?? (read: [], unread: [])
        searchRead = result.read
        searchUnread = result.unread
    }

    private func chapterLabel(_ index: Int) -> String {
        let title = titles.indices.contains(index) ? titles[index] : ""
        let display = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "第 \(index + 1) 章"
            : title
        return "\(RomanNumeral.format(index + 1)) · \(display)"
    }

    private func row(index: Int, title: String) -> some View {
        let isCurrent = index == currentIndex
        let chapterFacts = facts[index] ?? ChapterFacts()
        let display = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "第 \(index + 1) 章"
            : title
        return Button {
            onSelect(index)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(RomanNumeral.format(index + 1))
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundStyle(isCurrent ? palette.accent : palette.ink3)
                        .frame(width: 22, alignment: .leading)
                    Text(display)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(isCurrent ? palette.accent : palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 9) {
                    Spacer().frame(width: 22)
                    if let cn = cnTitles[index] {
                        Text(cn)
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(palette.ink3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    transChip(index: index, facts: chapterFacts)
                }
                HStack(spacing: 9) {
                    Spacer().frame(width: 22)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.line)
                            Capsule()
                                .fill(palette.accent)
                                .frame(width: geo.size.width * progressFraction(index: index))
                        }
                    }
                    .frame(height: 3)
                    Text(metaLine(index: index, facts: chapterFacts))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(
                isCurrent ? palette.accentSoft : .clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func transChip(index: Int, facts chapterFacts: ChapterFacts) -> some View {
        if chapterFacts.pretranslated {
            Text("✓ 已缓存")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(palette.accentSoft, in: Capsule())
        } else if case .translating(let done, let total) = progressByChapter[index], total > 0 {
            Text("⟳ 预译 \(Int(Double(done) / Double(total) * 100))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.accent)
        } else if progressByChapter[index] == .queued {
            Text("排队中")
                .font(.system(size: 10))
                .foregroundStyle(palette.ink3)
        } else if chapterFacts.cachedCount > 0 {
            Text("部分缓存")
                .font(.system(size: 10))
                .foregroundStyle(palette.ink3)
        } else {
            Text("未译")
                .font(.system(size: 10))
                .foregroundStyle(palette.ink3)
        }
    }

    private func progressFraction(index: Int) -> CGFloat {
        if index < currentIndex { return 1 }
        if index == currentIndex { return CGFloat(min(max(intraChapterFraction, 0), 1)) }
        return 0
    }

    private func metaLine(index: Int, facts chapterFacts: ChapterFacts) -> String {
        if index < currentIndex {
            return chapterFacts.highlightCount > 0
                ? "已读完 · 朱批 \(chapterFacts.highlightCount)"
                : "已读完"
        }
        if index == currentIndex {
            let percent = "\(Int((intraChapterFraction * 100).rounded()))%"
            return chapterFacts.highlightCount > 0
                ? "\(percent) · 朱批 \(chapterFacts.highlightCount)"
                : percent
        }
        let minutes = ReadingTimeEstimate.minutes(
            utf16Length: chapterFacts.utf16Length,
            languageTag: book.languageTag
        )
        return minutes > 0 ? "约 \(minutes) 分钟" : "—"
    }

    private var footer: some View {
        let pretranslated = facts.values.count { $0.pretranslated }
        let fraction = titles.isEmpty ? 0 : Double(pretranslated) / Double(titles.count)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("全书预译")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))% · \(Self.byteLabel(footprint.bytes))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.line)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 4)
            .padding(.top, 7)
            Text("译文缓存在本机,离线可读、不重复翻译。阅读时自动预译后两章。")
                .font(.system(size: 10.5))
                .lineSpacing(4)
                .foregroundStyle(palette.ink3)
                .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .overlay(alignment: .top) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
    }

    private static func byteLabel(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1_024 {
            return "\(bytes / 1_024) KB"
        }
        return "\(bytes) B"
    }

    private func refreshFacts() {
        let bookID = book.id
        let store = TranslationStore(modelContext: modelContext)
        let chapters = (try? modelContext.fetch(
            FetchDescriptor<Chapter>(
                predicate: #Predicate { $0.bookID == bookID },
                sortBy: [SortDescriptor(\.index)]
            )
        )) ?? []
        let highlights = (try? modelContext.fetch(
            FetchDescriptor<Highlight>(
                predicate: #Predicate { $0.book?.id == bookID }
            )
        )) ?? []
        let highlightCounts = Dictionary(grouping: highlights, by: \.chapterIndex)
            .mapValues(\.count)

        var collected: [Int: ChapterFacts] = [:]
        for chapter in chapters {
            collected[chapter.index] = ChapterFacts(
                utf16Length: chapter.utf16Length,
                pretranslated: chapter.pretranslatedAt != nil,
                cachedCount: store.cachedCount(
                    bookID: bookID,
                    chapterIndex: chapter.index,
                    kind: .bilingual
                ),
                highlightCount: highlightCounts[chapter.index] ?? 0
            )
        }
        facts = collected
        footprint = store.bookFootprint(bookID: bookID)
    }
}

#endif
