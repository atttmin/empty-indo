//
//  ReaderAppearance.swift
//  Empty
//
//  Reader-surface appearance: canvas themes (微信读书-style background
//  swatches, in the 朱批 voice) and body-text font choices. These apply
//  to the reading canvas only — the app shell keeps its own palette.
//

import SwiftUI

/// Reader canvas theme — the design handoff's four: 纸白 / 暖纸 / 夜读 /
/// 墨黑. `paper` follows the app palette (warm paper in light, night-read
/// in dark); the rest pin the canvas regardless of the shell theme.
nonisolated enum ReaderTheme: String, CaseIterable {
    case paper
    case wheat
    case night
    case inkblack

    var title: String {
        switch self {
        case .paper: "纸白"
        case .wheat: "暖纸"
        case .night: "夜读"
        case .inkblack: "墨黑"
        }
    }

    /// The palette the reading surface should run under.
    func palette(base: EmptyPalette) -> EmptyPalette {
        switch self {
        case .paper:
            return base
        case .wheat:
            var palette = EmptyPalette.light
            palette.window = Color(hex: 0xEFE3CC)
            palette.side = Color(hex: 0xE7D8BB)
            palette.line = Color(hex: 0xDCCAA6)
            palette.line2 = Color(hex: 0xCFBA90)
            palette.ink = Color(hex: 0x46391F)
            palette.ink2 = Color(hex: 0x6B5B3A)
            return palette
        case .night:
            var palette = EmptyPalette.dark
            palette.window = Color(hex: 0x2A241C)
            palette.side = Color(hex: 0x322B21)
            palette.card = Color(hex: 0x352D23)
            palette.ink = Color(hex: 0xC9BFAC)
            palette.ink2 = Color(hex: 0xA89D89)
            return palette
        case .inkblack:
            var palette = EmptyPalette.dark
            palette.window = Color(hex: 0x0D0C0A)
            palette.side = Color(hex: 0x171511)
            palette.card = Color(hex: 0x1B1915)
            palette.ink = Color(hex: 0xA89F8D)
            palette.ink2 = Color(hex: 0x8A8273)
            palette.line = Color(hex: 0x26231D)
            palette.line2 = Color(hex: 0x333028)
            return palette
        }
    }

    /// Whether the canvas is dark, given the shell theme (only `paper`
    /// follows the shell).
    func isDarkCanvas(baseIsDark: Bool) -> Bool {
        switch self {
        case .paper: baseIsDark
        case .night, .inkblack: true
        case .wheat: false
        }
    }

    /// Body-text colors for the native text views (primary, secondary).
    func inkHexes(baseIsDark: Bool) -> (primary: UInt32, secondary: UInt32) {
        switch self {
        case .paper:
            return baseIsDark ? (0xEDE5D4, 0xC4B9A4) : (0x3A332A, 0x5C5443)
        case .wheat:
            return (0x46391F, 0x6B5B3A)
        case .night:
            return (0xC9BFAC, 0xA89D89)
        case .inkblack:
            return (0xA89F8D, 0x8A8273)
        }
    }

    /// Paged mode: inner paper card fill.
    func pageFill(baseIsDark: Bool) -> Color {
        switch self {
        case .paper:
            return baseIsDark ? Color(hex: 0x241F18) : Color(hex: 0xFBF7EF)
        case .wheat:
            return Color(hex: 0xF4E8D1)
        case .night:
            return Color(hex: 0x312920)
        case .inkblack:
            return Color(hex: 0x14120F)
        }
    }

    /// Paged mode: paper-card border / gutter rule.
    func pageRule(baseIsDark: Bool) -> Color {
        switch self {
        case .paper:
            return baseIsDark ? Color(hex: 0x3B342A) : Color(hex: 0xE0D4C0)
        case .wheat:
            return Color(hex: 0xD8C29A)
        case .night:
            return Color(hex: 0x433A2E)
        case .inkblack:
            return Color(hex: 0x2B261F)
        }
    }

    /// Swatch fill for the settings picker.
    var swatch: Color {
        switch self {
        case .paper: Color(hex: 0xF7F2E9)
        case .wheat: Color(hex: 0xEFE3CC)
        case .night: Color(hex: 0x2A241C)
        case .inkblack: Color(hex: 0x0D0C0A)
        }
    }
}

