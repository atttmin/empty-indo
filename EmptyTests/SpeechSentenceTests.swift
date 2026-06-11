//
//  SpeechSentenceTests.swift
//  EmptyTests
//
//  P1 朗读: sentence splitting keeps exact UTF-16 ranges (follow-along
//  highlights depend on them) and 从当前位置接读 picks the right sentence.
//

import Testing
@testable import Empty

struct SpeechSentenceSplitterTests {
    @Test func splitsCJKAndLatinWithExactRanges() {
        let text = "第一句。第二句！Third sentence. 最后一句"
        let sentences = SpeechSentenceSplitter.split(text)

        #expect(sentences.map(\.text) == ["第一句。", "第二句！", "Third sentence.", "最后一句"])

        // Ranges tile the string in order and map back to the source.
        for sentence in sentences {
            let utf16 = Array(text.utf16)
            let slice = String(
                decoding: utf16[sentence.utf16Range.lowerBound..<sentence.utf16Range.upperBound],
                as: UTF16.self
            )
            #expect(slice.contains(sentence.text.prefix(3)))
        }
        #expect(sentences[0].utf16Range.lowerBound == 0)
        #expect(sentences[1].utf16Range.lowerBound == sentences[0].utf16Range.upperBound)
    }

    @Test func dropsWhitespaceOnlyFragmentsAndKeepsNewlbreaks() {
        let text = "标题\n\n正文第一行。\n"
        let sentences = SpeechSentenceSplitter.split(text)
        #expect(sentences.map(\.text) == ["标题", "正文第一行。"])
    }

    @Test func sentenceIndexFindsContainingSentence() {
        let text = "一二三。四五六。七八九。"
        let sentences = SpeechSentenceSplitter.split(text)
        #expect(sentences.count == 3)

        // Offset inside the second sentence (utf16 5 = "五").
        #expect(SpeechSentenceSplitter.sentenceIndex(at: 5, in: sentences) == 1)
        #expect(SpeechSentenceSplitter.sentenceIndex(at: 0, in: sentences) == 0)
        // Past the end clamps to the last sentence.
        #expect(SpeechSentenceSplitter.sentenceIndex(at: 999, in: sentences) == 2)
    }

    @Test func languageDetectionPicksChineseForCJK() {
        #expect(ReadingAloud.detectLanguage(of: "上善若水。") == "zh-CN")
        #expect(ReadingAloud.detectLanguage(of: "I went to the woods.") == "en-US")
    }
}
