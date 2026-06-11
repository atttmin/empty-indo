//
//  PDFReaderView.swift
//  Empty
//

import PDFKit
import SwiftUI

#if canImport(UIKit)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif

/// Same marker yellow the EPUB reader paints (rgba 255,214,10,0.45).
private let highlightFill = PlatformColor(
    red: 1, green: 0.84, blue: 0.04, alpha: 0.45
)

/// Native PDFKit reader — one page at a time, synced to `pageIndex`.
/// Reports text selections (for highlighting and AI actions) and paints
/// stored highlights as PDF annotations on the visible page.
struct PDFReaderView: View {
    let documentURL: URL
    @Binding var pageIndex: Int
    var highlights: [HighlightPaint] = []
    /// 夜间反色 (smart-ish: hue-rotated so colors keep their identity).
    var nightInverted: Bool = false
    /// Per-book zoom memory: UserDefaults key, nil disables.
    var zoomMemoryKey: String? = nil
    /// 双页 spread (Mac).
    var twoUp: Bool = false
    /// 自动裁边 (white-margin detection).
    var autoCrop: Bool = false
    var onPageChange: (Int) -> Void = { _ in }
    var onSelectionChange: (ReaderSelection?) -> Void = { _ in }

    var body: some View {
        PDFReaderRepresentable(
            documentURL: documentURL,
            pageIndex: $pageIndex,
            highlights: highlights,
            zoomMemoryKey: zoomMemoryKey,
            twoUp: twoUp,
            autoCrop: autoCrop,
            onPageChange: onPageChange,
            onSelectionChange: onSelectionChange
        )
        .colorInvert(enabled: nightInverted)
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(enabled: Bool) -> some View {
        if enabled {
            self.colorInvert().hueRotation(.degrees(180))
        } else {
            self
        }
    }
}

// MARK: - Selection context

/// Builds the `ReaderSelection` (text + disambiguation context) for a PDF
/// selection, mirroring what the EPUB web view reports. Factored out of the
/// coordinator so the UTF-16 slicing is unit-testable without a `PDFView`.
nonisolated enum PDFSelectionContext {
    /// Characters of surrounding page text kept on each side of the
    /// selection; matches the EPUB reader's prefix/suffix window.
    static let contextLength = 40

    static func readerSelection(
        pageText: String,
        selectedText: String,
        range: NSRange
    ) -> ReaderSelection {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = pageText as NSString
        guard range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= page.length else {
            return ReaderSelection(text: text, prefix: "", suffix: "")
        }

        // Round to composed-character boundaries so the context never slices
        // a surrogate pair into a replacement character.
        var prefixStart = max(0, range.location - contextLength)
        if prefixStart > 0, prefixStart < page.length {
            prefixStart = page.rangeOfComposedCharacterSequence(at: prefixStart).location
        }
        let prefix = page.substring(
            with: NSRange(location: prefixStart, length: range.location - prefixStart)
        )

        let suffixStart = NSMaxRange(range)
        var suffixEnd = min(page.length, suffixStart + contextLength)
        if suffixEnd > suffixStart, suffixEnd < page.length {
            let sequence = page.rangeOfComposedCharacterSequence(at: suffixEnd - 1)
            suffixEnd = NSMaxRange(sequence)
        }
        let suffix = page.substring(
            with: NSRange(location: suffixStart, length: suffixEnd - suffixStart)
        )

        return ReaderSelection(text: text, prefix: prefix, suffix: suffix)
    }
}

// MARK: - Auto crop (白边检测)

/// Detects a page's content bounding box by scanning a small rendered
/// thumbnail for non-background pixels, then maps it back to media-box
/// coordinates. Cheap enough to run per displayed page.
nonisolated enum PDFAutoCrop {
    static func contentRect(for page: PDFPage, padding: CGFloat = 6) -> CGRect? {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 1, mediaBox.height > 1 else { return nil }
        let sampleWidth = 160.0
        let scale = sampleWidth / mediaBox.width
        let size = CGSize(width: sampleWidth, height: mediaBox.height * scale)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)

        #if canImport(UIKit)
        guard let cgImage = thumbnail.cgImage else { return nil }
        #else
        var proposed = CGRect(origin: .zero, size: thumbnail.size)
        guard let cgImage = thumbnail.cgImage(
            forProposedRect: &proposed, context: nil, hints: nil
        ) else { return nil }
        #endif

        let width = cgImage.width
        let height = cgImage.height
        guard width > 4, height > 4 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Background luminance from the corners; content = pixels that
        // differ noticeably.
        let corners = [
            pixels[0], pixels[width - 1],
            pixels[(height - 1) * width], pixels[height * width - 1],
        ]
        let background = corners.map(Int.init).reduce(0, +) / corners.count

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where abs(Int(pixels[y * width + x]) - background) > 28 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Mostly-empty pages keep their full box.
        let coverage = Double((maxX - minX) * (maxY - minY)) / Double(width * height)
        guard coverage > 0.02 else { return nil }

        let pixelScale = mediaBox.width / CGFloat(width)
        // CGImage rows are top-down; PDF space is bottom-up.
        let content = CGRect(
            x: mediaBox.minX + CGFloat(minX) * pixelScale - padding,
            y: mediaBox.minY + CGFloat(height - 1 - maxY) * pixelScale - padding,
            width: CGFloat(maxX - minX + 1) * pixelScale + padding * 2,
            height: CGFloat(maxY - minY + 1) * pixelScale + padding * 2
        ).intersection(mediaBox)
        guard content.width > 40, content.height > 40 else { return nil }
        return content
    }
}

