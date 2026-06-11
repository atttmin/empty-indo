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

/// Everything the reading canvas needs to draw itself.
nonisolated struct ReaderAppearance: Equatable {
    var theme: ReaderTheme = .paper
    var font: ReaderFont = .serif
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
