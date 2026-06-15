//
//  BackupSettingsView.swift
//  Empty
//

import SwiftData
import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var appSession: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette
    @Environment(\.modelContext) private var modelContext

    @State private var showDataBoundary = true
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var backupDocument = ReaderNotesBackupDocument.empty()
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    currentStateSection
                    backupActionsSection
                    dataBoundarySection
                    if let statusMessage {
                        statusCard(statusMessage)
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
            }
        }
        .background(palette.window)
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .emptyNotes,
            defaultFilename: defaultExportFilename
        ) { result in
            switch result {
            case .success:
                statusMessage = "已导出读者笔记包：\(backupDocument.package.counts.total) 条记录。"
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ReaderNotesBackupDocument.readableContentTypes,
            allowsMultipleSelection: false,
            onCompletion: importNotes
        )
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("本机数据")
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("当前没有云同步，所有内容只在这台设备上")
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

    private var currentStateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("现在怎么存")
                .sectionLabel(palette)
            VStack(alignment: .leading, spacing: 8) {
                Text(appSession.isEphemeral ? "临时本机容器" : "本机 SwiftData")
                    .font(.system(size: 15, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("书库元数据、阅读进度、高亮、批注、单词、学习卡片和 ReaderMemory 都只保存在本机。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink2)
                Text("导出包只包含读者数据，不包含 EPUB/PDF 文件、章节正文、译文缓存、embedding 或 API Key。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .emptyCard(palette, radius: 12)
        }
    }

    private var backupActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("读者笔记包")
                .sectionLabel(palette)
            VStack(alignment: .leading, spacing: 10) {
                Text("导出 / 导入 .empty-notes")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text("用于备份或迁移高亮、批注、单词、书签、学习卡片、ReaderMemory 和书籍元数据。导入是合并，不会删除本机已有记录。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink2)
                HStack(spacing: 8) {
                    actionButton("导出读者笔记") {
                        exportNotes()
                    }
                    actionButton("导入读者笔记") {
                        isImporting = true
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .emptyCard(palette, radius: 12)
        }
    }

    private var dataBoundarySection: some View {
        DisclosureGroup(isExpanded: $showDataBoundary) {
            VStack(alignment: .leading, spacing: 8) {
                dataBoundaryRow(
                    title: "会进备份包",
                    detail: "Book 元数据、ReadingSession、高亮、批注、VocabEntry、Bookmark、StudyCardEntry、MemoryItem。"
                )
                dataBoundaryRow(
                    title: "永远只留本机",
                    detail: "导入的 EPUB/PDF 文件、章节正文、Chunk、ParagraphTranslation、MemoryEmbedding、AI API Key。"
                )
                Text("跨 store 仍只通过 Book.id 关联。这个边界让备份包小、可读、可审计，也避免把整本书正文误传出去。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("数据边界")
                    .sectionLabel(palette)
                Text("先把哪些内容值得备份说清楚。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.ink3)
            }
        }
    }

    private func dataBoundaryRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.ink)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.ink2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emptyCard(palette, radius: 12)
    }

    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(palette.accent)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .emptyCard(palette, radius: 12)
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

    private var defaultExportFilename: String {
        "Empty-Notes-\(Self.filenameDateFormatter.string(from: Date())).empty-notes"
    }

    private func exportNotes() {
        do {
            let package = try ReaderNotesBackupStore(modelContext: modelContext).exportPackage()
            backupDocument = ReaderNotesBackupDocument(package: package)
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importNotes(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let package = try ReaderNotesBackupCodec.decode(data)
            let summary = try ReaderNotesBackupStore(modelContext: modelContext)
                .importPackage(package)
            statusMessage = "导入完成：\(summary.displayText)。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()
}

private extension Text {
    func sectionLabel(_ palette: EmptyPalette) -> some View {
        self
            .font(.system(size: 12, weight: .bold))
            .kerning(1.4)
            .foregroundStyle(palette.ink3)
    }
}

#Preview {
    BackupSettingsView()
        .environmentObject(AppSession.preview)
        .modelContainer(try! AppStores.makeContainer(ephemeral: true))
}
