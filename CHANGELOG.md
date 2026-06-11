# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- PDF reading: import `.pdf` files, native PDFKit viewer with per-page
  navigation, progress tracking, and AI indexing via per-page `Chapter` rows
- PDF text selection and highlights: selections report through the same
  `ReaderSelection` pipeline as EPUB (highlight button on iOS; explain /
  translate / ask / vocab popover on Mac), and stored highlights paint as
  PDF annotations on the visible page
- Intra-chapter reading position: the paginated reader now reports the
  furthest visible character (`utf16Offset`) on every page turn, so
  spoiler-safe retrieval includes already-read text from the current chapter
- Language-aware sentence embeddings: semantic indexing and retrieval now
  pick the embedding model from the text's language (Chinese supported),
  instead of hardcoding English
- Flashcards: generate study cards from highlights (`StudyCardEntry`,
  `StudyCardStore`) and review them with the Ebbinghaus ladder on the Mac
  vocab screen and the new iOS Study tab (`FlashcardsReviewView`)
- iOS root tabs: Library / Notes / Study, bringing vocab review and
  highlight notes to iPhone and iPad
- CloudKit sync enabled: `Empty.entitlements` + synced store on
  `.automatic`
- Mac notes screen AI theme suggestion for the knowledge graph

### Fixed

- `StudyCardEntry.book` now has an inverse relationship on `Book`
  (`studyCards`, cascade delete) — CloudKit refuses to initialize a synced
  store containing inverse-less relationships, which crashed the app at
  launch with sync enabled; deleting a book also no longer orphans its
  study cards
- Removed duplicated doc-comment line in `ChunkRetriever`
- `BookIndexer` doc comment no longer claims the embedding pass is
  unimplemented (`SemanticIndexer` exists and is wired into ask-the-book)
- Docs: test suite status updated (the previously noted
  `SemanticScorerTests.testRetrieverFallsBackToLexical` failure no longer
  reproduces)

### Known limitations

- Building with the iCloud entitlement requires a paid developer team;
  local test runs can disable signing (`CODE_SIGNING_ALLOWED=NO`)

## [1.0.0] - 2026-06-11

### Added

- Initial release: **空 · AI 伴读** v1.0 prototype
- EPUB import, parsing, and WebKit paginated reader with highlights
- Dual SwiftData persistence (synced metadata + local chapter/chunk store)
- Spoiler-safe chunk retrieval and grounded AI answering
- On-device Apple Foundation Models and cloud BYOK (DeepSeek preset)
- Recap, ask-the-book, chapter summaries, and vocab gloss lookup
- Mac deep-reading workbench: library, reader, notes, vocab screens
- Companion panel, thought links, reading aloud (macOS TTS)
- Ebbinghaus spaced-repetition vocab scheduling
- Vermilion (朱批) design system for Mac UI
- Unit test suite (~79 tests) covering persistence, EPUB, retrieval, highlights, recap, cloud AI

### Known limitations (at 1.0.0; all addressed in Unreleased)

- Reading position tracked at chapter level only
- PDF import supported; PDF reading not implemented
- CloudKit sync prepared but disabled (`syncedDatabase = .none`)
- Flashcard generation implemented in services; no UI yet
- iOS lacks vocab/notes screens (Mac-only)

[1.0.0]: https://github.com/DaviRain-Su/empty/releases/tag/v1.0.0