// MARK: - Bridge

final class PDFReaderCoordinator: NSObject {
    var pageIndex: Int = 0
    var paints: [HighlightPaint] = []
    /// 按书缩放记忆: persisted scale factor under this defaults key.
    var zoomMemoryKey: String?
    /// 自动裁边 — crops the displayed page to its detected content box.
    var autoCrop = false

    var onPageChange: (Int) -> Void = { _ in }
    var onSelectionChange: (ReaderSelection?) -> Void = { _ in }

    private var observations: [NSObjectProtocol] = []
    private var isApplyingPage = false
    private var selectionDebounce: DispatchWorkItem?
    private var paintedAnnotations: [PDFAnnotation] = []
    /// Pages whose cropBox we replaced, with the original to restore.
    private var croppedPages: [ObjectIdentifier: (page: PDFPage, original: CGRect)] = [:]

    /// Applies/undoes auto-crop on the visible page.
    func applyAutoCrop(on pdfView: PDFView) {
        guard let page = pdfView.currentPage else { return }
        let key = ObjectIdentifier(page)
        if autoCrop {
            guard croppedPages[key] == nil,
                  let content = PDFAutoCrop.contentRect(for: page) else { return }
            croppedPages[key] = (page, page.bounds(for: .cropBox))
            page.setBounds(content, for: .cropBox)
            pdfView.layoutDocumentView()
        } else if !croppedPages.isEmpty {
            for (_, entry) in croppedPages {
                entry.page.setBounds(entry.original, for: .cropBox)
            }
            croppedPages.removeAll()
            pdfView.layoutDocumentView()
        }
    }

    func attach(to pdfView: PDFView) {
        detach()
        observations.append(NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self, weak pdfView] _ in
            guard let self, let pdfView else { return }
            self.applyAutoCrop(on: pdfView)
            self.applyHighlights(on: pdfView)
            guard !self.isApplyingPage else { return }
            guard let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            guard index != NSNotFound, index != self.pageIndex else { return }
            self.pageIndex = index
            self.onPageChange(index)
        })
        observations.append(NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged,
            object: pdfView,
            queue: .main
        ) { [weak self, weak pdfView] _ in
            guard let self, let pdfView, let key = self.zoomMemoryKey else { return }
            UserDefaults.standard.set(Double(pdfView.scaleFactor), forKey: key)
        })
        observations.append(NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged,
            object: pdfView,
            queue: .main
        ) { [weak self, weak pdfView] _ in
            guard let self else { return }
            // Debounce: drags fire a notification per glyph.
            self.selectionDebounce?.cancel()
            let work = DispatchWorkItem { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.reportSelection(in: pdfView)
            }
            self.selectionDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        })
    }

    func detach() {
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
        observations.removeAll()
        selectionDebounce?.cancel()
        selectionDebounce = nil
    }

    /// Restores the book's remembered zoom (must run after the document
    /// is set; `autoScales` wins until a stored value exists).
    func restoreZoom(in pdfView: PDFView) {
        guard let key = zoomMemoryKey else { return }
        let stored = UserDefaults.standard.double(forKey: key)
        guard stored > 0.05 else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = CGFloat(stored)
    }

    func applyPage(in pdfView: PDFView, index: Int) {
        guard let document = pdfView.document,
              index >= 0,
              index < document.pageCount,
              let page = document.page(at: index) else { return }
        guard pdfView.currentPage !== page else { return }
        isApplyingPage = true
        pdfView.go(to: page)
        isApplyingPage = false
        applyHighlights(on: pdfView)
    }

    // MARK: Selection

    private func reportSelection(in pdfView: PDFView) {
        guard let selection = pdfView.currentSelection,
              let rawText = selection.string,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let page = selection.pages.first else {
            onSelectionChange(nil)
            return
        }
        var range = NSRange(location: NSNotFound, length: 0)
        if selection.numberOfTextRanges(on: page) > 0 {
            range = selection.range(at: 0, on: page)
        }
        onSelectionChange(PDFSelectionContext.readerSelection(
            pageText: page.string ?? "",
            selectedText: rawText,
            range: range
        ))
    }

    // MARK: Highlight painting

    /// Repaints stored highlights on the visible page. Mirrors the EPUB
    /// painter's strategy: locate each highlight by its text snapshot and
    /// mark the first occurrence on the page.
    func applyHighlights(on pdfView: PDFView) {
        for annotation in paintedAnnotations {
            annotation.page?.removeAnnotation(annotation)
        }
        paintedAnnotations.removeAll()

        guard !paints.isEmpty,
              let document = pdfView.document,
              let page = pdfView.currentPage else { return }

        for paint in paints {
            let needle = paint.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            let matches = document.findString(needle, withOptions: [])
            guard let match = matches.first(where: { $0.pages.contains(page) }) else {
                continue
            }
            for line in match.selectionsByLine() where line.pages.contains(page) {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(
                    bounds: bounds,
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = highlightFill
                page.addAnnotation(annotation)
                paintedAnnotations.append(annotation)
            }
        }
    }

    deinit {
        detach()
    }
}

