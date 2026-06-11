//
//  PDFParser.swift
//  Empty
//

import Foundation
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Extracts per-page plain text, metadata, and a cover thumbnail from a PDF.
nonisolated struct PDFParser {
    enum ParseError: LocalizedError {
        case fileNotFound
        case unreadable
        case noPages

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                "The PDF file is missing."
            case .unreadable:
                "This PDF could not be opened."
            case .noPages:
                "This PDF has no readable pages."
            }
        }
    }

    func parseBook(at url: URL) throws -> ParsedPDF {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound
        }
        guard let document = PDFDocument(url: url) else {
            throw ParseError.unreadable
        }
        guard document.pageCount > 0 else {
            throw ParseError.noPages
        }

        var metadata = PDFMetadata()
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           !title.isEmpty {
            metadata.title = title
        }
        if let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String,
           !author.isEmpty {
            metadata.author = author
        }

        var pages: [PDFPageContent] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            let page = document.page(at: index)
            let text = page?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            pages.append(
                PDFPageContent(
                    index: index,
                    title: "Page \(index + 1)",
                    text: text
                )
            )
        }

        let coverImageData = document.page(at: 0).map {
            thumbnailData(for: $0.thumbnail(
                of: CGSize(width: 240, height: 360),
                for: .mediaBox
            ))
        } ?? nil

        return ParsedPDF(
            metadata: metadata,
            pages: pages,
            coverImageData: coverImageData,
            sourceURL: url
        )
    }

    private func thumbnailData(for image: PlatformImage?) -> Data? {
        guard let image else { return nil }
        #if canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        #elseif canImport(UIKit)
        return image.jpegData(compressionQuality: 0.82)
        #else
        return nil
        #endif
    }
}

#if canImport(AppKit)
private typealias PlatformImage = NSImage
#elseif canImport(UIKit)
private typealias PlatformImage = UIImage
#endif