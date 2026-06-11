//
//  ChapterListView.swift
//  Empty
//

import SwiftUI

/// 目录 in the 朱批 language: serif header, numbered rows, read chapters
/// dimmed, the current one carrying the vermilion 正在读 chip. Opens
/// scrolled to where the reader is.
struct ChapterListView: View {
    let titles: [String]
    /// "章" for EPUB chapters, "页" for PDF pages.
    var unitLabel: String = "章"
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.line).frame(height: 1)

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
}
