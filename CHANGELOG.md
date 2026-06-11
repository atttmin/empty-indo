# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Intra-chapter reading position: the paginated reader now reports the
  furthest visible character (`utf16Offset`) on every page turn, so
  spoiler-safe retrieval includes already-read text from the current chapter
- Language-aware sentence embeddings: semantic indexing and retrieval now
  pick the embedding model from the text's language (Chinese supported),
  instead of hardcoding English

### Fixed

- Removed duplicated doc-comment line in `ChunkRetriever`
- `BookIndexer` doc comment no longer claims the embedding pass is
  unimplemented (`SemanticIndexer` exists and is wired into ask-the-book)
- Docs: test suite status updated to 79/79 passing (the previously noted
  `SemanticScorerTests.testRetrieverFallsBackToLexical` failure no longer
  reproduces)

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

### Known limitations

- Reading position tracked at chapter level only (`utf16Offset` not yet reported from reader; fixed in Unreleased)
- PDF import supported; PDF reading not implemented
- CloudKit sync prepared but disabled (`syncedDatabase = .none`)
- Flashcard generation implemented in services; no UI yet
- iOS lacks vocab/notes screens (Mac-only)

[1.0.0]: https://github.com/DaviRain-Su/empty/releases/tag/v1.0.0