//
//  KimiProviderTests.swift
//  EmptyTests
//
//  Kimi Code as an Anthropic-protocol cloud preset, the second wire
//  standard alongside OpenAI-compatible, and the Messages API service
//  that backs it.
//

import Foundation
import Testing
@testable import Empty

struct KimiProviderTests {
    @Test func presetTargetsTheAnthropicCodingBase() {
        // The Messages client appends /v1/messages, so the base carries no
        // version segment.
        #expect(AIProviderSettings.kimiBaseURL == "https://api.kimi.com/coding")
        #expect(AIProviderSettings.kimiModel == "kimi-for-coding")
    }

    @Test func cloudProtocolRoundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "KimiProviderTests-\(UUID())"))
        var settings = AIProviderSettings()
        settings.mode = .cloud
        settings.cloudProtocol = .anthropic
        settings.cloudBaseURL = AIProviderSettings.kimiBaseURL
        settings.cloudModel = AIProviderSettings.kimiModel
        settings.save(to: defaults)

        let loaded = AIProviderSettings.load(from: defaults)
        #expect(loaded.cloudProtocol == .anthropic)
        #expect(loaded.cloudBaseURL == AIProviderSettings.kimiBaseURL)
        #expect(loaded.cloudModel == AIProviderSettings.kimiModel)
    }

    @Test func absentProtocolDefaultsToOpenAIForExistingConfigs() throws {
        let defaults = try #require(UserDefaults(suiteName: "KimiProviderTests-\(UUID())"))
        // Simulate a pre-protocol stored config (DeepSeek, OpenAI-only era).
        defaults.set("cloud", forKey: "ai.provider.mode")
        defaults.set(AIProviderSettings.deepSeekBaseURL, forKey: "ai.cloud.baseURL")
        defaults.set(AIProviderSettings.deepSeekModel, forKey: "ai.cloud.model")

        let loaded = AIProviderSettings.load(from: defaults)
        #expect(loaded.cloudProtocol == .openAI)
    }

    @MainActor
    @Test func resolvesAnthropicServiceForKimi() {
        var settings = AIProviderSettings()
        settings.mode = .cloud
        settings.cloudProtocol = .anthropic
        settings.cloudBaseURL = AIProviderSettings.kimiBaseURL
        settings.cloudModel = AIProviderSettings.kimiModel

        let service = settings.resolveService(apiKey: "sk-test")
        #expect(service is AnthropicAIService)
        #expect(service.availability.isAvailable)
    }

    @MainActor
    @Test func resolvesOpenAIServiceForDeepSeek() {
        var settings = AIProviderSettings()
        settings.mode = .cloud
        settings.cloudProtocol = .openAI
        let service = settings.resolveService(apiKey: "sk-test")
        #expect(service is CloudAIService)
    }
}

struct AnthropicAIServiceTests {
    @Test func availabilityNeedsURLAndKey() {
        let ok = AnthropicAIService(configuration: .kimi(apiKey: "sk-test"))
        #expect(ok.availability.isAvailable)

        let keyless = AnthropicAIService(configuration: .kimi(apiKey: ""))
        #expect(!keyless.availability.isAvailable)

        let badURL = AnthropicAIService(
            configuration: AnthropicAIService.Configuration(
                baseURLString: "not a url", model: "m", apiKey: "k"
            )
        )
        #expect(!badURL.availability.isAvailable)
    }

    @Test func requestEncodesMessagesWireFormat() throws {
        let request = AnthropicMessageRequest(
            model: "kimi-for-coding",
            maxTokens: 1024,
            system: "be concise",
            messages: [AnthropicMessage(role: "user", content: "hi")],
            temperature: 0.3
        )
        let json = try JSONEncoder().encode(request)
        let object = try #require(
            try JSONSerialization.jsonObject(with: json) as? [String: Any]
        )
        // Anthropic uses snake_case max_tokens and a top-level system string.
        #expect(object["max_tokens"] as? Int == 1024)
        #expect(object["system"] as? String == "be concise")
        #expect(object["model"] as? String == "kimi-for-coding")
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
    }

    @Test func extractsTextFromContentBlocks() throws {
        let data = Data("""
        {"id":"msg_1","type":"message","role":"assistant",
         "content":[{"type":"text","text":"梭罗在做减法。"}],
         "model":"kimi-for-coding"}
        """.utf8)
        #expect(AnthropicAIService.text(fromResponseData: data) == "梭罗在做减法。")
    }

    @Test func joinsMultipleTextBlocksAndSkipsNonText() throws {
        let data = Data("""
        {"content":[
          {"type":"text","text":"part one. "},
          {"type":"thinking","text":"(ignored)"},
          {"type":"text","text":"part two."}
        ]}
        """.utf8)
        #expect(AnthropicAIService.text(fromResponseData: data) == "part one. part two.")
    }

    @Test func malformedResponseYieldsNil() {
        #expect(AnthropicAIService.text(fromResponseData: Data("not json".utf8)) == nil)
        #expect(AnthropicAIService.text(fromResponseData: Data(#"{"content":[]}"#.utf8)) == nil)
    }

    @Test func reusesCloudParsersForJSONFeatures() throws {
        // The Messages service prompts for the same JSON the OpenAI path
        // does and decodes it with CloudAIService's tested parsers.
        let answer = try CloudAIService.groundedAnswer(
            fromContent: #"{"answer": "ok", "cited_passage_ids": [1]}"#,
            includedIDs: [1]
        )
        #expect(answer.text == "ok")
        let step = try CloudAIService.agentStep(
            fromContent: #"{"action": "finish", "answer": "done"}"#
        )
        #expect(step == .finish(answer: "done"))
    }
}
