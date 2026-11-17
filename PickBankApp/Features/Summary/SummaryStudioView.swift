import Charts
import PickBankCore
import SwiftUI

public struct SummaryStudioView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        let zh = (viewModel.language == .zhHans)
        let report = viewModel.activeSummaryReport
        let activeShares = viewModel.summaryTypeTab == .income ? report.incomeShares : report.expenseShares

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header + Quick Theme/Lang/Export bar
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(zh ? "SUMMARY STUDIO" : "ANALYTICS")
                            .font(SumFont.mono(11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(zh ? "收支总结看板" : "Summary Analytics")
                            .font(SumFont.heading(26, hermes: palette.isHermes))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    Menu {
                        Button(zh ? "导出 Excel 工作簿 (.xlsx)" : "Export Excel (.xlsx)") {
                            Task { await viewModel.prepareExport(kind: .xlsx) }
                        }
                        Button(zh ? "导出表格 (.csv)" : "Export CSV") {
                            Task { await viewModel.prepareExport(kind: .csv) }
                        }
                        Button(zh ? "导出无损全量备份 (.pickbank.json)" : "Export Lossless Archive") {
                            Task { await viewModel.prepareExport(kind: .losslessJson) }
                        }
                        Divider()
                        Button(zh ? "切换语言：\(zh ? "EN" : "中文")" : "Language: 中文") {
                            Task { await viewModel.setLanguage(zh ? .en : .zhHans) }
                        }
                    } label: {
                        Label(zh ? "导出 / 语言" : "Export", systemImage: "square.and.arrow.up")
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }

                // Period selector (v1.9.2 contract: switching dimension resets anchor to today)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SummaryTimePeriod.allCases, id: \.self) { period in
                            let sel = (viewModel.summaryPeriod == period)
                            Button {
                                viewModel.selectSummaryPeriod(period)
                            } label: {
                                Text(zh ? period.zhLabel : period.enLabel)
                                    .font(SumFont.body(13, weight: sel ? .bold : .regular))
                                    .foregroundStyle(sel ? palette.ink : palette.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(sel ? palette.accent : palette.surface))
                            }
                            .buttonStyle(SpringPressStyle())
                        }
                    }
                }

                // Date anchor navigator
                HStack {
                    if viewModel.summaryPeriod != .custom {
                        Button { viewModel.shiftSummaryAnchor(direction: -1) } label: {
                            Image(systemName: "chevron.left").padding(8)
                        }
                        .pickbankLiquidGlass(in: Circle())
                    }
                    Spacer()
                    Text(report.rangeLabel)
                        .font(SumFont.mono(15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if viewModel.summaryPeriod != .custom {
                        Button { viewModel.shiftSummaryAnchor(direction: 1) } label: {
                            Image(systemName: "chevron.right").padding(8)
                        }
                        .pickbankLiquidGlass(in: Circle())
                    }
                }

                if viewModel.summaryPeriod == .custom {
                    HStack {
                        DatePicker("起", selection: $viewModel.summaryCustomStart, displayedComponents: .date)
                        DatePicker("止", selection: $viewModel.summaryCustomEnd, displayedComponents: .date)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(palette.surface))
                }

                // Total metrics card
                SumCard(highlightAccent: true) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(zh ? "期间总支出" : "Total Expense")
                                .font(SumFont.body(12))
                                .foregroundStyle(palette.textSecondary)
                            Text(MoneyFormatter.formatYuan(cents: report.totalExpenseCents))
                                .font(SumFont.display(26, hermes: palette.isHermes))
                                .foregroundStyle(palette.expense)
                                .numericRollTransition()
                            Text("环比上期 \(MoneyFormatter.formatYuan(cents: report.previousExpenseCents))")
                                .font(SumFont.mono(11))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(zh ? "期间总收入" : "Total Income")
                                .font(SumFont.body(12))
                                .foregroundStyle(palette.textSecondary)
                            Text(MoneyFormatter.formatYuan(cents: report.totalIncomeCents))
                                .font(SumFont.display(26, hermes: palette.isHermes))
                                .foregroundStyle(palette.income)
                                .numericRollTransition()
                            let net = report.totalIncomeCents - report.totalExpenseCents
                            Text("结余 \(MoneyFormatter.formatYuan(cents: net))")
                                .font(SumFont.mono(11))
                                .foregroundStyle(net >= 0 ? palette.income : palette.expense)
                        }
                    }
                    .padding(18)
                }

                // Expense / Income Toggle
                Picker("", selection: $viewModel.summaryTypeTab) {
                    Text(zh ? "支出分布" : "Expense").tag(TransactionType.expense)
                    Text(zh ? "收入分布" : "Income").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)

                // Adaptive Bento Charts
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        barChartCard(report: report, zh: zh).frame(maxWidth: .infinity)
                        donutChartCard(shares: activeShares, zh: zh).frame(maxWidth: .infinity)
                    }
                } else {
                    barChartCard(report: report, zh: zh)
                    donutChartCard(shares: activeShares, zh: zh)
                }
            }
            .padding(18)
        }
        .sheet(item: $viewModel.selectedSummaryDayBucket) { bucket in
            NavigationStack {
                let dayTxs = report.periodTransactions.filter { $0.createdAt >= bucket.startMs && $0.createdAt < bucket.endMs }
                List(dayTxs) { tx in
                    TransactionRowView(tx: tx, categoriesById: viewModel.categoriesById, walletsById: viewModel.walletsById)
                }
                .navigationTitle("\(bucket.label) 明细 (\(dayTxs.count))")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") { viewModel.selectedSummaryDayBucket = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func barChartCard(report: SummaryReport, zh: Bool) -> some View {
        SumCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(zh ? "趋势柱状分布（点击柱条查看当期明细）" : "Trend Breakdown")
                    .font(SumFont.mono(11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)

                Chart(report.buckets) { pt in
                    let val = Double(viewModel.summaryTypeTab == .income ? pt.incomeCents : pt.expenseCents) / 100.0
                    BarMark(
                        x: .value("Period", pt.label),
                        y: .value("Yuan", val)
                    )
                    .foregroundStyle(viewModel.summaryTypeTab == .income ? palette.income : palette.accent)
                    .cornerRadius(4)
                }
                .frame(height: 170)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(report.buckets.filter { ($0.expenseCents + $0.incomeCents) > 0 }) { b in
                            Button {
                                viewModel.selectedSummaryDayBucket = b
                            } label: {
                                Text("\(b.label) ¥\(Int((b.expenseCents + b.incomeCents) / 100))")
                                    .font(SumFont.mono(10))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(palette.backgroundElevated))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func donutChartCard(shares: [CategoryShareItem], zh: Bool) -> some View {
        SumCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(zh ? "分类占比排行" : "Category Breakdown")
                    .font(SumFont.mono(11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)

                if shares.isEmpty {
                    Text(zh ? "本周期暂无记录" : "No data for this period")
                        .font(SumFont.body(14))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.vertical, 24)
                } else {
                    Chart(shares) { item in
                        SectorMark(
                            angle: .value("Amount", Double(item.amountCents)),
                            innerRadius: .ratio(0.60),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Category", item.name))
                        .cornerRadius(4)
                    }
                    .frame(height: 190)

                    VStack(spacing: 8) {
                        ForEach(shares) { item in
                            HStack {
                                Text(item.name)
                                    .font(SumFont.body(14, weight: .medium))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text(String(format: "%.1f%%", item.percentage * 100))
                                    .font(SumFont.mono(12))
                                    .foregroundStyle(palette.textSecondary)
                                Text(MoneyFormatter.formatYuan(cents: item.amountCents))
                                    .font(SumFont.mono(14, weight: .bold))
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 100, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
