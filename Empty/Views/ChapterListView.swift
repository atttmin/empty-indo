//
//  ChapterListView.swift
//  Empty
//

import SwiftUI
import SwiftData

/// 目录 in the 朱批 language: serif header, numbered rows, read chapters
/// dimmed, the current one carrying the vermilion 正在读 chip. Opens
/// scrolled to where the reader is.
nonisolated enum ChapterListTab: String, CaseIterable, Sendable {
    case toc = "目录"
    case bookmarks = "书签"
    case search = "搜索"
}

struct ChapterListView: View {
    let titles: [String]
    /// "章" for EPUB chapters, "页" for PDF pages.
    var unitLabel: String
    let currentIndex: Int
    let book: Book?
    let currentPosition: ReadingPosition
    let onSelect: (Int) -> Void
    let onJump: (ReadingPosition) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext


    @State private var tab: ChapterListTab
    @State private var bookmarks: [Bookmark] = []
    @State private var searchQuery = ""
    @State private var searchRead: [BookSearchHit] = []
    @State private var searchUnread: [BookSearchHit] = []
    @State private var unreadExpanded = false

    init(
        titles: [String],
        unitLabel: String = "章",
        currentIndex: Int,
        book: Book? = nil,
        currentPosition: ReadingPosition? = nil,
        initialTab: ChapterListTab = .toc,
        onSelect: @escaping (Int) -> Void,
        onJump: @escaping (ReadingPosition) -> Void = { _ in }
    ) {
        self.titles = titles
        self.unitLabel = unitLabel
        self.currentIndex = currentIndex
        self.book = book
        self.currentPosition = currentPosition ?? ReadingPosition(
            chapterIndex: currentIndex,
            utf16Offset: 0
        )
        self.onSelect = onSelect
        self.onJump = onJump
        _tab = State(initialValue: initialTab)
    }

    private var showsDrawerTabs: Bool { book != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsDrawerTabs {
                tabRow
            }
            Rectangle().fill(palette.line).frame(height: 1)

            switch tab {
            case .toc:
                tocList
            case .bookmarks:
                bookmarkList
            case .search:
                searchPane
            }
        }
        .background(palette.window)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("目录")
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("共 \(titles.count) \(unitLabel) · 正在读第 \(currentIndex + 1) \(unitLabel)")
                    .font(.system(size: 11))
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
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 16))
    }

    private var tabRow: some View {
        HStack(spacing: 18) {
            ForEach(ChapterListTab.allCases, id: \.self) { choice in
                Button {
                    tab = choice
                } label: {
                    Text(choice.rawValue)
                        .font(.system(size: 12, weight: tab == choice ? .bold : .regular))
                        .foregroundStyle(tab == choice ? palette.accent : palette.ink3)
                        .padding(.bottom, 5)
                        .overlay(alignment: .bottom) {
                            if tab == choice {
                                Capsule().fill(palette.accent).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("reader.drawer.\(choice.rawValue)")
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
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
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 16, trailing: 12))
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    private var bookmarkList: some View {
        ScrollView {
            VStack(spacing: 8) {
                if bookmarks.isEmpty {
                    emptyMessage("还没有书签 — 阅读时点顶部书签按钮留一枚。")
                        .padding(.top, 28)
                }
                ForEach(bookmarks) { bookmark in
                    bookmarkRow(bookmark)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 18, trailing: 12))
        }
        .task(id: currentPosition) { reloadBookmarks() }
        .onAppear { reloadBookmarks() }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            onJump(ReadingPosition(
                chapterIndex: bookmark.chapterIndex,
                utf16Offset: bookmark.utf16Offset
            ))
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
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
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                }
                Text(bookmark.snippet)
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.bookmark.hit")
    }

    private func reloadBookmarks() {
        guard let book else {
            bookmarks = []
            return
        }
        bookmarks = (try? BookmarkStore(modelContext: modelContext).bookmarks(for: book)) ?? []
    }

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink3)
                TextField("全文搜索…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
                    .submitLabel(.search)
                    .accessibilityIdentifier("reader.search.field")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 8) {
                    if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        emptyMessage("输入至少两个字开始搜索。")
                            .padding(.top, 24)
                    }
                    ForEach(searchRead) { hit in
                        searchHitRow(hit)
                    }
                    if !searchUnread.isEmpty {
                        unreadSection
                    }
                    if searchRead.isEmpty && searchUnread.isEmpty
                        && searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        emptyMessage("没有找到「\(searchQuery)」。")
                            .padding(.top, 24)
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 18, trailing: 12))
            }
        }
        .task(id: searchQuery) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private var unreadSection: some View {
        Group {
            if unreadExpanded {
                Text("未读章节（可能剧透）")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                ForEach(searchUnread) { hit in
                    searchHitRow(hit)
                }
            } else {
                Button {
                    unreadExpanded = true
                } label: {
                    Text("未读章节中还有 \(searchUnread.count) 处 · 点开（可能剧透）")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(palette.line2, style: StrokeStyle(dash: [4, 4]))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func searchHitRow(_ hit: BookSearchHit) -> some View {
        Button {
            onJump(ReadingPosition(
                chapterIndex: hit.chapterIndex,
                utf16Offset: hit.utf16Offset
            ))
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapterLabel(hit.chapterIndex))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.ink3)
                Text(hit.snippet)
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .accessibilityIdentifier("reader.search.hit")
        .buttonStyle(.plain)
    }

    private func runSearch() {
        guard let book else {
            searchRead = []
            searchUnread = []
            return
        }
        unreadExpanded = false
        let result = (try? BookTextSearch(modelContext: modelContext).search(
            book: book,
            query: searchQuery,
            maxReadChapter: max(currentIndex, book.position.chapterIndex)
        )) ?? (read: [], unread: [])
        searchRead = result.read
        searchUnread = result.unread
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(palette.ink3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
    }

    private func row(index: Int, title: String) -> some View {
        let isCurrent = index == currentIndex
        let isRead = index < currentIndex
        let display = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "第 \(index + 1) \(unitLabel)"
            : title
        return Button {
            onSelect(index)
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 11, design: .serif).monospacedDigit())
                    .foregroundStyle(isCurrent ? palette.accent : palette.ink3)
                    .frame(width: 24, alignment: .trailing)
                Text(display)
                    .font(.system(size: 13.5, weight: isCurrent ? .bold : .regular))
                    .foregroundStyle(
                        isCurrent ? palette.accent : (isRead ? palette.ink3 : palette.ink)
                    )
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isCurrent {
                    Text("正在读")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(palette.accent, in: Capsule())
                } else if isRead {
                    Text("读过")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.ink3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isCurrent ? palette.accentSoft : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func chapterLabel(_ index: Int) -> String {
        let title = titles.indices.contains(index) ? titles[index] : ""
        let display = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "第 \(index + 1) \(unitLabel)"
            : title
        return "\(RomanNumeral.format(index + 1)) · \(display)"
    }
}
