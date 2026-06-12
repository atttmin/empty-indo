//
//  SyncSettingsView.swift
//  Empty
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SyncSettingsView: View {
    @EnvironmentObject private var appSession: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext

    @State private var isPickingFolder = false
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var confirmRestore = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    liveSyncSection
                    folderBackupSection
                    roadmapSection
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.accent)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .emptyCard(palette, radius: 12)
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
            }
        }
        .background(palette.window)
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderPick
        )
        .confirmationDialog(
            "从这个文件夹恢复最新 Empty 读者快照？",
            isPresented: $confirmRestore,
            titleVisibility: .visible
        ) {
            Button("恢复", role: .destructive) {
                restoreLatestSnapshot()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复只会 merge / upsert 已备份的读者数据，不会导入正文、chunk 或 embedding。")
        }
        .alert(
            "出了点问题",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(iOS)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("同步与备份")
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("同步读者数据，不同步书正文")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("×")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink3)
                    .frame(width: 28, height: 28)
                    .background(palette.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 16))
    }

    private var liveSyncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("实时同步")
                .font(.system(size: 12, weight: .bold))
                .kerning(1.4)
                .foregroundStyle(palette.ink3)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SyncProviderCatalog.liveProviders) { provider in
                    Button {
                        applyLiveMode(provider.mode)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(provider.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(palette.ink)
                                    Text(provider.badge)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(provider.mode == appSession.effectiveLiveMode ? palette.window : palette.ink3)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(
                                            provider.mode == appSession.effectiveLiveMode ? palette.accent : palette.accentSoft,
                                            in: Capsule()
                                        )
                                }
                                Text(provider.detail)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.ink2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: provider.mode == appSession.effectiveLiveMode ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(provider.mode == appSession.effectiveLiveMode ? palette.accent : palette.line2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .emptyCard(palette, radius: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || appSession.isEphemeral)
                }
            }
            Text("书库元数据、进度、高亮、卡片和 ReaderMemory 可同步；EPUB/PDF 文件、章节正文、翻译缓存、MemoryEmbedding 仍留在本机。")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.ink3)
            if appSession.isEphemeral {
                Text("当前是测试 / clean-room 容器，实时同步固定为仅本机。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.accent)
            }
        }
    }

    private var folderBackupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("第三方云 / 文件夹")
                .font(.system(size: 12, weight: .bold))
                .kerning(1.4)
                .foregroundStyle(palette.ink3)
            VStack(alignment: .leading, spacing: 10) {
                Text("选择任意 Files / File Provider 文件夹：iCloud Drive、Dropbox、OneDrive、Google Drive、SMB 或 NAS 都可以。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink2)
                if let target = appSession.syncSettings.folderTarget {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(target.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.ink)
                            Text(FolderBackupProvider.snapshotFilename)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.ink3)
                        }
                        if let lastSnapshotAt = target.lastSnapshotAt {
                            Text("上次备份 · \(lastSnapshotAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.ink3)
                        }
                        HStack(spacing: 8) {
                            actionButton("更换文件夹") { isPickingFolder = true }
                            actionButton(isBusy ? "备份中…" : "立即备份") { backupSnapshot() }
                                .disabled(isBusy)
                            actionButton(isBusy ? "恢复中…" : "恢复最新备份") { confirmRestore = true }
                                .disabled(isBusy)
                        }
                        Button(role: .destructive) {
                            appSession.clearBackupFolder()
                            statusMessage = "已移除文件夹目标。"
                        } label: {
                            Text("移除目标")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .emptyCard(palette, radius: 12)
                } else {
                    actionButton("选择文件夹") { isPickingFolder = true }
                }
                Text("文件夹路径当前是“可恢复快照”，不是实时双向合并。恢复时以你主动选择的快照为准，做 merge / upsert，不删除本机额外数据。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
            }
        }
    }

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("后续 provider")
                .font(.system(size: 12, weight: .bold))
                .kerning(1.4)
                .foregroundStyle(palette.ink3)
            Text("下一步会在同一套快照 / provider 边界上接 Empty Cloud / 自建 server；Passkey 先做账号登录，Walrus 先做可选导出 / 备份层，不把钱包与存储绑死。")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.ink2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .emptyCard(palette, radius: 12)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(palette.accent.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyLiveMode(_ mode: SyncLiveMode) {
        do {
            try appSession.setLiveMode(mode)
            statusMessage = "已切换到 \(mode.title)。"
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            try appSession.rememberBackupFolder(url)
            statusMessage = "已把备份目标设为 \(appSession.syncSettings.folderTarget?.displayName ?? url.lastPathComponent)。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func backupSnapshot() {
        guard let target = appSession.syncSettings.folderTarget else {
            errorMessage = FolderBackupProviderError.noFolderConfigured.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let snapshot = try SyncSnapshot.capture(from: modelContext)
            let fileURL = try FolderBackupProvider(target: target).export(snapshot: snapshot)
            appSession.markBackupCompleted(at: snapshot.exportedAt)
            statusMessage = "已写入 \(fileURL.lastPathComponent)。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreLatestSnapshot() {
        guard let target = appSession.syncSettings.folderTarget else {
            errorMessage = FolderBackupProviderError.noFolderConfigured.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let snapshot = try FolderBackupProvider(target: target).restoreLatest()
            try snapshot.merge(into: modelContext)
            statusMessage = "已把快照合并回当前书库。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SyncSettingsView()
        .environmentObject(AppSession.preview)
        .modelContainer(try! AppStores.makeContainer(ephemeral: true))
}
