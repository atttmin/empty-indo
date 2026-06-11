//
//  NativeChapterSelectionSheet.swift
//  Empty
//

import Foundation
import SwiftUI

struct NativeChapterSelectionSheet: View {
    let title: String
    let chapterText: String
    let highlights: [HighlightPaint]
    let fontSize: Double
    let lineSpacing: Double
    let initialSelection: ReaderSelection?
    let onApply: (ReaderSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette
    @State private var draftSelection: ReaderSelection?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                NativeSelectableTextBlockView(
                    text: chapterText,
                    fontSize: max(16, fontSize),
                    lineSpacing: max(4, CGFloat((lineSpacing - 1) * max(16, fontSize))),
                    weight: .regular,
                    tone: .primary,
                    highlightRanges: chapterHighlightRanges(),
                    isDark: palette.isDark,
                    clearSelection: false,
                    onSelectionChange: { range in
                        guard let range else {
                            draftSelection = nil
                            return
                        }
                        draftSelection = ReaderSelectionContext.selection(
                            in: chapterText,
                            utf16Range: range
                        )
                    }
                )
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            footer
        }
        .background(palette.window)
        .onAppear {
            draftSelection = initialSelection
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 720, minHeight: 620)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("跨段选取")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text(title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink3)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.ink3)
            }
            Text("在整章文本里连续选取，完成后回到阅读器继续解释、翻译或高亮。")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.ink3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let draftSelection {
                Text(draftSelection.text)
                    .font(.system(size: 13.5, weight: .medium, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(3)
            } else {
                Text("先在正文里拖拽或长按选择需要的跨段文本。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink3)
            }

            HStack(spacing: 10) {
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.ink3)
                Spacer()
                Button {
                    guard let draftSelection else { return }
                    onApply(draftSelection)
                    dismiss()
                } label: {
                    Text("使用选区")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(draftSelection == nil)
                .opacity(draftSelection == nil ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(palette.side)
    }

    private func chapterHighlightRanges() -> [Range<Int>] {
        let ranges = highlights.compactMap { highlight -> Range<Int>? in
            if let start = highlight.startUTF16,
               let end = highlight.endUTF16,
               end > start {
                return start..<min(end, chapterText.utf16.count)
            }
            let needle = highlight.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return nil }
            return PlainTextSearch.utf16Range(of: needle, in: chapterText)
        }
        return mergeRanges(ranges)
    }

    private func mergeRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.sorted {
            if $0.lowerBound != $1.lowerBound {
                return $0.lowerBound < $1.lowerBound
            }
            return $0.upperBound < $1.upperBound
        }
        var merged: [Range<Int>] = []
        for range in sorted {
            guard !range.isEmpty else { continue }
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
