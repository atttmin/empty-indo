//
//  PagedChapterReaderView.swift
//  Empty
//
//  微信读书-style horizontal paging for the iOS EPUB reader: the chapter
//  lays out once into fixed-size TextKit pages (one NSTextStorage, one
//  NSLayoutManager, one NSTextContainer per page), and the reader swipes
//  or edge-taps between pages. Selection, highlights, 双语/导读 notes and
//  position reporting ride the same chapter-offset pipeline as the
//  scrolling reader.
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Composition

/// One block's footprint inside the composed attributed string.
private struct PagedRun {
    var blockID: String
    var paragraph: ReaderParagraph?
    /// Full range in the attributed string (marker included).
    var attrRange: NSRange
    /// Where the block's own text starts (after any list marker).
    var textLocation: Int
    /// The block's exact UTF-16 range in the chapter plain text.
    var chapterRange: Range<Int>?
}

private final class PaginatedChapter {
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let containers: [NSTextContainer]
    let runs: [PagedRun]
    let pageSize: CGSize
    let version: Int

    init(
        storage: NSTextStorage,
        layoutManager: NSLayoutManager,
        containers: [NSTextContainer],
        runs: [PagedRun],
        pageSize: CGSize,
        version: Int
    ) {
        self.storage = storage
        self.layoutManager = layoutManager
        self.containers = containers
        self.runs = runs
        self.pageSize = pageSize
        self.version = version
    }

    var pageCount: Int { containers.count }

    func characterRange(forPage index: Int) -> NSRange {
        guard containers.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        let glyphs = layoutManager.glyphRange(for: containers[index])
        return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }

    /// Chapter UTF-16 offset of the first mapped character on a page.
    func chapterOffset(forPage index: Int) -> Int? {
        let pageRange = characterRange(forPage: index)
        for run in runs {
            guard let chapterRange = run.chapterRange else { continue }
            let textEnd = run.attrRange.location + run.attrRange.length
            guard textEnd > pageRange.location else { continue }
            let attrStart = max(run.textLocation, pageRange.location)
            let delta = max(0, attrStart - run.textLocation)
            return min(chapterRange.lowerBound + delta, chapterRange.upperBound)
        }
        return nil
    }

    /// First page whose content reaches the chapter offset.
    func page(forChapterOffset offset: Int) -> Int? {
        guard let run = runs.last(where: { run in
            guard let range = run.chapterRange else { return false }
            return range.lowerBound <= offset
        }), let chapterRange = run.chapterRange else { return nil }
        let delta = max(0, min(offset, chapterRange.upperBound) - chapterRange.lowerBound)
        let attrLocation = run.textLocation + delta
        for index in containers.indices {
            let pageRange = characterRange(forPage: index)
            if attrLocation < pageRange.location + pageRange.length {
                return index
            }
        }
        return containers.indices.last
    }

    /// Paragraphs whose runs intersect the page.
    func paragraphs(onPage index: Int) -> [ReaderParagraph] {
        let pageRange = characterRange(forPage: index)
        return runs.compactMap { run in
            guard let paragraph = run.paragraph,
                  NSIntersectionRange(run.attrRange, pageRange).length > 0 else {
                return nil
            }
            return paragraph
        }
    }

    /// Maps a storage-coordinate selection to the chapter's UTF-16 range.
    func chapterRange(forAttrRange selection: NSRange) -> Range<Int>? {
        let selectionEnd = selection.location + selection.length
        let mapped = runs.compactMap { run -> Range<Int>? in
            guard let chapterRange = run.chapterRange else { return nil }
            let runTextEnd = run.attrRange.location + run.attrRange.length
            let lower = max(selection.location, run.textLocation)
            let upper = min(selectionEnd, runTextEnd)
            guard upper > lower else { return nil }
            let start = chapterRange.lowerBound + (lower - run.textLocation)
            let end = min(chapterRange.lowerBound + (upper - run.textLocation), chapterRange.upperBound)
            guard end > start else { return nil }
            return start..<end
        }
        guard let first = mapped.first, let last = mapped.last else { return nil }
        return first.lowerBound..<last.upperBound
    }
}