/// Reader body-text font. `serif` is the system serif the reader shipped
/// with; 宋体 / 楷体 are the classic CJK book faces; 黑体 is the system
/// sans for readers who prefer it.
nonisolated enum ReaderFont: String, CaseIterable {
    case serif
    case song
    case kai
    case sans

    var title: String {
        switch self {
        case .serif: "衬线"
        case .song: "宋体"
        case .kai: "楷体"
        case .sans: "黑体"
        }
    }

    /// Named font family to resolve, or nil for a system design.
    var familyName: String? {
        switch self {
        case .serif, .sans: nil
        case .song: "Songti SC"
        case .kai: "Kaiti SC"
        }
    }

    var usesSerifDesign: Bool {
        self == .serif
    }
}

/// Reader text block width — narrower text columns feel more like a page and
/// reduce phone-edge crowding.
nonisolated enum ReaderContentWidth: String, CaseIterable {
    case narrow
    case medium
    case wide

    var title: String {
        switch self {
        case .narrow: "窄"
        case .medium: "中"
        case .wide: "宽"
        }
    }

    func maxTextWidth(isMac: Bool) -> CGFloat {
        switch self {
        case .narrow: isMac ? 620 : 540
        case .medium: isMac ? 700 : 620
        case .wide: isMac ? 780 : 720
        }
    }

    func scrollHorizontalPadding(viewWidth: CGFloat, isMac: Bool) -> CGFloat {
        switch (self, isMac) {
        case (.narrow, true):
            max(56, min(112, viewWidth * 0.14))
        case (.medium, true):
            max(46, min(96, viewWidth * 0.12))
        case (.wide, true):
            max(34, min(74, viewWidth * 0.09))
        case (.narrow, false):
            max(28, min(42, viewWidth * 0.11))
        case (.medium, false):
            max(22, min(34, viewWidth * 0.08))
        case (.wide, false):
            max(16, min(24, viewWidth * 0.05))
        }
    }

    func pagedHorizontalInset(viewWidth: CGFloat, isMac: Bool) -> CGFloat {
        switch (self, isMac) {
        case (.narrow, true):
            max(86, min(144, viewWidth * 0.14))
        case (.medium, true):
            max(72, min(128, viewWidth * 0.11))
        case (.wide, true):
            max(56, min(108, viewWidth * 0.08))
        case (.narrow, false):
            max(32, min(52, viewWidth * 0.11))
        case (.medium, false):
            max(24, min(40, viewWidth * 0.08))
        case (.wide, false):
            max(18, min(30, viewWidth * 0.05))
        }
    }
}

/// Book-style first-line indentation for continuous prose.
nonisolated enum ReaderFirstLineIndent: String, CaseIterable {
    case none
    case modest
    case classic

    var title: String {
        switch self {
        case .none: "无"
        case .modest: "1.5 格"
        case .classic: "2 格"
        }
    }

    func points(fontSize: Double) -> CGFloat {
        switch self {
        case .none: 0
        case .modest: CGFloat(fontSize * 1.5)
        case .classic: CGFloat(fontSize * 2.0)
        }
    }
}

/// Paragraph rhythm: denser for manuals, looser for essays.
nonisolated enum ReaderParagraphSpacingStyle: String, CaseIterable {
    case tight
    case book
    case airy

    var title: String {
        switch self {
        case .tight: "紧"
        case .book: "书卷"
        case .airy: "疏朗"
        }
    }

    func blockPadding(fontSize: Double) -> CGFloat {
        switch self {
        case .tight: max(4, fontSize * 0.22)
        case .book: max(7, fontSize * 0.34)
        case .airy: max(10, fontSize * 0.46)
        }
    }

    func paragraphSpacing(fontSize: Double) -> CGFloat {
        switch self {
        case .tight: CGFloat(fontSize * 0.46)
        case .book: CGFloat(fontSize * 0.62)
        case .airy: CGFloat(fontSize * 0.82)
        }
    }
}

