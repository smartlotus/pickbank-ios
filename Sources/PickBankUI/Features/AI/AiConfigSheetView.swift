import PickBankCore
import SwiftUI

public struct AiConfigSheetView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderName = ""
    @State private var baseUrl = ""
    @State private var modelId = ""
    @State private var apiKey = ""
    @State private var newPresetName = ""
    @State private var newPresetPrompt = ""
    @State private var editingPresetId: String? = nil

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("界面语言 (Language)") {
                    Picker("显示语言", selection: Binding(
                        get: { viewModel.language },
                        set: { lang in Task { await viewModel.setLanguage(lang) } }
                    )) {
                        Text("简体中文").tag(AppLanguage.zhHans)
                        Text("English").tag(AppLanguage.en)
                    }
                    .pickerStyle(.segmented)
                }

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

                Section("接口配置与密钥（保存在系统 Keychain）") {
                    TextField("Base URL", text: $baseUrl)
                        .autocorrectionDisabled()
                        .pickbankNoAutocapitalization()
                    TextField("Model ID", text: $modelId)
                        .autocorrectionDisabled()
                        .pickbankNoAutocapitalization()
                    SecureField("API Key (sk-...)", text: $apiKey)
                }

                Section("连通性与问账管道验证") {
                    Button("发送测试请求 (Connectivity)") {
                        Task {
                            await viewModel.saveAiConfig(providerName: selectedProviderName, baseUrl: baseUrl, modelId: modelId, apiKey: apiKey)
                            await viewModel.testAiConnectivity()
                        }
                    }
                    if let status = viewModel.aiTestStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }

                    Button("测试本月账本问账管道 (QA)") {
                        Task {
                            await viewModel.saveAiConfig(providerName: selectedProviderName, baseUrl: baseUrl, modelId: modelId, apiKey: apiKey)
                            await viewModel.testAiQa()
                        }
                    }
                    if let qaStatus = viewModel.aiQaTestStatus {
                        Text(qaStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("AI 分析提示词预设") {
                    ForEach(viewModel.snapshot.preferences.promptPresets) { preset in
                        HStack {
                            Button {
                                Task { await viewModel.selectPromptPreset(id: preset.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(preset.name).fontWeight(.semibold).foregroundStyle(.primary)
                                        if preset.id == viewModel.snapshot.preferences.selectedPromptPresetId {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                                        }
                                    }
                                    Text(preset.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if !preset.builtIn {
                                Button("编辑") {
                                    editingPresetId = preset.id
                                    newPresetName = preset.name
                                    newPresetPrompt = preset.prompt
                                }
                                .font(.caption)
                                Button(role: .destructive) {
                                    Task { await viewModel.deletePromptPreset(id: preset.id) }
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("新建/编辑预设名称", text: $newPresetName)
                        TextField("提示词内容（指导 AI 的分析角度）", text: $newPresetPrompt, axis: .vertical)
                            .lineLimit(2...4)
                        HStack {
                            Button(editingPresetId == nil ? "添加提示词预设" : "保存提示词修改") {
                                let eid = editingPresetId
                                let n = newPresetName
                                let p = newPresetPrompt
                                Task {
                                    await viewModel.savePromptPreset(editingId: eid, name: n, prompt: p)
                                    editingPresetId = nil
                                    newPresetName = ""
                                    newPresetPrompt = ""
                                }
                            }
                            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPresetPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if editingPresetId != nil {
                                Button("取消编辑") {
                                    editingPresetId = nil
                                    newPresetName = ""
                                    newPresetPrompt = ""
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI 与偏好设置")
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
