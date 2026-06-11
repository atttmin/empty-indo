# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- Reading position tracked at chapter level only (`utf16Offset` not yet reported from reader)
- PDF import supported; PDF reading not implemented
- CloudKit sync prepared but disabled (`syncedDatabase = .none`)
- Flashcard generation implemented in services; no UI yet
- iOS lacks vocab/notes screens (Mac-only)
- One failing test: `SemanticScorerTests.testRetrieverFallsBackToLexical`

[1.0.0]: https://github.com/<你的用户名>/Empty/releases/tag/v1.0.0