//
//  FolderBackupProvider.swift
//  Empty
//

import Foundation

nonisolated enum FolderBackupProviderError: LocalizedError {
    case noFolderConfigured
    case bookmarkResolutionFailed
    case cannotAccessFolder
    case selectedURLIsNotFolder
    case snapshotMissing

    var errorDescription: String? {
        switch self {
        case .noFolderConfigured:
            "还没有选择备份文件夹。"
        case .bookmarkResolutionFailed:
            "无法重新打开已保存的文件夹授权，请重新选择一次。"
        case .cannotAccessFolder:
            "无法访问这个文件夹。请确认 Files 授权仍然有效。"
        case .selectedURLIsNotFolder:
            "请选择文件夹，而不是单个文件。"
        case .snapshotMissing:
            "所选文件夹里还没有 Empty 读者快照。"
        }
    }
}

nonisolated struct FolderBackupProvider {
    static let snapshotFilename = "empty-reader-backup.json"
    static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(iOS)
        []
        #else
        [.withSecurityScope]
        #endif
    }

    static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(iOS)
        []
        #else
        [.withSecurityScope]
        #endif
    }

    let target: SyncSettings.FolderBackupTarget

    func export(snapshot: SyncSnapshot) throws -> URL {
        try withResolvedFolder { folderURL in
            let fileURL = folderURL.appending(path: Self.snapshotFilename, directoryHint: .notDirectory)
            let data = try Self.makeSnapshotEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }

    func restoreLatest() throws -> SyncSnapshot {
        try withResolvedFolder { folderURL in
            let fileURL = folderURL.appending(path: Self.snapshotFilename, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: fileURL.path()) else {
                throw FolderBackupProviderError.snapshotMissing
            }
            let data = try Data(contentsOf: fileURL)
            return try Self.makeSnapshotDecoder().decode(SyncSnapshot.self, from: data)
        }
    }

    static func validateSelectionURL(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw FolderBackupProviderError.selectedURLIsNotFolder
        }
    }

    private static func makeSnapshotEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeSnapshotDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func withResolvedFolder<T>(_ body: (URL) throws -> T) throws -> T {
        var stale = false
        let folderURL: URL
        do {
            folderURL = try URL(
                resolvingBookmarkData: target.bookmarkData,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw FolderBackupProviderError.bookmarkResolutionFailed
        }
        if stale {
            // The URL is still usable right now; the next explicit selection
            // will refresh the bookmark.
        }
        let isScoped = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped { folderURL.stopAccessingSecurityScopedResource() }
        }
        guard isScoped || folderURL.isFileURL else {
            throw FolderBackupProviderError.cannotAccessFolder
        }
        return try body(folderURL)
    }
}

