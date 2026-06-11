//
//  PDFTypes.swift
//  Empty
//

import Foundation

nonisolated struct PDFMetadata {
    var title: String = ""
    var author: String = ""
}

/// One page of extracted plain text — maps to a `Chapter` row for AI indexing.
nonisolated struct PDFPageContent {
    let index: Int
    let title: String
    let text: String
}

nonisolated struct ParsedPDF {
    let metadata: PDFMetadata
    let pages: [PDFPageContent]
    let coverImageData: Data?
    let sourceURL: URL
}