nonisolated enum ReaderTextAlignmentStyle: String, CaseIterable {
    case leading
    case justified

    var title: String {
        switch self {
        case .leading: "左对齐"
        case .justified: "两端对齐"
        }
    }

    var usesJustifiedText: Bool {
        self == .justified
    }
}

/// Chapter opening: keep the first paragraph quieter, treat it like a
/// section opener, or add book-style ornament (small chapter title +
/// decorative rule / drop cap).
nonisolated enum ReaderChapterOpeningStyle: String, CaseIterable {
    case outdent
    case enlarged
    case ornament
    case dropCap
    case plain

    var title: String {
        switch self {
        case .outdent: "首段不缩进"
        case .enlarged: "首段放大"
        case .ornament: "章首饰线"
        case .dropCap: "首字下沉"
        case .plain: "简洁章首"
        }
    }

    /// Whether the opening paragraph should also render a chapter header
    /// (small title + decorative rule) above the first paragraph.
    var showsChapterHeader: Bool {
        self == .ornament
    }

    /// Whether the opening paragraph should enlarge its first character.
    var usesDropCap: Bool {
        self == .dropCap
    }
}

/// Everything the reading canvas needs to draw itself.
nonisolated struct ReaderAppearance: Equatable {
    var theme: ReaderTheme = .paper
    var font: ReaderFont = .serif
    var contentWidth: ReaderContentWidth = .medium
    var firstLineIndent: ReaderFirstLineIndent = .none
    var paragraphSpacing: ReaderParagraphSpacingStyle = .book
    var textAlignment: ReaderTextAlignmentStyle = .leading
    var chapterOpening: ReaderChapterOpeningStyle = .plain

    static let paperPreset = ReaderAppearance(
        theme: .wheat,
        font: .serif,
        contentWidth: .medium,
        firstLineIndent: .classic,
        paragraphSpacing: .book,
        textAlignment: .justified,
        chapterOpening: .outdent
    )

    func scrollHorizontalPadding(viewWidth: CGFloat, isMac: Bool) -> CGFloat {
        contentWidth.scrollHorizontalPadding(viewWidth: viewWidth, isMac: isMac)
    }

    func pagedHorizontalInset(viewWidth: CGFloat, isMac: Bool) -> CGFloat {
        contentWidth.pagedHorizontalInset(viewWidth: viewWidth, isMac: isMac)
    }

    func maxTextWidth(isMac: Bool) -> CGFloat {
        contentWidth.maxTextWidth(isMac: isMac)
    }

    func blockPadding(fontSize: Double) -> CGFloat {
        paragraphSpacing.blockPadding(fontSize: fontSize)
    }

    func paragraphSpacing(fontSize: Double) -> CGFloat {
        paragraphSpacing.paragraphSpacing(fontSize: fontSize)
    }

    func firstLineIndentPoints(fontSize: Double, isOpeningParagraph: Bool) -> CGFloat {
        if isOpeningParagraph, chapterOpening != .plain {
            return 0
        }
        return firstLineIndent.points(fontSize: fontSize)
    }

    func openingFontSize(base: Double, isOpeningParagraph: Bool) -> Double {
        guard isOpeningParagraph else { return base }
        switch chapterOpening {
        case .enlarged, .ornament: return base + 1.5
        case .dropCap: return base + 0.5
        case .outdent, .plain: return base
        }
    }

    /// Size of the first character when using a drop-cap opening.
    func dropCapFontSize(base: Double) -> Double {
        base * 2.6
    }

    /// Vertical offset to visually seat a drop cap on the first baseline.
    func dropCapBaselineOffset(base: Double) -> CGFloat {
        base * 0.22
    }

    /// Vertical clearance consumed by a chapter-header ornament.
    func chapterHeaderSpacing(fontSize: Double) -> CGFloat {
        chapterOpening.showsChapterHeader ? max(18, fontSize * 1.2) : 0
    }
}

/// How the iOS reader advances text (Mac always scrolls).
nonisolated enum ReaderPageTurn: String, CaseIterable {
    case paged
    case scroll

    var title: String {
        switch self {
        case .paged: "左右翻页"
        case .scroll: "上下滚动"
        }
    }
}
