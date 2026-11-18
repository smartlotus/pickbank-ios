import Charts
import PickBankCore
import SwiftUI

public struct SummaryStudioView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showDatePickerSheet = false
    @State private var showAiSettings = false

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    private var donutColors: [Color] {
        if palette.isHermes {
            return [
                palette.expense,
                palette.income,
                palette.transfer,
                Color(hex: 0x75D7FF),
                Color(hex: 0xD5A6FF),
                Color(hex: 0x69F2D0),
                Color(hex: 0xFFB0D8),
                Color(hex: 0xC9C9EE),
            ]
        }
        return [
            Color(hex: 0xFFAB91),
            Color(hex: 0xA5D6A7),
            Color(hex: 0xFFE082),
            Color(hex: 0x90CAF9),
            Color(hex: 0xCE93D8),
            Color(hex: 0x80CBC4),
            Color(hex: 0xF48FB1),
            Color(hex: 0xBCAAA4),
        ]
    }

    public var body: some View {
        let zh = (viewModel.language == .zhHans)
        let report = viewModel.activeSummaryReport
        let activeShares = viewModel.summaryTypeTab == .income ? report.incomeShares : report.expenseShares

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header: Paw enable-pet button + Theme toggle + AI/Language settings + Export menu
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(zh ? "SUMMARY STUDIO" : "ANALYTICS")
                            .font(SumFont.mono(11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(zh ? "收支总结看板" : "Summary Analytics")
                            .font(SumFont.heading(26, hermes: palette.isHermes))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()

                    if !viewModel.snapshot.petState.settings.isEnabled {
                        Button {
                            Task { await viewModel.setPetModuleEnabled(true) }
                        } label: {
                            Image(systemName: "pawprint.fill")
                                .foregroundStyle(palette.accent)
                                .frame(width: 34, height: 34)
                        }
                        .pickbankLiquidGlass(in: Circle())
                    }

                    Button {
                        Task { await viewModel.toggleTheme() }
                    } label: {
                        Image(systemName: palette.isHermes ? "moon.stars.fill" : "paintpalette.fill")
                            .foregroundStyle(palette.accent)
                            .frame(width: 34, height: 34)
                    }
                    .pickbankLiquidGlass(in: Circle())

                    Button {
                        showAiSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 34, height: 34)
                    }
                    .pickbankLiquidGlass(in: Circle())

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
                        Button(zh ? "切换语言：EN" : "Language: 中文") {
                            Task { await viewModel.setLanguage(zh ? .en : .zhHans) }
                        }
                    } label: {
                        Label(zh ? "导出" : "Export", systemImage: "square.and.arrow.up")
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }

                // Dimension selector (resets anchor date to today)
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

                // TimeRangeDashboard (< 当前区间 >)
                SumCard(cornerRadius: 16) {
                    HStack {
                        Button { viewModel.shiftSummaryAnchor(direction: -1) } label: {
                            Image(systemName: "chevron.left").padding(8)
                        }
                        .disabled(viewModel.summaryPeriod == .custom)
                        .foregroundStyle(viewModel.summaryPeriod == .custom ? palette.textTertiary : palette.accent)

                        Spacer()
                        Button {
                            if viewModel.summaryPeriod != .custom {
                                showDatePickerSheet = true
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(report.rangeLabel)
                                    .font(SumFont.mono(15, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(viewModel.summaryPeriod == .custom ? "自定义区间" : "点此跳转日期")
                                    .font(SumFont.body(10))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                        Spacer()

                        Button { viewModel.shiftSummaryAnchor(direction: 1) } label: {
                            Image(systemName: "chevron.right").padding(8)
                        }
                        .disabled(viewModel.summaryPeriod == .custom)
                        .foregroundStyle(viewModel.summaryPeriod == .custom ? palette.textTertiary : palette.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                if viewModel.summaryPeriod == .custom {
                    HStack {
                        DatePicker("起", selection: $viewModel.summaryCustomStart, displayedComponents: .date)
                        DatePicker("止", selection: $viewModel.summaryCustomEnd, displayedComponents: .date)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(palette.surface))
                }

                // Totals & Period Comparison Card (Android SummaryStatCard + PeriodComparisonCard)
                SumCard(cornerRadius: 22, highlightAccent: true) {
                    VStack(spacing: 14) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(zh ? "期间总支出" : "Total Expense")
                                    .font(SumFont.body(12))
                                    .foregroundStyle(palette.textSecondary)
                                Text(MoneyFormatter.formatYuan(cents: report.totalExpenseCents))
                                    .font(SumFont.display(26, hermes: palette.isHermes))
                                    .foregroundStyle(palette.expense)
                                    .numericRollTransition()
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
                            }
                        }

                        Divider().overlay(palette.divider)

                        HStack {
                            Text(periodComparisonText(title: "支出环比", current: report.totalExpenseCents, previous: report.previousExpenseCents))
                                .font(SumFont.mono(11, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text("上期支 \(MoneyFormatter.formatYuan(cents: report.previousExpenseCents, showFractionIfWhole: false))")
                                .font(SumFont.mono(11))
                                .foregroundStyle(palette.textTertiary)
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

                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        donutChartCard(shares: activeShares, zh: zh).frame(maxWidth: .infinity)
                        trendSectionCard(report: report, zh: zh).frame(maxWidth: .infinity)
                    }
                } else {
                    donutChartCard(shares: activeShares, zh: zh)
                    trendSectionCard(report: report, zh: zh)
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showDatePickerSheet) {
            NavigationStack {
                VStack {
                    DatePicker(
                        "选择锚点日期",
                        selection: $viewModel.summaryAnchorDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(palette.accent)
                    .padding()
                    Spacer()
                }
                .navigationTitle("选择查看日期")
                .pickbankInlineNavBar()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") { showDatePickerSheet = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAiSettings) {
            AiConfigSheetView(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .sheet(item: $viewModel.selectedSummaryDayBucket) { bucket in
            let dayTxs = report.periodTransactions.filter { $0.createdAt >= bucket.startMs && $0.createdAt < bucket.endMs }
            let dayExp = dayTxs.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
            let dayInc = dayTxs.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }

            NavigationStack {
                List {
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("支出").font(.caption).foregroundStyle(.secondary)
                                Text(MoneyFormatter.formatYuan(cents: dayExp)).font(.headline).foregroundStyle(palette.expense)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("收入").font(.caption).foregroundStyle(.secondary)
                                Text(MoneyFormatter.formatYuan(cents: dayInc)).font(.headline).foregroundStyle(palette.income)
                            }
                        }
                    }
                    Section("当日明细 (\(dayTxs.count))") {
                        ForEach(dayTxs) { tx in
                            TransactionRowView(
                                tx: tx,
                                categoriesById: viewModel.categoriesById,
                                walletsById: viewModel.walletsById,
                                tagsById: viewModel.tagsById
                            )
                        }
                    }
                }
                .navigationTitle("\(bucket.label) 明细")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") { viewModel.selectedSummaryDayBucket = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trendSectionCard(report: SummaryReport, zh: Bool) -> some View {
        SumCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.summaryPeriod == .month
                     ? (zh ? "月度热力日历（点击日期查看当期明细）" : "Monthly Calendar Heatmap")
                     : (zh ? "趋势柱状分布（点击柱条查看当期明细）" : "Trend Breakdown"))
                    .font(SumFont.mono(11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)

                if viewModel.summaryPeriod == .month {
                    MonthlyCalendarHeatmapView(
                        buckets: report.buckets,
                        rangeStartMs: report.rangeStartMs,
                        useIncome: viewModel.summaryTypeTab == .income
                    ) { bucket in
                        viewModel.selectedSummaryDayBucket = bucket
                    }
                } else {
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
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func donutChartCard(shares: [CategoryShareItem], zh: Bool) -> some View {
        let colors = donutColors
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
                    Chart(Array(shares.enumerated()), id: \.element.id) { idx, item in
                        SectorMark(
                            angle: .value("Amount", Double(item.amountCents)),
                            innerRadius: .ratio(0.60),
                            angularInset: 2
                        )
                        .foregroundStyle(colors[idx % colors.count])
                        .cornerRadius(4)
                    }
                    .frame(height: 190)

                    VStack(spacing: 8) {
                        ForEach(Array(shares.enumerated()), id: \.element.id) { idx, item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(colors[idx % colors.count])
                                    .frame(width: 9, height: 9)
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
                                    .frame(width: 96, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func periodComparisonText(title: String, current: Int64, previous: Int64) -> String {
        if previous <= 0 {
            return current <= 0 ? "\(title) 持平" : "\(title) 新增 \(MoneyFormatter.formatYuan(cents: current, showFractionIfWhole: false))"
        }
        let pct = Double(current - previous) / Double(previous) * 100.0
        let sign = pct >= 0 ? "+" : ""
        return String(format: "%@ %@%.1f%%", title, sign, pct)
    }
}

private struct MonthlyCalendarHeatmapView: View {
    @Environment(\.sumPalette) private var palette
    let buckets: [SummaryBucketPoint]
    let rangeStartMs: Int64
    let useIncome: Bool
    let onSelectDay: (SummaryBucketPoint) -> Void

    var body: some View {
        let cal = Calendar.current
        let startDate = PickBankClock.date(fromMs: rangeStartMs)
        let firstDayOffset = (cal.component(.weekday, from: startDate) + 5) % 7 // Monday = 0
        let maxVal = max(Int64(1), buckets.map { useIncome ? $0.incomeCents : $0.expenseCents }.max() ?? 1)
        let rows = (firstDayOffset + buckets.count + 6) / 7
        let activeColor = useIncome ? palette.income : palette.expense

        VStack(spacing: 5) {
            HStack {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { label in
                    Text(label)
                        .font(SumFont.mono(10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { c in
                        let idx = r * 7 + c - firstDayOffset
                        if idx >= 0 && idx < buckets.count {
                            let pt = buckets[idx]
                            let val = useIncome ? pt.incomeCents : pt.expenseCents
                            let intensity = Double(val) / Double(maxVal)
                            Button {
                                Haptics.light()
                                onSelectDay(pt)
                            } label: {
                                Text(pt.label)
                                    .font(SumFont.mono(11, weight: val > 0 ? .bold : .regular))
                                    .foregroundStyle(intensity > 0.55 ? palette.ink : palette.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(val > 0 ? activeColor.opacity(0.15 + intensity * 0.72) : palette.backgroundElevated.opacity(0.65))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(intensity > 0.5 ? palette.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                                            }
                                    }
                            }
                            .buttonStyle(SpringPressStyle())
                        } else {
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}
