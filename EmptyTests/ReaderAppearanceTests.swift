import CoreGraphics
import Testing
@testable import Empty

struct ReaderAppearanceTests {
    @Test func paperPresetUsesBookishDefaults() {
        let preset = ReaderAppearance.paperPreset
        #expect(preset.theme == .wheat)
        #expect(preset.font == .serif)
        #expect(preset.contentWidth == .medium)
        #expect(preset.firstLineIndent == .classic)
        #expect(preset.paragraphSpacing == .book)
        #expect(preset.textAlignment == .justified)
        #expect(preset.chapterOpening == .outdent)
    }

    @Test func widthPresetsOrderNarrowMediumWide() {
        #expect(ReaderContentWidth.narrow.maxTextWidth(isMac: false) < ReaderContentWidth.medium.maxTextWidth(isMac: false))
        #expect(ReaderContentWidth.medium.maxTextWidth(isMac: false) < ReaderContentWidth.wide.maxTextWidth(isMac: false))
        #expect(ReaderContentWidth.narrow.scrollHorizontalPadding(viewWidth: 430, isMac: false) > ReaderContentWidth.wide.scrollHorizontalPadding(viewWidth: 430, isMac: false))
    }

    @Test func openingParagraphCanSuppressIndent() {
        let appearance = ReaderAppearance(
            theme: .paper,
            font: .serif,
            contentWidth: .medium,
            firstLineIndent: .classic,
            paragraphSpacing: .book,
            textAlignment: .justified,
            chapterOpening: .outdent
        )
        #expect(appearance.firstLineIndentPoints(fontSize: 18, isOpeningParagraph: false) == CGFloat(36))
        #expect(appearance.firstLineIndentPoints(fontSize: 18, isOpeningParagraph: true) == 0)
    }

    @Test func enlargedOpeningRaisesBodySize() {
        let appearance = ReaderAppearance(
            theme: .paper,
            font: .serif,
            contentWidth: .medium,
            firstLineIndent: .modest,
            paragraphSpacing: .book,
            textAlignment: .leading,
            chapterOpening: .enlarged
        )
        #expect(appearance.openingFontSize(base: 18, isOpeningParagraph: false) == 18)
        #expect(appearance.openingFontSize(base: 18, isOpeningParagraph: true) == 19.5)
    }

    @Test func ornamentAndEnlargedShareBodyBoost() {
        let ornament = ReaderAppearance(chapterOpening: .ornament)
        let enlarged = ReaderAppearance(chapterOpening: .enlarged)
        #expect(ornament.openingFontSize(base: 18, isOpeningParagraph: true) == enlarged.openingFontSize(base: 18, isOpeningParagraph: true))
        #expect(ornament.chapterOpening.showsChapterHeader)
        #expect(!enlarged.chapterOpening.showsChapterHeader)
    }

    @Test func dropCapEnlargesFirstCharacter() {
        let appearance = ReaderAppearance(chapterOpening: .dropCap)
        #expect(appearance.chapterOpening.usesDropCap)
        #expect(appearance.dropCapFontSize(base: 18) == 18 * 2.6)
        #expect(appearance.openingFontSize(base: 18, isOpeningParagraph: true) == 18.5)
        #expect(appearance.chapterHeaderSpacing(fontSize: 18) == 0)
    }
}
