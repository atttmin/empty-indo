//
//  HighlightsListView.swift
//  Empty
//

import SwiftData
import SwiftUI

/// All highlights of one book, in reading order. Tapping jumps the reader
/// to the highlight's chapter; swipe to delete; context menu generates
/// AI flashcards.
struct HighlightsListView: View {
    let book: Book
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var highlights: [Highlight]

    @State private var generatingHighlightID: UUID?
    @State private var statusMessage: String?
    @State private var showFlashcards = false

    init(book: Book, onJump: @escaping (Int) -> Void) {
        self.book = book
        self.onJump = onJump
        let bookID = book.id
        _highlights = Query(
            filter: #Predicate<Highlight> { $0.book?.id == bookID },
            sort: [
                SortDescriptor(\Highlight.chapterIndex),
                SortDescriptor(\Highlight.startUTF16),
            ]
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    ContentUnavailableView {
                        Label("No Highlights", systemImage: "highlighter")
                    } description: {
                        Text("Select text while reading and tap Highlight.")
                    }
                } else {
                    List {
                        ForEach(highlights) { highlight in
                            Button {
                                onJump(highlight.chapterIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(highlight.textSnapshot)
                                        .font(.callout)
                                        .lineLimit(3)
                                        .foregroundStyle(.primary)
                                    Text("Chapter \(highlight.chapterIndex + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .contextMenu {
                                Button {
                                    Task { await generateFlashcards(from: highlight) }
                                } label: {
                                    Label("Generate Flashcards", systemImage: "rectangle.on.rectangle.angled")
                                }
                                if generatingHighlightID == highlight.id {
                                    Text("Generating…")
                                }
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { highlights[$0] })
                        }
                    }
                }
            }
            .navigationTitle("Highlights")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Flashcards", systemImage: "rectangle.on.rectangle.angled") {
                        showFlashcards = true
                    }
                }
            }
            .sheet(isPresented: $showFlashcards) {
                NavigationStack {
                    FlashcardsReviewView(bookFilter: book)
                        .padding()
                        .navigationTitle("Flashcards")
                        #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showFlashcards = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 420)
                #endif
            }
            .alert(
                "Flashcards",
                isPresented: Binding(
                    get: { statusMessage != nil },
                    set: { if !$0 { statusMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }

    private func generateFlashcards(from highlight: Highlight) async {
        generatingHighlightID = highlight.id
        defer { generatingHighlightID = nil }
        do {
            let created = try await StudyCardStore(modelContext: modelContext)
                .generate(from: highlight, book: book)
            statusMessage = created.isEmpty
                ? "No cards were generated. Check AI availability in AI Status."
                : "Added \(created.count) flashcard\(created.count == 1 ? "" : "s")."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func delete(_ toDelete: [Highlight]) {
        for highlight in toDelete {
            modelContext.delete(highlight)
        }
        try? modelContext.save()
    }
}