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
    @Published private(set) var syncSettings: SyncSettings
    @Published private(set) var containerRevision = UUID()

    let isEphemeral: Bool

    init(isEphemeral override: Bool? = nil) {
        let process = ProcessInfo.processInfo
        let inferredEphemeral = process.environment["XCTestConfigurationFilePath"] != nil
            || process.arguments.contains("-ScreenshotCleanRoom")
        isEphemeral = override ?? inferredEphemeral
        let loadedSettings = SyncSettings.load()
        syncSettings = loadedSettings
        let mode = isEphemeral ? SyncLiveMode.localOnly : loadedSettings.liveMode
        do {
            container = try AppStores.makeContainer(syncMode: mode, ephemeral: isEphemeral)
        } catch {
            fatalError("Failed to set up persistence: \(error)")
        }
    }

    static var preview: AppSession {
        AppSession(isEphemeral: true)
    }

    var effectiveLiveMode: SyncLiveMode {
        isEphemeral ? .localOnly : syncSettings.liveMode
    }

    func setLiveMode(_ mode: SyncLiveMode) throws {
        guard !isEphemeral else { return }
        guard syncSettings.liveMode != mode else { return }
        var updated = syncSettings
        updated.liveMode = mode
        let newContainer = try AppStores.makeContainer(syncMode: mode, ephemeral: false)
        updated.save()
        syncSettings = updated
        container = newContainer
        containerRevision = UUID()
    }

    func rememberBackupFolder(_ url: URL) throws {
        try FolderBackupProvider.validateSelectionURL(url)
        let bookmarkData = try url.bookmarkData(
            options: FolderBackupProvider.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let displayName = try url.resourceValues(forKeys: [.nameKey]).name ?? url.lastPathComponent
        var updated = syncSettings
        updated.folderTarget = .init(
            bookmarkData: bookmarkData,
            displayName: displayName,
            lastSnapshotAt: updated.folderTarget?.lastSnapshotAt
        )
        updated.save()
        syncSettings = updated
    }

    func clearBackupFolder() {
        var updated = syncSettings
        updated.folderTarget = nil
        updated.save()
        syncSettings = updated
    }

    func markBackupCompleted(at date: Date = Date()) {
        guard var target = syncSettings.folderTarget else { return }
        target.lastSnapshotAt = date
        var updated = syncSettings
        updated.folderTarget = target
        updated.save()
        syncSettings = updated
    }
}
