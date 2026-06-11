//
//  AIDiagnosticsView.swift
//  Empty
//
//  朱 · AI 状态: pick the route (on-device Apple Intelligence or an
//  OpenAI-compatible cloud endpoint, BYOK), then prove the pipeline with
//  a windowed summarize round trip. Styled in the 朱批 design language —
//  the one screen the prototypes never drew.
//

import SwiftUI

struct AIDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.emptyPalette) private var palette

    @State private var settings = AIProviderSettings.load()
    @State private var apiKey = KeychainStore.read(account: AIProviderSettings.apiKeyAccount) ?? ""

    @State private var sampleText = ""
    @State private var summary = ""
    @State private var errorMessage = ""
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionLabel("提供商")
                    providerCards

                    if settings.mode == .cloud {
                        cloudConfig
                    }

                    statusRow

                    sectionLabel("连通性测试")
                    testCard

                    Text("密钥只存在本机 Keychain,不写入配置文件,也不随 iCloud 同步。")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.ink3)
                }
                .padding(EdgeInsets(top: 18, leading: 24, bottom: 28, trailing: 24))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(palette.window)
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 620)
        #endif
        .onChange(of: settings) { _, newValue in
            newValue.save()
        }
        .onChange(of: apiKey) { _, newValue in
            persistAPIKey(newValue)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZhuBadge(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI 状态")
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(palette.ink)
                Text("选择伴读的大脑 · 跑一次连通测试")
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
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 14, trailing: 18))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .kerning(1.6)
            .foregroundStyle(palette.ink3)
    }

    // MARK: Provider choice

    private var providerCards: some View {
        HStack(spacing: 12) {
            providerCard(
                mode: .onDevice,
                title: "On-Device",
                vendor: "Apple Intelligence",
                detail: "本机模型 — 本地、免费、私密,离线也能伴读。"
            )
            providerCard(
                mode: .cloud,
                title: "Cloud · BYOK",
                vendor: "OpenAI 兼容接口",
                detail: "自带密钥接云端模型,内置 DeepSeek 预设。"
            )
        }
    }

    private func providerCard(
        mode: AIProviderMode,
        title: String,
        vendor: String,
        detail: String
    ) -> some View {
        let isActive = settings.mode == mode
        return Button {
            settings.mode = mode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 0)
                    if isActive {
                        Text("使用中")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(palette.accent, in: Capsule())
                    }
                }
                Text(vendor)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(detail)
                    .font(.system(size: 11.5))
                    .lineSpacing(4)
                    .foregroundStyle(palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? palette.accentSoft : palette.card,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isActive ? palette.accent : palette.line,
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Cloud config

    private var cloudConfig: some View {
        VStack(alignment: .leading, spacing: 12) {
            configField("Base URL") {
                TextField("https://…", text: $settings.cloudBaseURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }
            configField("模型") {
                TextField("model id", text: $settings.cloudModel)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            configField("API Key") {
                SecureField("sk-…", text: $apiKey)
            }

            HStack(spacing: 8) {
                Text("预设")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
                presetChip("DeepSeek Flash", model: AIProviderSettings.deepSeekModel)
                presetChip("DeepSeek Pro", model: AIProviderSettings.deepSeekProModel)
            }
        }
        .padding(16)
        .emptyCard(palette, radius: 14)
    }

    private func configField(
        _ label: String,
        @ViewBuilder field: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(palette.ink3)
            field()
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.window, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(palette.line2, lineWidth: 1)
                )
        }
    }

    private func presetChip(_ title: String, model: String) -> some View {
        let isActive = settings.cloudModel == model
            && settings.cloudBaseURL == AIProviderSettings.deepSeekBaseURL
        return Button {
            applyDeepSeekPreset(model: model)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.accent : palette.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? palette.accentSoft : .clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? palette.accentSoft2 : palette.line2,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(resolvedAvailability.isAvailable ? palette.accent : palette.ink3)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.ink2)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.side, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusText: String {
        switch resolvedAvailability {
        case .available:
            settings.mode == .onDevice
                ? "本机模型就绪 — 朱批可以落笔了。"
                : "\(settings.cloudModel) @ \(settings.cloudBaseURL)"
        case .unavailable(let reason):
            reason
        }
    }

    // MARK: Round trip

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "贴几段文字,让 AI 摘要一次,证明管线通了…",
                text: $sampleText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineSpacing(5)
            .foregroundStyle(palette.ink)
            .lineLimit(4...10)
            .padding(12)
            .background(palette.window, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(palette.line2, lineWidth: 1)
            )

            Button {
                runRoundTrip()
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRunning ? "正在摘要…" : "朱 · 测一次摘要")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(canRun ? palette.accent : palette.ink3, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canRun)

            if !summary.isEmpty {
                ZhupiCallout(title: "朱批 · 摘要结果") {
                    Text(summary)
                        .font(.system(size: 12.5))
                        .lineSpacing(5)
                        .foregroundStyle(palette.ink2)
                        .textSelection(.enabled)
                }
            }
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .emptyCard(palette, radius: 14)
    }

    private var canRun: Bool {
        !isRunning
            && resolvedAvailability.isAvailable
            && !sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Logic (unchanged)

    private var resolvedAvailability: AIAvailability {
        settings.resolveService(apiKey: apiKey).availability
    }

    private func applyDeepSeekPreset(model: String) {
        settings.cloudBaseURL = AIProviderSettings.deepSeekBaseURL
        settings.cloudModel = model
    }

    private func persistAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: AIProviderSettings.apiKeyAccount)
        } else {
            try? KeychainStore.save(trimmed, account: AIProviderSettings.apiKeyAccount)
        }
    }

    private func runRoundTrip() {
        summary = ""
        errorMessage = ""
        isRunning = true
        let text = sampleText
        let service = settings.resolveService(apiKey: apiKey)
        Task {
            defer { isRunning = false }
            do {
                summary = try await service.summarize(text, focus: .digest)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AIDiagnosticsView()
}
