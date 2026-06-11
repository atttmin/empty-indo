//
//  AIProviderRegistry.swift
//  Empty
//
//  P0 handoff §3 多模型: a provider LIST with per-feature routing and a
//  fallback chain, upgrading the single mode/protocol choice. The legacy
//  `AIProviderSettings` remains the storage for the editable cloud config
//  (the diagnostics screen edits it); the registry mirrors it as the
//  "linked" cloud provider and layers routing on top.
//
//  Fallback chain per the spec: routed provider → default provider →
//  local — and when nothing can serve, the routed provider is returned
//  so its unavailability reason reaches the UI (features degrade
//  silently; reading itself never blocks).
//

import Foundation

nonisolated enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case local
    case openAI
    case anthropic

    var title: String {
        switch self {
        case .local: "Apple 本地"
        case .openAI: "OpenAI 兼容"
        case .anthropic: "Anthropic 兼容"
        }
    }
}

nonisolated struct AIProvider: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: AIProviderKind
    var baseURL: String = ""
    var model: String = ""
    /// Keychain account holding this provider's key; empty = keyless.
    var keychainAccount: String = ""

    var isLocal: Bool { kind == .local }
}

/// The AI features that can be routed to different providers.
nonisolated enum AIFeature: String, Codable, CaseIterable, Sendable {
    case translate
    case recap
    case chat
    case vocab

    var title: String {
        switch self {
        case .translate: "翻译 · 导读"
        case .recap: "回顾 · 概览"
        case .chat: "伴读对话"
        case .vocab: "词汇"
        }
    }
}

nonisolated struct AIProviderRegistry: Codable, Equatable, Sendable {
    var providers: [AIProvider]
    var defaultProviderID: UUID
    /// AIFeature.rawValue → provider id. Missing key = default provider.
    var routes: [String: UUID] = [:]

    /// Stable identities so migration and the legacy-linked cloud entry
    /// survive reloads.
    static let localID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let linkedCloudID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private static let storageKey = "ai.providers.registry.v1"

    static let localProvider = AIProvider(
        id: localID,
        name: "On-Device · Apple",
        kind: .local
    )

    // MARK: Load / save

    /// Loads the registry, synthesizing it from the legacy single-provider
    /// settings on first run — and re-syncing the linked cloud entry with
    /// the legacy config every load, since the diagnostics screen edits
    /// the legacy fields.
    static func load(defaults: UserDefaults = .standard) -> AIProviderRegistry {
        let legacy = AIProviderSettings.load(from: defaults)
        var registry: AIProviderRegistry
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(AIProviderRegistry.self, from: data) {
            registry = stored
        } else {
            registry = AIProviderRegistry(
                providers: [localProvider],
                defaultProviderID: legacy.mode == .cloud ? linkedCloudID : localID
            )
        }

        if !registry.providers.contains(where: { $0.id == localID }) {
            registry.providers.insert(localProvider, at: 0)
        }

        // Mirror the legacy cloud config as the linked provider.
        let linked = AIProvider(
            id: linkedCloudID,
            name: legacy.cloudBaseURL.contains("kimi")
                ? "Kimi Code"
                : (legacy.cloudBaseURL.contains("deepseek") ? "DeepSeek" : "云端"),
            kind: legacy.cloudProtocol == .anthropic ? .anthropic : .openAI,
            baseURL: legacy.cloudBaseURL,
            model: legacy.cloudModel,
            keychainAccount: AIProviderSettings.apiKeyAccount
        )
        if let index = registry.providers.firstIndex(where: { $0.id == linkedCloudID }) {
            registry.providers[index] = linked
        } else {
            registry.providers.append(linked)
        }

        if !registry.providers.contains(where: { $0.id == registry.defaultProviderID }) {
            registry.defaultProviderID = localID
        }
        return registry
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: Routing

    func provider(id: UUID) -> AIProvider? {
        providers.first { $0.id == id }
    }

    /// The provider a feature routes to (explicit route → default).
    func provider(for feature: AIFeature) -> AIProvider {
        if let routed = routes[feature.rawValue], let provider = provider(id: routed) {
            return provider
        }
        return provider(id: defaultProviderID) ?? Self.localProvider
    }

    mutating func route(_ feature: AIFeature, to providerID: UUID?) {
        if let providerID {
            routes[feature.rawValue] = providerID
        } else {
            routes.removeValue(forKey: feature.rawValue)
        }
    }

    // MARK: Services

    @MainActor
    func service(for provider: AIProvider, apiKey: String? = nil) -> any AIService {
        switch provider.kind {
        case .local:
            return FoundationModelsService.make()
        case .openAI:
            return CloudAIService(
                configuration: CloudAIService.Configuration(
                    baseURLString: provider.baseURL,
                    model: provider.model,
                    apiKey: apiKey
                        ?? KeychainStore.read(account: provider.keychainAccount)
                        ?? ""
                )
            )
        case .anthropic:
            return AnthropicAIService(
                configuration: AnthropicAIService.Configuration(
                    baseURLString: provider.baseURL,
                    model: provider.model,
                    apiKey: apiKey
                        ?? KeychainStore.read(account: provider.keychainAccount)
                        ?? ""
                )
            )
        }
    }

    /// Resolves a feature through the fallback chain: routed provider →
    /// default provider → local. When none can serve, returns the routed
    /// provider's service so its unavailability reason surfaces.
    @MainActor
    func resolveUsableService(
        feature: AIFeature,
        apiKey: String? = nil
    ) -> (service: any AIService, provider: AIProvider, fellBack: Bool) {
        let routed = provider(for: feature)
        var chain: [AIProvider] = [routed]
        if let fallback = provider(id: defaultProviderID), fallback.id != routed.id {
            chain.append(fallback)
        }
        if !chain.contains(where: { $0.isLocal }) {
            chain.append(provider(id: Self.localID) ?? Self.localProvider)
        }

        for (index, candidate) in chain.enumerated() {
            let service = service(for: candidate, apiKey: apiKey)
            if service.availability.isAvailable {
                return (service, candidate, index > 0)
            }
        }
        return (service(for: routed, apiKey: apiKey), routed, false)
    }
}
