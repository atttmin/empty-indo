//
//  ReadingSettingsView.swift
//  Empty
//

import Foundation
import SwiftUI

struct ReadingSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var theme: ReaderTheme
    @Binding var font: ReaderFont
    var pageTurn: Binding<ReaderPageTurn>? = nil
    /// When set, the panel offers 本书覆盖 — a per-book目标语言 kept on
    /// the book dimension (the global default lives in AI 状态 → 语言).
    var bookID: UUID? = nil

    @State private var bookTargetOverride: String?

    @AppStorage("reader.traditional") private var traditionalChinese = false
    @AppStorage("reader.pdf.invert") private var pdfInvert = false
    @AppStorage("reader.pdf.twoup") private var pdfTwoUp = false
    @AppStorage("reader.pdf.autocrop") private var pdfAutoCrop = false
    @AppStorage("reader.vertical.mac") private var verticalText = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("阅读设置")
                        .font(.system(size: 17, weight: .black, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text("字号 \(Int(fontSize)) · 行距 \(lineSpacing, specifier: "%.1f")")
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
            Rectangle().fill(palette.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                settingRow(label: "字号") {
                    HStack(spacing: 12) {
                        Text("A").font(.system(size: 11, design: .serif))
                        Slider(value: $fontSize, in: 12...28, step: 1)
                            .tint(palette.accent)
                        Text("A").font(.system(size: 20, design: .serif))
                    }
                    .foregroundStyle(palette.ink2)
                }
                settingRow(label: "行距") {
                    HStack(spacing: 12) {
                        Image(systemName: "text.alignleft").font(.system(size: 10))
                        Slider(value: $lineSpacing, in: 1.2...2.2, step: 0.1)
                            .tint(palette.accent)
                        Image(systemName: "text.alignleft").font(.system(size: 16))
                    }
                    .foregroundStyle(palette.ink2)
                }
                settingRow(label: "字体") {
                    HStack(spacing: 8) {
                        ForEach(ReaderFont.allCases, id: \.self) { choice in
                            fontChip(choice)
                        }
                    }
                }
                settingRow(label: "主题") {
                    HStack(spacing: 10) {
                        ForEach(ReaderTheme.allCases, id: \.self) { choice in
                            themeSwatch(choice)
                        }
                    }
                }
                if let pageTurn {
                    settingRow(label: "翻页方式") {
                        Picker("", selection: pageTurn) {
                            ForEach(ReaderPageTurn.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                settingRow(label: "繁简 · PDF") {
                    HStack(spacing: 8) {
                        optionChip("繁体显示", isOn: $traditionalChinese)
                        optionChip("PDF 夜间反色", isOn: $pdfInvert)
                        #if os(macOS)
                        optionChip("PDF 双页", isOn: $pdfTwoUp)
                        optionChip("PDF 裁边", isOn: $pdfAutoCrop)
                        optionChip("竖排（翻页·实验）", isOn: $verticalText)
                        #else
                        optionChip("PDF 裁边", isOn: $pdfAutoCrop)
                        #endif
                    }
                }
                if bookID != nil {
                    settingRow(label: "本书语言") {
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    bookLanguageChip("跟随全局", target: nil)
                                    ForEach(LanguageSettings.targetOptions, id: \.id) { option in
                                        bookLanguageChip(option.native, target: option.id)
                                    }
                                }
                            }
                            Text("只改这一本的目标语言；全局默认在 AI 状态 → 语言。")
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.ink3)
                        }
                    }
                }
                Text("\u{201C}I went to the woods because I wished to live deliberately…\u{201D}")
                    .font(.system(size: fontSize * 0.8, design: .serif))
                    .lineSpacing(fontSize * 0.8 * (lineSpacing - 1))
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .emptyCard(palette, radius: 12)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))

            Spacer(minLength: 0)
        }
        .background(palette.window)
        #if os(iOS)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            if let bookID {
                bookTargetOverride = LanguageSettings.bookOverride(for: bookID)?.target
            }
        }
    }

    private func bookLanguageChip(_ title: String, target: String?) -> some View {
        let isActive = bookTargetOverride == target
        return Button {
            guard let bookID else { return }
            bookTargetOverride = target
            var override = LanguageSettings.bookOverride(for: bookID)
                ?? LanguageSettings.BookOverride()
            override.target = target
            LanguageSettings.setBookOverride(override, for: bookID)
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? palette.onAccent : palette.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isActive ? palette.accent : palette.side, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func optionChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: isOn.wrappedValue ? .bold : .regular))
                .foregroundStyle(isOn.wrappedValue ? palette.onAccent : palette.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    isOn.wrappedValue ? palette.accent : palette.side,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func fontChip(_ choice: ReaderFont) -> some View {
        Button {
            font = choice
        } label: {
            Text(choice.title)
                .font(.system(size: 12.5, weight: font == choice ? .bold : .regular))
                .foregroundStyle(font == choice ? palette.onAccent : palette.ink2)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    font == choice ? palette.accent : palette.side,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        font == choice ? palette.accent : palette.line2,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func themeSwatch(_ choice: ReaderTheme) -> some View {
        Button {
            theme = choice
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(choice.swatch)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(
                            theme == choice ? palette.accent : palette.line2,
                            lineWidth: theme == choice ? 2 : 1
                        )
                    )
                    .overlay {
                        if theme == choice {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    choice.isDarkCanvas(baseIsDark: false)
                                        ? Color(hex: 0xEDE5D4) : Color(hex: 0x2A2419)
                                )
                        }
                    }
                Text(choice.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme == choice ? palette.accent : palette.ink3)
            }
        }
        .buttonStyle(.plain)
    }

    private func settingRow(
        label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(palette.ink3)
            content()
        }
    }
}
