//
//  BookExportView.swift
//  Empty
//
//  P1 导出: toggle 高亮/批注/书签, pick Markdown ⇄ 纯文本, watch the
//  preview re-render live, copy in one tap. Every entry carries an
//  empty:// link back to its exact passage.
//

import SwiftUI

struct BookExportView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext

    @State private var options = BookExportOptions()
    @State private var rendered = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    toggleChip("高亮", isOn: $options.includeHighlights)
                    toggleChip("批注", isOn: $options.includeNotes)
                    toggleChip("书签", isOn: $options.includeBookmarks)
                    Spacer()
                    Picker("", selection: $options.format) {
                        ForEach(BookExportOptions.Format.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }

                ScrollView {
                    Text(rendered)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(palette.line, lineWidth: 1)
                )

                HStack {
                    Text("每条都带 empty:// 回链，可跳回原文段落。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.ink3)
                    Spacer()
                    Button {
                        copyRendered()
                    } label: {
                        Text(copied ? "已复制 ✓" : "复制全部")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(palette.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18))
        }
        .background(palette.window)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task(id: options) {
            render()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("导出摘录")
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text(book.title)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
                    .lineLimit(1)
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
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 12, trailing: 14))
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isOn.wrappedValue ? .bold : .regular))
                .foregroundStyle(isOn.wrappedValue ? palette.onAccent : palette.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isOn.wrappedValue ? palette.accent : palette.side,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func render() {
        rendered = (try? BookExporter(modelContext: modelContext)
            .export(book: book, options: options)) ?? ""
        copied = false
    }

    private func copyRendered() {
        #if os(iOS)
        UIPasteboard.general.string = rendered
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rendered, forType: .string)
        #endif
        copied = true
    }
}
