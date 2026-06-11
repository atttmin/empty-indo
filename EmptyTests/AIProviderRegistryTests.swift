//
//  AIProviderRegistryTests.swift
//  EmptyTests
//
//  P0 多模型: provider list, per-feature routing, fallback chain, and
//  the migration that mirrors the legacy single-cloud config.
//

import Foundation
import Testing
@testable import Empty

struct AIProviderRegistryTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "registry-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func migratesLegacySettingsIntoLinkedProvider() {
        let defaults = makeDefaults()
        var legacy = AIProviderSettings()
        legacy.mode = .cloud
        legacy.cloudProtocol = .anthropic
        legacy.cloudBaseURL = AIProviderSettings.kimiBaseURL
        legacy.cloudModel = AIProviderSettings.kimiModel
        legacy.save(to: defaults)

        let registry = AIProviderRegistry.load(defaults: defaults)

        #expect(registry.providers.contains { $0.id == AIProviderRegistry.localID })
        let linked = registry.provider(id: AIProviderRegistry.linkedCloudID)
        #expect(linked?.kind == .anthropic)
        #expect(linked?.name == "Kimi Code")
        #expect(linked?.baseURL == AIProviderSettings.kimiBaseURL)
        #expect(registry.defaultProviderID == AIProviderRegistry.linkedCloudID)
    }

    @Test func unroutedFeatureFollowsDefaultAndRoutesPersist() {
        let defaults = makeDefaults()
        var registry = AIProviderRegistry.load(defaults: defaults)

        // Unrouted → default provider.
        #expect(registry.provider(for: .translate).id == registry.defaultProviderID)

        // Route 翻译 to the linked cloud provider and persist.
        registry.route(.translate, to: AIProviderRegistry.linkedCloudID)
        registry.save(defaults: defaults)

        let reloaded = AIProviderRegistry.load(defaults: defaults)
        #expect(reloaded.provider(for: .translate).id == AIProviderRegistry.linkedCloudID)
        #expect(reloaded.provider(for: .chat).id == reloaded.defaultProviderID)

        // Clearing the route falls back to default.
        var cleared = reloaded
        cleared.route(.translate, to: nil)
        #expect(cleared.provider(for: .translate).id == cleared.defaultProviderID)
    }

    @Test func legacyConfigEditsReflectInLinkedProviderOnReload() {
        let defaults = makeDefaults()
        _ = AIProviderRegistry.load(defaults: defaults).save(defaults: defaults)

        var legacy = AIProviderSettings.load(from: defaults)
        legacy.cloudBaseURL = "https://example.com/v1"
        legacy.cloudModel = "custom-model"
        legacy.cloudProtocol = .openAI
        legacy.save(to: defaults)

        let registry = AIProviderRegistry.load(defaults: defaults)
        let linked = registry.provider(id: AIProviderRegistry.linkedCloudID)
        #expect(linked?.baseURL == "https://example.com/v1")
        #expect(linked?.model == "custom-model")
        #expect(linked?.kind == .openAI)
    }

    @Test func dropsDanglingDefaultToLocal() {
        let defaults = makeDefaults()
        var registry = AIProviderRegistry.load(defaults: defaults)
        registry.defaultProviderID = UUID()
        registry.save(defaults: defaults)

        let reloaded = AIProviderRegistry.load(defaults: defaults)
        #expect(reloaded.defaultProviderID == AIProviderRegistry.localID)
    }
}