private struct PageComposer {
    let document: NativeChapterDocument
    let blockSpans: [String: NativeTextBlockSpan]
    let chapterPlainText: String?
    let basePath: URL
    let chapterHref: String
    let fontSize: Double
    let lineSpacing: Double
    let appearance: ReaderAppearance
    let isDarkCanvas: Bool
    let inlineMode: InlineNoteKind
    let inlineNotes: [InlineNotePaint]
    let highlights: [HighlightPaint]
    let pageSize: CGSize

    func compose(version: Int) -> PaginatedChapter {
        let (attributed, runs) = buildAttributed()
        paintHighlights(on: attributed, runs: runs)

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)
            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.location + glyphRange.length >= layoutManager.numberOfGlyphs {
                break
            }
        } while containers.count < 1200

        return PaginatedChapter(
            storage: storage,
            layoutManager: layoutManager,
            containers: containers,
            runs: runs,
            pageSize: pageSize,
            version: version
        )
    }

    // MARK: Attributed text

    private var inkPrimary: UIColor {
        let hexes = appearance.theme.inkHexes(baseIsDark: isDarkCanvas)
        return UIColor(hex: hexes.primary)
    }

    private var inkSecondary: UIColor {
        let hexes = appearance.theme.inkHexes(baseIsDark: isDarkCanvas)
        return UIColor(hex: hexes.secondary)
    }

    private var accent: UIColor {
        UIColor(hex: appearance.theme.isDarkCanvas(baseIsDark: isDarkCanvas) ? 0xD86B47 : 0xB5482A)
    }

    private func bodyFont(size: Double, bold: Bool = false) -> UIFont {
        if let family = appearance.font.familyName {
            var descriptor = UIFontDescriptor(fontAttributes: [.family: family])
            if bold, let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) {
                descriptor = boldDescriptor
            }
            let font = UIFont(descriptor: descriptor, size: size)
            if font.familyName == family { return font }
        }
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard appearance.font.usesSerifDesign,
              let descriptor = base.fontDescriptor.withDesign(.serif) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func paragraphStyle(
        spacingBefore: CGFloat = 0,
        spacing: CGFloat,
        headIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(3, CGFloat((lineSpacing - 1) * fontSize))
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = spacingBefore
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        return style
    }

    private func buildAttributed() -> (NSMutableAttributedString, [PagedRun]) {
        let result = NSMutableAttributedString()
        var runs: [PagedRun] = []

        func appendBlockText(
            _ block: NativeChapterBlock,
            text: String,
            marker: String = "",
            attributes: [NSAttributedString.Key: Any]
        ) {
            let start = result.length
            let full = marker + text
            result.append(NSAttributedString(string: full, attributes: attributes))
            runs.append(PagedRun(
                blockID: block.id,
                paragraph: block.readerParagraph,
                attrRange: NSRange(location: start, length: full.utf16.count),
                textLocation: start + marker.utf16.count,
                chapterRange: blockSpans[block.id]?.chapterRange
            ))
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }

        func appendNote(for paragraph: ReaderParagraph) {
            guard inlineMode != .none,
                  let note = inlineNotes.first(where: { $0.idx == paragraph.idx }),
                  !note.failed,
                  !note.text.isEmpty else { return }
            let label = inlineMode == .bilingual ? "译" : "导读"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont(size: max(13, fontSize - 2.5)),
                .foregroundColor: inkSecondary,
                .paragraphStyle: paragraphStyle(spacing: fontSize * 0.7, headIndent: 14),
            ]
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(10, fontSize - 7), weight: .bold),
                .foregroundColor: accent,
                .paragraphStyle: paragraphStyle(spacing: fontSize * 0.7, headIndent: 14),
            ]
            result.append(NSAttributedString(string: "\(label) · ", attributes: labelAttributes))
            result.append(NSAttributedString(string: note.text + "\n", attributes: attributes))
        }

        for block in document.blocks {
            switch block {
            case .heading(_, let level, let text):
                let size = fontSize + [10.0, 6, 3, 1, 1, 1][min(max(level - 1, 0), 5)]
                appendBlockText(block, text: text, attributes: [
                    .font: bodyFont(size: size, bold: true),
                    .foregroundColor: inkPrimary,
                    .paragraphStyle: paragraphStyle(
                        spacingBefore: fontSize * (level <= 2 ? 1.1 : 0.7),
                        spacing: fontSize * 0.7
                    ),
                ])

            case .paragraph(_, _, let text):
                appendBlockText(block, text: text, attributes: [
                    .font: bodyFont(size: fontSize),
                    .foregroundColor: inkPrimary,
                    .paragraphStyle: paragraphStyle(spacing: fontSize * 0.62),
                ])
                if let paragraph = block.readerParagraph { appendNote(for: paragraph) }

            case .quote(_, _, let text):
                appendBlockText(block, text: text, attributes: [
                    .font: bodyFont(size: fontSize),
                    .foregroundColor: inkSecondary,
                    .paragraphStyle: paragraphStyle(spacing: fontSize * 0.62, headIndent: 16),
                ])
                if let paragraph = block.readerParagraph { appendNote(for: paragraph) }

            case .listItem(_, _, let text, let level, let marker):
                appendBlockText(block, text: text, marker: marker + " ", attributes: [
                    .font: bodyFont(size: fontSize),
                    .foregroundColor: inkPrimary,
                    .paragraphStyle: paragraphStyle(
                        spacing: fontSize * 0.45,
                        headIndent: CGFloat(max(0, level - 1)) * 18 + 4
                    ),
                ])
                if let paragraph = block.readerParagraph { appendNote(for: paragraph) }

            case .footnote(_, _, let text):
                appendBlockText(block, text: text, marker: "注 · ", attributes: [
                    .font: bodyFont(size: max(12, fontSize - 2.5)),
                    .foregroundColor: inkSecondary,
                    .paragraphStyle: paragraphStyle(spacing: fontSize * 0.55, headIndent: 10),
                ])
                if let paragraph = block.readerParagraph { appendNote(for: paragraph) }

            case .code(_, let text):
                appendBlockText(block, text: text, attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: max(12, fontSize - 3), weight: .regular),
                    .foregroundColor: inkPrimary,
                    .paragraphStyle: paragraphStyle(spacing: fontSize * 0.62, headIndent: 8),
                ])

            case .table(_, let rows):
                let text = rows
                    .map { $0.joined(separator: "  ·  ") }
                    .joined(separator: "\n")
                guard !text.isEmpty else { continue }
                result.append(NSAttributedString(
                    string: text + "\n",
                    attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: max(11, fontSize - 4), weight: .regular),
                        .foregroundColor: inkSecondary,
                        .paragraphStyle: paragraphStyle(spacing: fontSize * 0.62, headIndent: 8),
                    ]
                ))

            case .image(_, let source, let alt):
                appendImage(source: source, alt: alt, into: result)
            }
        }

        if result.length == 0 {
            result.append(NSAttributedString(
                string: " ",
                attributes: [.font: bodyFont(size: fontSize)]
            ))
        }
        return (result, runs)
    }

    private func appendImage(source: String, alt: String?, into result: NSMutableAttributedString) {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = fontSize * 0.8
        centered.paragraphSpacingBefore = fontSize * 0.5

        if let image = loadImage(source: source) {
            let maxWidth = max(40, pageSize.width - 2)
            let maxHeight = max(80, pageSize.height * 0.62)
            let scale = min(1, min(maxWidth / image.size.width, maxHeight / image.size.height))
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(
                x: 0,
                y: 0,
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttribute(
                .paragraphStyle,
                value: centered,
                range: NSRange(location: 0, length: attachmentString.length)
            )
            result.append(attachmentString)
            result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: centered]))
        }

        if let alt, !alt.isEmpty {
            result.append(NSAttributedString(
                string: alt + "\n",
                attributes: [
                    .font: bodyFont(size: max(11, fontSize - 5)),
                    .foregroundColor: inkSecondary,
                    .paragraphStyle: centered,
                ]
            ))
        }
    }

    private func loadImage(source: String) -> UIImage? {
        let cleaned = source.components(separatedBy: "#").first ?? source
        let chapterDirectory = basePath
            .appendingPathComponent(chapterHref)
            .deletingLastPathComponent()
        let url: URL
        if cleaned.hasPrefix("/") {
            url = basePath.appendingPathComponent(String(cleaned.dropFirst()))
        } else {
            url = chapterDirectory.appendingPathComponent(cleaned)
        }
        return UIImage(contentsOfFile: url.path)
    }

    private func paintHighlights(on attributed: NSMutableAttributedString, runs: [PagedRun]) {
        let gold = UIColor(hex: 0xDEB248).withAlphaComponent(
            appearance.theme.isDarkCanvas(baseIsDark: isDarkCanvas) ? 0.28 : 0.4
        )
        for highlight in highlights {
            guard let start = highlight.startUTF16,
                  let end = highlight.endUTF16,
                  end > start else { continue }
            for run in runs {
                guard let chapterRange = run.chapterRange,
                      let local = NativeTextBlockSpan(
                        blockID: run.blockID,
                        chapterRange: chapterRange,
                        paragraphInfo: nil
                      ).localRange(intersecting: start..<end) else { continue }
                let runTextLength = run.attrRange.length - (run.textLocation - run.attrRange.location)
                let lower = min(local.lowerBound, runTextLength)
                let upper = min(local.upperBound, runTextLength)
                guard upper > lower else { continue }
                attributed.addAttribute(
                    .backgroundColor,
                    value: gold,
                    range: NSRange(location: run.textLocation + lower, length: upper - lower)
                )
            }
        }
    }
}

