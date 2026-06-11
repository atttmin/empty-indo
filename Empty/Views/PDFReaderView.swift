//
//  PDFReaderView.swift
//  Empty
//

import PDFKit
import SwiftUI

/// Native PDFKit reader — one page at a time, synced to `pageIndex`.
struct PDFReaderView: View {
    let documentURL: URL
    @Binding var pageIndex: Int
    var onPageChange: (Int) -> Void = { _ in }

    var body: some View {
        PDFReaderRepresentable(
            documentURL: documentURL,
            pageIndex: $pageIndex,
            onPageChange: onPageChange
        )
    }
}

// MARK: - Bridge

final class PDFReaderCoordinator: NSObject {
    var pageIndex: Int = 0
    var onPageChange: (Int) -> Void = { _ in }
    private var observation: NSObjectProtocol?
    private var isApplyingPage = false

    func attach(to pdfView: PDFView) {
        detach()
        observation = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self, weak pdfView] _ in
            guard let self, let pdfView, !self.isApplyingPage else { return }
            guard let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            guard index != NSNotFound, index != self.pageIndex else { return }
            self.pageIndex = index
            self.onPageChange(index)
        }
    }

    func detach() {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
        observation = nil
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
    }

    deinit {
        detach()
    }
}

#if canImport(UIKit)
struct PDFReaderRepresentable: UIViewRepresentable {
    let documentURL: URL
    @Binding var pageIndex: Int
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> PDFReaderCoordinator {
        PDFReaderCoordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(url: documentURL)
        context.coordinator.pageIndex = pageIndex
        context.coordinator.onPageChange = { index in
            pageIndex = index
            onPageChange(index)
        }
        context.coordinator.attach(to: pdfView)
        context.coordinator.applyPage(in: pdfView, index: pageIndex)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != documentURL {
            pdfView.document = PDFDocument(url: documentURL)
        }
        context.coordinator.onPageChange = { index in
            pageIndex = index
            onPageChange(index)
        }
        if context.coordinator.pageIndex != pageIndex {
            context.coordinator.pageIndex = pageIndex
            context.coordinator.applyPage(in: pdfView, index: pageIndex)
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: PDFReaderCoordinator) {
        coordinator.detach()
    }
}
#else
struct PDFReaderRepresentable: NSViewRepresentable {
    let documentURL: URL
    @Binding var pageIndex: Int
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> PDFReaderCoordinator {
        PDFReaderCoordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(url: documentURL)
        context.coordinator.pageIndex = pageIndex
        context.coordinator.onPageChange = { index in
            pageIndex = index
            onPageChange(index)
        }
        context.coordinator.attach(to: pdfView)
        context.coordinator.applyPage(in: pdfView, index: pageIndex)
        DispatchQueue.main.async {
            pdfView.window?.makeFirstResponder(pdfView)
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != documentURL {
            pdfView.document = PDFDocument(url: documentURL)
        }
        context.coordinator.onPageChange = { index in
            pageIndex = index
            onPageChange(index)
        }
        if context.coordinator.pageIndex != pageIndex {
            context.coordinator.pageIndex = pageIndex
            context.coordinator.applyPage(in: pdfView, index: pageIndex)
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: PDFReaderCoordinator) {
        coordinator.detach()
    }
}
#endif