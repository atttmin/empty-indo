//
//  IOSRootView.swift
//  Empty
//

#if !os(macOS)

import SwiftUI

struct IOSRootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            NotesView()
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }

            StudyView()
                .tabItem {
                    Label("Study", systemImage: "brain.head.profile")
                }
        }
    }
}

#endif