// MARK: - SwiftUI view

struct PagedChapterReaderView: View {
    let chapter: EPUBChapter
    let basePath: URL
    let fontSize: Double
    let lineSpacing: Double
    let landing: ChapterLanding
    let resumeUTF16Offset: Int
    let chapterPlainText: String?
    let highlights: [HighlightPaint]
    let inlineMode: InlineNoteKind
    let inlineNotes: [InlineNotePaint]
    var appearance: ReaderAppearance = ReaderAppearance()
    var selectionActive: Bool = false
    var onTap: () -> Void = {}
    var onChapterBoundary: (PageTurnDirection) -> Void = { _ in }
    var onSelectionChange: (ReaderSelection?) -> Void = { _ in }
    var onPositionChange: (String) -> Void = { _ in }
    var onVisibleParagraphs: ([ReaderParagraph]) -> Void = { _ in }
    var onPageInfo: (Int, Int) -> Void = { _, _ in }

    private let document: NativeChapterDocument
    private let blockSpans: [String: NativeTextBlockSpan]

    @Environment(\.emptyPalette) private var palette
    @State private var paginated: PaginatedChapter?
    @State private var pageIndex = 0
    @State private var composeVersion = 0
    @State private var lastComposeKey: ComposeKey?

    private struct ComposeKey: Equatable {
        var width: CGFloat
        var height: CGFloat
        var fontSize: Double
        var lineSpacing: Double
        var appearance: ReaderAppearance
        var isDark: Bool
        var inlineMode: InlineNoteKind
        var noteFingerprint: Int
        var highlightFingerprint: Int
    }

