import PickBankCore
import SwiftUI

public struct AiAdvisorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @State private var showConfigSheet = false

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        let zh = (viewModel.language == .zhHans)
        let hasKey = !viewModel.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BYOK · KEYCHAIN")
                            .font(SumFont.mono(11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(zh ? "AI 智能问账与洞察" : "AI Financial Advisor")
                            .font(SumFont.heading(24, hermes: palette.isHermes))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    Button {
                        showConfigSheet = true
                    } label: {
                        Label(hasKey ? viewModel.snapshot.preferences.selectedAiProviderName : "配置 Key", systemImage: "key.fill")
                    }
                    .pickbankGlassButton(prominent: !hasKey, tint: palette.accent)
                }

                SumCard(highlightAccent: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(zh ? "周期消费体检（基于当前「总结」统计周期）" : "Period Insight")
                                .font(SumFont.body(15, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Button {
                                Task { await viewModel.runAiPeriodAdvice() }
                            } label: {
                                if viewModel.isAiLoading {
                                    ProgressView().tint(palette.ink)
                                } else {
                                    Text(zh ? "立即分析" : "Analyze")
                                }
                            }
                            .pickbankGlassButton(prominent: true, tint: palette.accent)
                        }

                        if viewModel.aiAdvice.isEmpty {
                            Text(hasKey
                                 ? "点击「立即分析」，使用 \(viewModel.snapshot.preferences.selectedAiProviderName) (\(viewModel.snapshot.preferences.aiModelId)) 剖析当前周期收支结构。"
                                 : "尚未配置外部 API Key，点击「立即分析」仍可立刻生成本地离线统计洞察，隐私零外传。")
                                .font(SumFont.body(13))
                                .foregroundStyle(palette.textSecondary)
                        } else {
                            Text(viewModel.aiAdvice)
                                .font(SumFont.body(14))
                                .foregroundStyle(palette.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }

                SumCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(zh ? "对账本发问" : "Ask Your Ledger")
                            .font(SumFont.body(15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)

                        HStack(spacing: 8) {
                            TextField("例如：这个月餐饮花了多少？有哪些可省的？", text: $viewModel.aiQuestion)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(palette.backgroundElevated))
                                .foregroundStyle(palette.textPrimary)
                            Button(zh ? "提问" : "Ask") {
                                Task { await viewModel.askAiQuestion() }
                            }
                            .pickbankGlassButton(prominent: true, tint: palette.accent)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["本月餐饮花了多少？", "哪天消费最高？", "帮我制定下周省钱预算"], id: \.self) { q in
                                    Button(q) {
                                        viewModel.aiQuestion = q
                                        Task { await viewModel.askAiQuestion() }
                                    }
                                    .font(SumFont.body(11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(palette.backgroundElevated))
                                    .foregroundStyle(palette.textSecondary)
                                }
                            }
                        }

                        if !viewModel.aiQuestionAnswer.isEmpty {
                            Divider().overlay(palette.divider)
                            Text(viewModel.aiQuestionAnswer)
                                .font(SumFont.body(14))
                                .foregroundStyle(palette.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showConfigSheet) {
            AiConfigSheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
    }
}

private struct AiConfigSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderName = ""
    @State private var baseUrl = ""
    @State private var modelId = ""
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("选择兼容服务商 (OpenAI Protocol)") {
                    ForEach(AiModelPreset.builtInPresets) { preset in
                        Button {
                            selectedProviderName = preset.name
                            baseUrl = preset.baseUrl
                            modelId = preset.defaultModel
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.name).foregroundStyle(.primary)
                                    Text(preset.defaultModel).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedProviderName == preset.name {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                Section("接口配置与密钥（保存在 iOS Keychain）") {
                    TextField("Base URL", text: $baseUrl).autocorrectionDisabled()
                    TextField("Model ID", text: $modelId).autocorrectionDisabled()
                    SecureField("API Key (sk-...)", text: $apiKey)
                }
                Section("连通性测试") {
                    Button("发送测试请求") {
                        Task {
                            await viewModel.saveAiConfig(providerName: selectedProviderName, baseUrl: baseUrl, modelId: modelId, apiKey: apiKey)
                            await viewModel.testAiConnectivity()
                        }
                    }
                    if let status = viewModel.aiTestStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("BYOK AI 设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await viewModel.saveAiConfig(providerName: selectedProviderName, baseUrl: baseUrl, modelId: modelId, apiKey: apiKey)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                selectedProviderName = viewModel.snapshot.preferences.selectedAiProviderName
                baseUrl = viewModel.snapshot.preferences.customAiBaseUrl
                modelId = viewModel.snapshot.preferences.aiModelId
                apiKey = viewModel.aiApiKey
            }
        }
    }
}
