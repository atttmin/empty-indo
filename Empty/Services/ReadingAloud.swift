//
//  ReadingAloud.swift
//  Empty
//
//  P1 朗读: sentence-level read-aloud. The chapter text splits into
//  sentences (UTF-16 ranges preserved), the queue advances sentence by
//  sentence publishing the current range so the reader can paint a
//  follow-along highlight, speed runs 0.75–1.5×, and finishing the last
//  sentence can hand off to the next chapter.
//

import AVFoundation
import Combine
import Foundation

/// One spoken sentence and where it lives in the chapter's plain text.
nonisolated struct SpeechSentence: Equatable {
    var text: String
    /// UTF-16 range in the source text the sentence was split from.
    var utf16Range: Range<Int>
}

/// Splits text into speakable sentences on CJK/Latin terminators and
/// newlines, preserving exact UTF-16 ranges for follow-along highlights.
nonisolated enum SpeechSentenceSplitter {
    private static let terminators: Set<Character> = [
        "。", "！", "？", "…", "!", "?", ".", ";", "；", "\n",
    ]

    static func split(_ text: String) -> [SpeechSentence] {
        var sentences: [SpeechSentence] = []
        var sentenceStartUTF16 = 0
        var currentUTF16 = 0
        var current = ""

        func flush(endUTF16: Int) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 {
                sentences.append(SpeechSentence(
                    text: trimmed,
                    utf16Range: sentenceStartUTF16..<endUTF16
                ))
            }
            current = ""
            sentenceStartUTF16 = endUTF16
        }

        for character in text {
            let width = String(character).utf16.count
            current.append(character)
            currentUTF16 += width
            if terminators.contains(character) {
                flush(endUTF16: currentUTF16)
            }
        }
        flush(endUTF16: currentUTF16)
        return sentences
    }

    /// Index of the sentence containing (or first after) the offset.
    static func sentenceIndex(at utf16Offset: Int, in sentences: [SpeechSentence]) -> Int {
        guard !sentences.isEmpty else { return 0 }
        for (index, sentence) in sentences.enumerated()
        where utf16Offset < sentence.utf16Range.upperBound {
            return index
        }
        return sentences.count - 1
    }
}

/// Text-to-speech for the reader's aloud bar: sentence queue, rate
/// control, follow-along range publishing, and chapter hand-off.
@MainActor
final class ReadingAloud: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var currentSnippet = ""
    /// The sentence being spoken, in chapter UTF-16 coordinates — the
    /// reader paints this as the follow-along highlight.
    @Published private(set) var currentSentenceRange: Range<Int>?
    /// 0.75–1.5×, multiplied onto the system default rate.
    @Published var rate: Double = 1.0 {
        didSet { rate = min(max(rate, 0.75), 1.5) }
    }

    /// Called after the queue's last sentence finishes (自动下一章).
    var onQueueFinished: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [SpeechSentence] = []
    private var queueIndex = 0
    private var language = "en-US"

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` from the sentence containing `utf16Offset` (从当前
    /// 位置接着读). Empty/short tails fall back to the first sentence.
    func speak(_ text: String, fromUTF16Offset utf16Offset: Int = 0, language: String? = nil) {
        stop()
        let sentences = SpeechSentenceSplitter.split(text)
        guard !sentences.isEmpty else { return }
        self.language = language ?? Self.detectLanguage(of: text)
        queue = sentences
        queueIndex = SpeechSentenceSplitter.sentenceIndex(at: utf16Offset, in: sentences)
        speakCurrent()
    }

    func togglePause() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isSpeaking = true
        } else if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue = []
        queueIndex = 0
        isSpeaking = false
        currentSentenceRange = nil
        currentSnippet = ""
    }

    nonisolated static func detectLanguage(of text: String) -> String {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            ? "zh-CN"
            : "en-US"
    }

    private func speakCurrent() {
        guard queue.indices.contains(queueIndex) else {
            let finished = onQueueFinished
            stop()
            finished?()
            return
        }
        let sentence = queue[queueIndex]
        currentSentenceRange = sentence.utf16Range
        currentSnippet = String(sentence.text.prefix(48))
        let utterance = AVSpeechUtterance(string: sentence.text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    private func advance() {
        queueIndex += 1
        speakCurrent()
    }
}

extension ReadingAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // `stop()` empties the queue; only a live queue advances.
            guard !queue.isEmpty else { return }
            advance()
        }
    }
}