    init(
        chapter: EPUBChapter,
        basePath: URL,
        fontSize: Double,
        lineSpacing: Double,
        landing: ChapterLanding,
        resumeUTF16Offset: Int,
        chapterPlainText: String?,
        highlights: [HighlightPaint],
        inlineMode: InlineNoteKind,
        inlineNotes: [InlineNotePaint],
        appearance: ReaderAppearance = ReaderAppearance(),
        selectionActive: Bool = false,
        onTap: @escaping () -> Void = {},
        onChapterBoundary: @escaping (PageTurnDirection) -> Void = { _ in },
        onSelectionChange: @escaping (ReaderSelection?) -> Void = { _ in },
        onPositionChange: @escaping (String) -> Void = { _ in },
        onVisibleParagraphs: @escaping ([ReaderParagraph]) -> Void = { _ in },
        onPageInfo: @escaping (Int, Int) -> Void = { _, _ in }
    ) {
        self.chapter = chapter
        self.basePath = basePath
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.landing = landing
        self.resumeUTF16Offset = resumeUTF16Offset
        self.chapterPlainText = chapterPlainText
        self.highlights = highlights
        self.inlineMode = inlineMode
        self.inlineNotes = inlineNotes
        self.appearance = appearance
        self.selectionActive = selectionActive
        self.onTap = onTap
        self.onChapterBoundary = onChapterBoundary
        self.onSelectionChange = onSelectionChange
        self.onPositionChange = onPositionChange
        self.onVisibleParagraphs = onVisibleParagraphs
        self.onPageInfo = onPageInfo

        let parsed = NativeChapterParser.parse(chapter)
        self.document = parsed
        self.blockSpans = parsed.resolvedTextSpans(in: chapterPlainText)
    }

