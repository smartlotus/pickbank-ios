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
                        Text(zh ? "AI 问账" : "AI Financial Advisor")
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

                // Question Input & Local-Search Actions (Android AiAssistantScreen)
                SumCard(highlightAccent: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(zh ? "自然语言账本检索与问答" : "Ask Your Ledger")
                            .font(SumFont.body(15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)

                        TextField("例如：上个月买咖啡一共花了多少钱", text: $viewModel.aiQuestion, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(palette.backgroundElevated))
                            .foregroundStyle(palette.textPrimary)

                        // Prompt preset picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.snapshot.preferences.promptPresets) { preset in
                                    let active = (preset.id == viewModel.snapshot.preferences.selectedPromptPresetId)
                                    Button(preset.name) {
                                        Task { await viewModel.selectPromptPreset(id: preset.id) }
                                    }
                                    .font(SumFont.body(11, weight: active ? .bold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(active ? palette.ink : palette.textSecondary)
                                    .background(Capsule().fill(active ? palette.accent : palette.backgroundElevated))
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task { await viewModel.runAiPeriodAdvice() }
                            } label: {
                                Label(zh ? "生成本月 AI 洞察" : "Monthly Insight", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .pickbankGlassButton()

                            Button {
                                Task { await viewModel.askAiQuestion() }
                            } label: {
                                if viewModel.isAiLoading {
                                    ProgressView().tint(palette.ink).frame(maxWidth: .infinity)
                                } else {
                                    Label(zh ? "开始分析" : "Analyze", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .pickbankGlassButton(prominent: true, tint: palette.accent)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["今天餐饮花了多少？", "上个月买咖啡花了多少钱？", "今年工资收入累计"], id: \.self) { q in
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
                    }
                    .padding(16)
                }

                // Period Advice Output
                if !viewModel.aiAdvice.isEmpty {
                    SumCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("周期洞察报告")
                                .font(SumFont.mono(11, weight: .bold))
                                .foregroundStyle(palette.accent)
                            Text(viewModel.aiAdvice)
                                .font(SumFont.body(14))
                                .foregroundStyle(palette.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                    }
                }

                // Local Query Hit Summary (matching Android "查询结果 · 命中 N 条")
                if let res = viewModel.aiLocalQueryResult {
                    SumCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("查询结果 · 命中 \(res.matchedTransactions.count) 条")
                                    .font(SumFont.body(15, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text(res.rangeLabel)
                                    .font(SumFont.mono(11))
                                    .foregroundStyle(palette.accent)
                            }
                            Text("支出 \(MoneyFormatter.formatYuan(cents: res.totalExpenseCents)) / 收入 \(MoneyFormatter.formatYuan(cents: res.totalIncomeCents))")
                                .font(SumFont.mono(12))
                                .foregroundStyle(palette.textSecondary)
                            if !res.keywords.isEmpty {
                                Text("解析关键词：\(res.keywords.joined(separator: "、"))")
                                    .font(SumFont.body(11))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                        .padding(16)
                    }
                }

                if !viewModel.aiQuestionAnswer.isEmpty {
                    SumCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI 回答")
                                .font(SumFont.mono(11, weight: .bold))
                                .foregroundStyle(palette.income)
                            Text(viewModel.aiQuestionAnswer)
                                .font(SumFont.body(14))
                                .foregroundStyle(palette.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                    }
                }

                // Matched Ledger Entries List (matching Android "命中明细")
                if let matched = viewModel.aiLocalQueryResult?.matchedTransactions, !matched.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("命中明细（最多显示 50 笔）")
                            .font(SumFont.mono(11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        SumCard {
                            LazyVStack(spacing: 0) {
                                ForEach(matched.prefix(50)) { tx in
                                    TransactionRowView(
                                        tx: tx,
                                        categoriesById: viewModel.categoriesById,
                                        walletsById: viewModel.walletsById,
                                        tagsById: viewModel.tagsById
                                    )
                                    if tx.id != matched.prefix(50).last?.id {
                                        Divider().overlay(palette.divider)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showConfigSheet) {
            AiConfigSheetView(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
    }
}
