//
//  ReaderAppearance.swift
//  Empty
//
//  Reader-surface appearance: canvas themes (微信读书-style background
//  swatches, in the 朱批 voice) and body-text font choices. These apply
//  to the reading canvas only — the app shell keeps its own palette.
//

import SwiftUI

/// Reader canvas theme. `paper` follows the app palette (warm paper in
/// light, night-read in dark); the rest pin the canvas regardless of the
/// shell theme.
nonisolated enum ReaderTheme: String, CaseIterable {
    case paper
    case white
    case wheat
    case green
    case night

    var title: String {
        switch self {
        case .paper: "纸色"
        case .white: "月白"
        case .wheat: "米黄"
        case .green: "竹青"
        case .night: "玄夜"
        }
    }

    /// The palette the reading surface should run under.
    func palette(base: EmptyPalette) -> EmptyPalette {
        switch self {
        case .paper:
            return base
        case .night:
            return .dark
        case .white:
            var palette = EmptyPalette.light
            palette.window = Color(hex: 0xFDFDFA)
            palette.side = Color(hex: 0xF3F2EC)
            palette.line = Color(hex: 0xE8E6DD)
            palette.line2 = Color(hex: 0xDBD8CC)
            return palette
        case .wheat:
            var palette = EmptyPalette.light
            palette.window = Color(hex: 0xF3E5C8)
            palette.side = Color(hex: 0xECDBB8)
            palette.line = Color(hex: 0xDFD0AC)
            palette.line2 = Color(hex: 0xD2C198)
            return palette
        case .green:
            var palette = EmptyPalette.light
            palette.window = Color(hex: 0xD5E6D0)
            palette.side = Color(hex: 0xC8DDC2)
            palette.line = Color(hex: 0xBBD2B4)
            palette.line2 = Color(hex: 0xA9C4A1)
            return palette
        }
    }

    /// Whether the canvas is dark, given the shell theme (only `paper`
    /// follows the shell).
    func isDarkCanvas(baseIsDark: Bool) -> Bool {
        switch self {
        case .paper: baseIsDark
        case .night: true
        case .white, .wheat, .green: false
        }
    }

    /// Body-text colors for the native text views (primary, secondary).
    func inkHexes(baseIsDark: Bool) -> (primary: UInt32, secondary: UInt32) {
        if isDarkCanvas(baseIsDark: baseIsDark) {
            return (0xEDE5D4, 0xC4B9A4)
        }
        switch self {
        case .green:
            return (0x243321, 0x4D5F48)
        case .wheat:
            return (0x33291B, 0x60543D)
        default:
            return (0x2A2419, 0x5C5443)
        }
    }

    /// Swatch fill for the settings picker.
    var swatch: Color {
        switch self {
        case .paper: Color(hex: 0xF7F2E9)
        case .white: Color(hex: 0xFDFDFA)
        case .wheat: Color(hex: 0xF3E5C8)
        case .green: Color(hex: 0xD5E6D0)
        case .night: Color(hex: 0x1F1B16)
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