    var body: some View {
        GeometryReader { geometry in
            let textSize = CGSize(
                width: max(40, geometry.size.width - horizontalInset * 2),
                height: max(80, geometry.size.height - verticalInset * 2)
            )
            ZStack {
                palette.window.ignoresSafeArea()

                if let paginated {
                    TabView(selection: $pageIndex) {
                        ForEach(0..<paginated.pageCount, id: \.self) { index in
                            PageTextView(
                                paginated: paginated,
                                pageIndex: index,
                                clearSelection: !selectionActive,
                                onSelectionChange: { handleSelection($0) }
                            )
                            .frame(width: textSize.width, height: textSize.height)
                            .padding(.horizontal, horizontalInset)
                            .padding(.vertical, verticalInset)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .id(paginated.version)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, width: geometry.size.width)
            }
            .onAppear {
                recomposeIfNeeded(textSize: textSize)
            }
            .onChange(of: composeKey(textSize: textSize)) { _, _ in
                recomposeIfNeeded(textSize: textSize)
            }
            .onChange(of: pageIndex) { _, newIndex in
                reportPage(newIndex)
            }
        }
    }

    private var horizontalInset: CGFloat { 24 }
    private var verticalInset: CGFloat { 14 }

    /// 微信读书-style tap navigation: left quarter back, right quarter
    /// forward, middle toggles the chrome. A pending selection makes the
    /// first tap dismiss it instead of turning a page.
    private func handleTap(at location: CGPoint, width: CGFloat) {
        if selectionActive {
            onSelectionChange(nil)
            return
        }
        if location.x < width * 0.26 {
            turnPage(-1)
        } else if location.x > width * 0.74 {
            turnPage(1)
        } else {
            onSelectionChange(nil)
            onTap()
        }
    }

    private func turnPage(_ delta: Int) {
        guard let paginated else { return }
        let target = pageIndex + delta
        if target < 0 {
            onChapterBoundary(.backward)
            return
        }
        if target >= paginated.pageCount {
            onChapterBoundary(.forward)
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            pageIndex = target
        }
    }

    private func composeKey(textSize: CGSize) -> ComposeKey {
        ComposeKey(
            width: textSize.width,
            height: textSize.height,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            appearance: appearance,
            isDark: palette.isDark,
            inlineMode: inlineMode,
            noteFingerprint: inlineNotes.reduce(0) { partial, note in
                partial &+ note.idx &* 31 &+ note.text.utf16.count &+ (note.failed ? 7 : 0)
            },
            highlightFingerprint: highlights.reduce(0) { partial, paint in
                partial &+ (paint.startUTF16 ?? 0) &* 31 &+ (paint.endUTF16 ?? 0)
            }
        )
    }

    private func recomposeIfNeeded(textSize: CGSize) {
        let key = composeKey(textSize: textSize)
        guard key != lastComposeKey else { return }
        lastComposeKey = key

        // Keep the reader's place across re-layout (notes arriving,
        // font/theme changes, rotation).
        let anchorOffset = paginated.flatMap { $0.chapterOffset(forPage: pageIndex) }

        let composer = PageComposer(
            document: document,
            blockSpans: blockSpans,
            chapterPlainText: chapterPlainText,
            basePath: basePath,
            chapterHref: chapter.href,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            appearance: appearance,
            isDarkCanvas: palette.isDark,
            inlineMode: inlineMode,
            inlineNotes: inlineNotes,
            highlights: highlights,
            pageSize: textSize
        )
        composeVersion += 1
        let next = composer.compose(version: composeVersion)
        paginated = next

        let landingPage: Int
        if let anchorOffset, let page = next.page(forChapterOffset: anchorOffset) {
            landingPage = page
        } else {
            switch landing {
            case .end:
                landingPage = max(0, next.pageCount - 1)
            case .start:
                if resumeUTF16Offset > 0,
                   let page = next.page(forChapterOffset: resumeUTF16Offset) {
                    landingPage = page
                } else {
                    landingPage = 0
                }
            }
        }
        pageIndex = min(landingPage, max(0, next.pageCount - 1))
        reportPage(pageIndex)
    }

    private func reportPage(_ index: Int) {
        guard let paginated else { return }
        onPageInfo(index, paginated.pageCount)

        let paragraphs = paginated.paragraphs(onPage: index)
        if !paragraphs.isEmpty {
            onVisibleParagraphs(paragraphs)
        }

        if let offset = paginated.chapterOffset(forPage: index) {
            let source = chapterPlainText ?? document.plainText
            let utf16 = Array(source.utf16)
            let clamped = max(0, min(offset, utf16.count))
            onPositionChange(String(decoding: utf16[0..<clamped], as: UTF16.self))
        }
    }

    private func handleSelection(_ attrRange: NSRange?) {
        guard let attrRange, attrRange.length > 0, let paginated else {
            onSelectionChange(nil)
            return
        }
        guard let chapterRange = paginated.chapterRange(forAttrRange: attrRange) else {
            onSelectionChange(nil)
            return
        }
        let source = chapterPlainText ?? document.plainText
        onSelectionChange(
            ReaderSelectionContext.selection(in: source, utf16Range: chapterRange)
        )
    }
}

// MARK: - Page text view

private struct PageTextView: UIViewRepresentable {
    let paginated: PaginatedChapter
    let pageIndex: Int
    let clearSelection: Bool
    let onSelectionChange: (NSRange?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let container = paginated.containers[pageIndex]
        let textView = UITextView(frame: .zero, textContainer: container)
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.dataDetectorTypes = []
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        if clearSelection, textView.selectedRange.length > 0 {
            context.coordinator.programmatic = true
            textView.selectedRange = NSRange(location: NSNotFound, length: 0)
            context.coordinator.programmatic = false
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChange: (NSRange?) -> Void
        var programmatic = false

        init(onSelectionChange: @escaping (NSRange?) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !programmatic else { return }
            let range = textView.selectedRange
            guard range.location != NSNotFound, range.length > 0 else {
                onSelectionChange(nil)
                return
            }
            onSelectionChange(range)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
