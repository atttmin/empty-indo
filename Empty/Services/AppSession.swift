//
//  AppSession.swift
//  Empty
//

import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var containerRevision = UUID()

    let isEphemeral: Bool

    init(isEphemeral override: Bool? = nil) {
        let process = ProcessInfo.processInfo
        let inferredEphemeral =
            process.environment["XCTestConfigurationFilePath"] != nil
            || process.arguments.contains("-ScreenshotCleanRoom")
        isEphemeral = override ?? inferredEphemeral

        do {
            container = try AppStores.makeContainer(ephemeral: isEphemeral)
        } catch {
            fatalError("Failed to set up persistence: \(error)")
        }
    }

    static var preview: AppSession {
        AppSession(isEphemeral: true)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        _ = phase
    }
}