#if canImport(UIKit)
struct PDFReaderRepresentable: UIViewRepresentable {
    let documentURL: URL
    @Binding var pageIndex: Int
    let highlights: [HighlightPaint]
    var zoomMemoryKey: String? = nil
    var twoUp: Bool = false
    var autoCrop: Bool = false
    let onPageChange: (Int) -> Void
    let onSelectionChange: (ReaderSelection?) -> Void

    func makeCoordinator() -> PDFReaderCoordinator {
        PDFReaderCoordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = twoUp ? .twoUp : .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(url: documentURL)
        context.coordinator.pageIndex = pageIndex
        context.coordinator.paints = highlights
        context.coordinator.zoomMemoryKey = zoomMemoryKey
        context.coordinator.autoCrop = autoCrop
        syncCallbacks(context.coordinator)
        context.coordinator.attach(to: pdfView)
        context.coordinator.applyPage(in: pdfView, index: pageIndex)
        context.coordinator.applyHighlights(on: pdfView)
        context.coordinator.restoreZoom(in: pdfView)
        context.coordinator.applyAutoCrop(on: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != documentURL {
            pdfView.document = PDFDocument(url: documentURL)
        }
        let mode: PDFDisplayMode = twoUp ? .twoUp : .singlePage
        if pdfView.displayMode != mode {
            pdfView.displayMode = mode
        }
        if context.coordinator.autoCrop != autoCrop {
            context.coordinator.autoCrop = autoCrop
            context.coordinator.applyAutoCrop(on: pdfView)
        }
        syncCallbacks(context.coordinator)
        if context.coordinator.pageIndex != pageIndex {
            context.coordinator.pageIndex = pageIndex
            context.coordinator.applyPage(in: pdfView, index: pageIndex)
        }
        if context.coordinator.paints != highlights {
            context.coordinator.paints = highlights
            context.coordinator.applyHighlights(on: pdfView)
        }
    }

    private func syncCallbacks(_ coordinator: PDFReaderCoordinator) {
        coordinator.onPageChange = { index in
            pageIndex = index
            onPageChange(index)
        }
        coordinator.onSelectionChange = onSelectionChange
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: PDFReaderCoordinator) {
        coordinator.detach()
    }
}
#else
struct PDFReaderRepresentable: NSViewRepresentable {
    let documentURL: URL
    @Binding var pageIndex: Int
    let highlights: [HighlightPaint]
    var zoomMemoryKey: String? = nil
    var twoUp: Bool = false
    var autoCrop: Bool = false
    let onPageChange: (Int) -> Void
    let onSelectionChange: (ReaderSelection?) -> Void

    func makeCoordinator() -> PDFReaderCoordinator {
        PDFReaderCoordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = twoUp ? .twoUp : .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(url: documentURL)
        context.coordinator.pageIndex = pageIndex
        context.coordinator.paints = highlights
        context.coordinator.zoomMemoryKey = zoomMemoryKey
        context.coordinator.autoCrop = autoCrop
        syncCallbacks(context.coordinator)
        context.coordinator.attach(to: pdfView)
        context.coordinator.applyPage(in: pdfView, index: pageIndex)
        context.coordinator.applyHighlights(on: pdfView)
        context.coordinator.restoreZoom(in: pdfView)
        context.coordinator.applyAutoCrop(on: pdfView)
        DispatchQueue.main.async {
            pdfView.window?.makeFirstResponder(pdfView)
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != documentURL {
            pdfView.document = PDFDocument(url: documentURL)
        }
        let mode: PDFDisplayMode = twoUp ? .twoUp : .singlePage
        if pdfView.displayMode != mode {
            pdfView.displayMode = mode
        }
        if context.coordinator.autoCrop != autoCrop {
            context.coordinator.autoCrop = autoCrop
            context.coordinator.applyAutoCrop(on: pdfView)
        }
        syncCallbacks(context.coordinator)
        if context.coordinator.pageIndex != pageIndex {
            context.coordinator.pageIndex = pageIndex
            context.coordinator.applyPage(in: pdfView, index: pageIndex)
        }
        if context.coordinator.paints != highlights {
            context.coordinator.paints = highlights
            context.coordinator.applyHighlights(on: pdfView)
        }
    }

    private func syncCallbacks(_ coordinator: PDFReaderCoordinator) {
        coordinator.onPageChange = { index in
            pageIndex = index
            onPageChange(index)
        }
        coordinator.onSelectionChange = onSelectionChange
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: PDFReaderCoordinator) {
        coordinator.detach()
    }
}
#endif
