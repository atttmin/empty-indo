//
//  AIProviderSettings.swift
//  Empty
//

import Foundation

/// Which inference route serves AI features.
nonisolated enum AIProviderMode: String, CaseIterable, Sendable {
    /// Apple's Foundation Models: free, offline, private — the default.
    case onDevice
    /// A hosted endpoint (DeepSeek / Kimi presets) with the user's key.
    case cloud
}

/// Which wire protocol the cloud endpoint speaks. Empty supports both
/// standards so a provider can be reached however it's cleanest: DeepSeek
/// speaks OpenAI chat-completions; Kimi Code's coding endpoint gates the
/// OpenAI path behind approved-client User-Agents but serves the Anthropic
/// Messages path with just an API key, so Kimi uses Anthropic.
nonisolated enum CloudProtocol: String, CaseIterable, Sendable {
    case openAI
    case anthropic
}

/// Persisted provider choice. Only non-secrets live in UserDefaults;
/// the API key goes through `KeychainStore`.
nonisolated struct AIProviderSettings: Equatable, Sendable {
    var mode: AIProviderMode = .onDevice
    var cloudProtocol: CloudProtocol = .openAI
    var cloudBaseURL: String = Self.deepSeekBaseURL
    var cloudModel: String = Self.deepSeekModel

    static let deepSeekBaseURL = "https://api.deepseek.com"
    /// Fast/cheap default; the right fit for summarize/recap workloads.
    static let deepSeekModel = "deepseek-v4-flash"
    /// Deeper-reasoning sibling for heavier analysis (argument maps etc.).
    static let deepSeekProModel = "deepseek-v4-pro"
    /// Kimi Code (Kimi membership), Anthropic-compatible base. The Messages
    /// client appends `/v1/messages`. The stable alias tracks Moonshot's
    /// latest coding model. Keys: Kimi Code Console (kimi.com/code/console).
    static let kimiBaseURL = "https://api.kimi.com/coding"
    static let kimiModel = "kimi-for-coding"
    /// Keychain account under which the cloud key is stored.
    static let apiKeyAccount = "cloud-provider-api-key"

    private enum Keys {
        static let mode = "ai.provider.mode"
        static let cloudProtocol = "ai.cloud.protocol"
        static let baseURL = "ai.cloud.baseURL"
        static let model = "ai.cloud.model"
    }

    static func load(from defaults: UserDefaults = .standard) -> AIProviderSettings {
        var settings = AIProviderSettings()
        if let raw = defaults.string(forKey: Keys.mode),
           let mode = AIProviderMode(rawValue: raw) {
            settings.mode = mode
        }
        if let raw = defaults.string(forKey: Keys.cloudProtocol),
           let proto = CloudProtocol(rawValue: raw) {
            settings.cloudProtocol = proto
        }
        if let baseURL = defaults.string(forKey: Keys.baseURL), !baseURL.isEmpty {
            settings.cloudBaseURL = baseURL
        }
        if let model = defaults.string(forKey: Keys.model), !model.isEmpty {
            settings.cloudModel = model
        }
        // DeepSeek retires the V3-era aliases on 2026-07-24; upgrade stored
        // configs to their V4 equivalents (chat → flash, reasoner → pro).
        if settings.cloudBaseURL == Self.deepSeekBaseURL {
            if settings.cloudModel == "deepseek-chat" {
                settings.cloudModel = Self.deepSeekModel
            } else if settings.cloudModel == "deepseek-reasoner" {
                settings.cloudModel = Self.deepSeekProModel
            }
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(cloudProtocol.rawValue, forKey: Keys.cloudProtocol)
        defaults.set(cloudBaseURL, forKey: Keys.baseURL)
        defaults.set(cloudModel, forKey: Keys.model)
    }

    /// Builds the service for the current choice. `apiKey` defaults to the
    /// stored Keychain secret; pass explicitly in tests.
    @MainActor
    func resolveService(
        apiKey: String? = KeychainStore.read(account: AIProviderSettings.apiKeyAccount)
    ) -> any AIService {
        switch mode {
        case .onDevice:
            return FoundationModelsService.make()
        case .cloud:
            switch cloudProtocol {
            case .openAI:
                return CloudAIService(
                    configuration: CloudAIService.Configuration(
                        baseURLString: cloudBaseURL,
                        model: cloudModel,
                        apiKey: apiKey ?? ""
                    )
                )
            case .anthropic:
                return AnthropicAIService(
                    configuration: AnthropicAIService.Configuration(
                        baseURLString: cloudBaseURL,
                        model: cloudModel,
                        apiKey: apiKey ?? ""
                    )
                )
            }
        }
    }

    /// The chosen route's service when it can serve; otherwise the *other*
    /// route when it can (e.g. on-device model ineligible but a DeepSeek key
    /// is configured — features shouldn't dead-end). When neither is usable,
    /// returns the chosen route's service so its unavailability reason
    /// surfaces to the user.
    @MainActor
    func resolveUsableService(
        apiKey: String? = KeychainStore.read(account: AIProviderSettings.apiKeyAccount)
    ) -> (service: any AIService, route: AIProviderMode, fellBack: Bool) {
        let chosen = resolveService(apiKey: apiKey)
        if chosen.availability.isAvailable {
            return (chosen, mode, false)
        }
        var alternate = self
        alternate.mode = mode == .onDevice ? .cloud : .onDevice
        let alternateService = alternate.resolveService(apiKey: apiKey)
        if alternateService.availability.isAvailable {
            return (alternateService, alternate.mode, true)
        }
        return (chosen, mode, false)
    }
}
