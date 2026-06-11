//
//  DictionaryLookupView.swift
//  Empty
//

#if os(iOS)
import SwiftUI
import UIKit

/// System dictionary lookup (词典) for the selection bar.
struct DictionaryLookupView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(
        _ controller: UIReferenceLibraryViewController,
        context: Context
    ) {}
}
#endif
