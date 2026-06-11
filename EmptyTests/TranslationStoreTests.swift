//
//  TranslationStoreTests.swift
//  EmptyTests
//
//  The persistent paragraph-translation cache behind 双语对照's
//  "never translate twice" rule.
//

import Foundation
import SwiftData
import Testing
@testable import Empty

@MainActor
struct TranslationStoreTests {
    /// Holds the container alongside the store: a `ModelContext` does not
    /// keep its container alive, so dropping the container mid-test makes
    /// every fetch a use-after-free.
    private struct Fixture {
        let container: ModelContainer
        let store: TranslationStore
    }

    private func makeFixture() throws -> Fixture {
        let container = try AppStores.makeContainer(ephemeral: true)
        return Fixture(
            container: container,
            store: TranslationStore(modelContext: container.mainContext)
        )
    }

    @Test func hashIsStableAndWhitespaceInsensitive() {
        let a = TranslationStore.hash("I went to the woods because I wished to live deliberately")
        let b = TranslationStore.hash("I went to the woods\n  because I wished to live deliberately ")
        #expect(a == b)
        #expect(a.count == 16)
        #expect(TranslationStore.hash("something else entirely") != a)
    }

    @Test func storesAndLooksUpByTextNotIndex() throws {
        let fixture = try makeFixture()
        let store = fixture.store
        let bookID = UUID()
        let paragraph = "Our life is frittered away by detail. Simplicity, simplicity, simplicity!"

        #expect(store.lookup(bookID: bookID, kind: .bilingual, text: paragraph) == nil)

        store.store(
            "生命被琐碎消磨殆尽。简单,简单,再简单!",
            bookID: bookID,
            chapterIndex: 1,
            kind: .bilingual,
            text: paragraph
        )

        // Different whitespace, same paragraph → still a hit.
        let rewrapped = "Our life is frittered away by detail.\nSimplicity, simplicity, simplicity!"
        #expect(
            store.lookup(bookID: bookID, kind: .bilingual, text: rewrapped)
                == "生命被琐碎消磨殆尽。简单,简单,再简单!"
        )
        // Other kinds and books don't collide.
        #expect(store.lookup(bookID: bookID, kind: .companion, text: paragraph) == nil)
        #expect(store.lookup(bookID: UUID(), kind: .bilingual, text: paragraph) == nil)
    }

    @Test func upsertReplacesInsteadOfDuplicating() throws {
        let fixture = try makeFixture()
        let store = fixture.store
        let bookID = UUID()
        let text = "A paragraph that gets retranslated with a better provider later on."

        store.store("第一版", bookID: bookID, chapterIndex: 0, kind: .bilingual, text: text)
        store.store("第二版", bookID: bookID, chapterIndex: 0, kind: .bilingual, text: text)

        #expect(store.lookup(bookID: bookID, kind: .bilingual, text: text) == "第二版")
        #expect(store.cachedCount(bookID: bookID, chapterIndex: 0, kind: .bilingual) == 1)
    }

    @Test func footprintCountsEntriesAndBytes() throws {
        let fixture = try makeFixture()
        let store = fixture.store
        let bookID = UUID()
        store.store("译文一", bookID: bookID, chapterIndex: 0, kind: .bilingual,
                    text: "First paragraph with enough length to be realistic in a chapter.")
        store.store("译文二", bookID: bookID, chapterIndex: 1, kind: .bilingual,
                    text: "Second paragraph with enough length to be realistic in a chapter.")

        let footprint = store.bookFootprint(bookID: bookID)
        #expect(footprint.count == 2)
        #expect(footprint.bytes == "译文一".utf8.count + "译文二".utf8.count)
        #expect(store.cachedCount(bookID: bookID, chapterIndex: 1, kind: .bilingual) == 1)
    }

    @Test func segmentsChapterTextIntoTranslatableParagraphs() {
        let text = """
        Short line.

        This paragraph is comfortably long enough to be worth translating in the bilingual mode.
        This second paragraph is also long enough to pass the minimum length filter for translation.

        Tiny.
        """
        let paragraphs = TranslationStore.paragraphs(in: text)
        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].hasPrefix("This paragraph"))
    }
}

struct RomanNumeralTests {
    @Test func formatsChapterNumbers() {
        #expect(RomanNumeral.format(1) == "I")
        #expect(RomanNumeral.format(4) == "IV")
        #expect(RomanNumeral.format(9) == "IX")
        #expect(RomanNumeral.format(18) == "XVIII")
        #expect(RomanNumeral.format(42) == "XLII")
        #expect(RomanNumeral.format(0) == "0")
    }
}
