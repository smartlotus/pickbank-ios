import Charts
import PickBankCore
import SwiftUI

public struct HomeConsoleView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var nlpFocused: Bool

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let zh = (viewModel.language == .zhHans)
        let monthSummary = viewModel.currentMonthSummary

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerRow(zh: zh)
                walletFilterStrip(zh: zh)

                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        budgetHeroCard(zh: zh, summary: monthSummary)
                            .frame(maxWidth: .infinity)
                        sparklineCard(zh: zh)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    budgetHeroCard(zh: zh, summary: monthSummary)
                    sparklineCard(zh: zh)
                }

                quickActionStrip(zh: zh)
                nlpCaptureCard(zh: zh)
                recentTransactionsSection(zh: zh)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .onChange(of: viewModel.shouldFocusNlpBar) { _, flag in
            if flag {
                nlpFocused = true
                viewModel.shouldFocusNlpBar = false
            }
        }
    }

    @ViewBuilder
    private func headerRow(zh: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(zh ? "PICKBANK · 拾念记账" : "PICKBANK · LEDGER")
                    .font(SumFont.mono(11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(zh ? "纯净局部财务控制台" : "Zero-Noise Ledger")
                    .font(SumFont.heading(26, hermes: palette.isHermes))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.toggleTheme() }
                } label: {
                    Image(systemName: palette.isHermes ? "moon.stars.fill" : "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 36, height: 36)
                }
                .pickbankLiquidGlass(in: Circle())

                Button {
                    viewModel.editingTransaction = nil
                    viewModel.showManualSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(palette.accent))
                }
                .buttonStyle(SpringPressStyle())
            }
        }
    }

    @ViewBuilder
    private func walletFilterStrip(zh: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                walletChip(id: nil, title: zh ? "全部账户" : "All Wallets", icon: "tray.full.fill")
                ForEach(viewModel.snapshot.wallets) { wallet in
                    walletChip(id: wallet.id, title: wallet.name, icon: wallet.icon)
                }
            }
        }
    }

    private func walletChip(id: String?, title: String, icon: String) -> some View {
        let selected = (viewModel.selectedWalletFilterId == id)
        return Button {
            Haptics.light()
            withAnimation(MotionTokens.springInteractive) {
                viewModel.selectedWalletFilterId = id
            }
        } label: {
            Label(title, systemImage: icon)
                .font(SumFont.body(12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.ink : palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(selected ? palette.accent : palette.surface.opacity(0.75))
                }
        }
        .buttonStyle(SpringPressStyle())
    }

    @ViewBuilder
    private func budgetHeroCard(zh: Bool, summary: SummaryReport) -> some View {
        let budgetStatus = viewModel.activeBudgetStatus
        SumCard(cornerRadius: 24, highlightAccent: true) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(zh ? "剩余可用预算" : "REMAINING BUDGET")
                        .font(SumFont.mono(11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)

                    if let status = budgetStatus {
                        Text(MoneyFormatter.formatYuan(cents: status.remainingCents, showFractionIfWhole: false))
                            .font(SumFont.display(34, hermes: palette.isHermes))
                            .foregroundStyle(status.remainingCents < 0 ? palette.expense : palette.textPrimary)
                            .numericRollTransition()
                    } else {
                        Button {
                            viewModel.showBudgetSetup = true
                        } label: {
                            Text(zh ? "点击设定预算" : "Set Budget")
                                .font(SumFont.heading(22, hermes: palette.isHermes))
                                .foregroundStyle(palette.accent)
                        }
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zh ? "本月支出" : "Spent")
                                .font(SumFont.body(11))
                                .foregroundStyle(palette.textSecondary)
                            Text(MoneyFormatter.formatYuan(cents: summary.totalExpenseCents))
                                .font(SumFont.mono(14, weight: .semibold))
                                .foregroundStyle(palette.expense)
                                .numericRollTransition()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zh ? "本月收入" : "Income")
                                .font(SumFont.body(11))
                                .foregroundStyle(palette.textSecondary)
                            Text(MoneyFormatter.formatYuan(cents: summary.totalIncomeCents))
                                .font(SumFont.mono(14, weight: .semibold))
                                .foregroundStyle(palette.income)
                                .numericRollTransition()
                        }
                    }
                }
                Spacer()
                BudgetRingGauge(
                    progress: budgetStatus?.progress ?? 0,
                    hasBudget: budgetStatus != nil
                )
                .frame(width: 86, height: 86)
                .onTapGesture { viewModel.showBudgetSetup = true }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func sparklineCard(zh: Bool) -> some View {
        let points = viewModel.last7DaysSparkline
        let labels = ["D-6", "D-5", "D-4", "D-3", "D-2", "昨天", "今天"]
        SumCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(zh ? "近 7 日支出走势" : "7-DAY EXPENSE TREND")
                        .font(SumFont.mono(11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    let sum7 = points.reduce(0, +)
                    Text(String(format: "¥%.0f", sum7))
                        .font(SumFont.mono(13, weight: .bold))
                        .foregroundStyle(palette.accent)
                }

                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { idx, val in
                        AreaMark(
                            x: .value("Day", labels[idx]),
                            y: .value("Amount", val)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Day", labels[idx]),
                            y: .value("Amount", val)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.4))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 68)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func quickActionStrip(zh: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    viewModel.showBudgetSetup = true
                } label: {
                    Label(zh ? "预算周期" : "Budget", systemImage: "gauge.with.needle")
                }
                .pickbankGlassButton()

                Button {
                    viewModel.showRecurringSetup = true
                } label: {
                    Label(zh ? "固定账单 (\(viewModel.snapshot.recurringRules.count))" : "Recurring", systemImage: "repeat")
                }
                .pickbankGlassButton()

                Button {
                    viewModel.selectedTab = .dataCenter
                } label: {
                    Label(zh ? "导入与备份" : "Import & Vault", systemImage: "externaldrive.badge.checkmark")
                }
                .pickbankGlassButton()

                if viewModel.snapshot.transactions.isEmpty {
                    Button {
                        Task { await viewModel.seedDemoData() }
                    } label: {
                        Label(zh ? "填充演示账单" : "Load Demo", systemImage: "wand.and.stars")
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func nlpCaptureCard(zh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.liveParsedPills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.liveParsedPills) { pill in
                            HStack(spacing: 6) {
                                Text(pill.categoryName)
                                    .font(SumFont.body(11, weight: .semibold))
                                if let w = pill.walletName {
                                    Text("· \(w)")
                                        .font(SumFont.body(10))
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Text(
                                    (pill.type == .income ? "+" : "-")
                                    + MoneyFormatter.formatYuan(cents: pill.amountCents, showFractionIfWhole: false)
                                )
                                .font(SumFont.mono(12, weight: .bold))
                                .foregroundStyle(pill.type == .income ? palette.income : palette.expense)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .pickbankLiquidGlass(in: Capsule(), tint: palette.surfaceElevated)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                Image(systemName: "waveform.and.magnifyingglass")
                    .foregroundStyle(palette.accent)
                    .padding(.leading, 6)

                TextField(
                    zh ? "一句话记多笔：午饭 35，打车 18，发工资 8000" : "Natural entry: Coffee 4.5, Taxi 18",
                    text: Binding(
                        get: { viewModel.nlpInputText },
                        set: { viewModel.updateNlpDraft($0) }
                    )
                )
                .focused($nlpFocused)
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.submitNlpInput() }
                }

                if !viewModel.nlpInputText.isEmpty {
                    Button {
                        Task { await viewModel.submitNlpInput() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(SpringPressStyle())
                } else {
                    Button {
                        viewModel.editingTransaction = nil
                        viewModel.showManualSheet = true
                    } label: {
                        Text(zh ? "键盘" : "Pad")
                            .font(SumFont.mono(12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(palette.surfaceElevated))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .pickbankLiquidGlass(in: Capsule(), tint: palette.surface)
        }
        .animation(MotionTokens.springInteractive, value: viewModel.liveParsedPills.count)
    }

    @ViewBuilder
    private func recentTransactionsSection(zh: Bool) -> some View {
        let recent = Array(viewModel.filteredTransactions.prefix(15))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(zh ? "最近记录" : "RECENT")
                    .font(SumFont.mono(12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button(zh ? "全部明细 →" : "All →") {
                    viewModel.selectedTab = .details
                }
                .font(SumFont.body(13, weight: .medium))
                .foregroundStyle(palette.accent)
            }

            if recent.isEmpty {
                SumCard {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(palette.textTertiary)
                        Text(zh ? "还没有账目记录。试试上方输入「拿铁 28，打车 15」，或点击「填充演示账单」。" : "No transactions yet.")
                            .font(SumFont.body(13))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }
            } else {
                SumCard {
                    LazyVStack(spacing: 0) {
                        ForEach(recent) { tx in
                            TransactionRowView(
                                tx: tx,
                                categoriesById: viewModel.categoriesById,
                                walletsById: viewModel.walletsById
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.editingTransaction = tx
                                viewModel.showManualSheet = true
                            }
                            .contextMenu {
                                Button(zh ? "编辑" : "Edit") {
                                    viewModel.editingTransaction = tx
                                    viewModel.showManualSheet = true
                                }
                                Button(zh ? "复制相似一笔" : "Duplicate") {
                                    Task { await viewModel.duplicateTransaction(tx) }
                                }
                                Button(zh ? "删除" : "Delete", role: .destructive) {
                                    Task { await viewModel.deleteTransaction(tx) }
                                }
                            }
                            if tx.id != recent.last?.id {
                                Divider().overlay(palette.divider)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

public struct BudgetRingGauge: View {
    @Environment(\.sumPalette) private var palette
    let progress: Double
    let hasBudget: Bool

    public var body: some View {
        let clamped = min(max(progress, 0), 1)
        let ringColor = progress > 1.0 ? palette.expense : (progress > 0.8 ? palette.transfer : palette.accent)
        ZStack {
            Circle()
                .stroke(palette.divider.opacity(0.6), lineWidth: 9)
            Circle()
                .trim(from: 0, to: hasBudget ? clamped : 0.08)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(MotionTokens.springBouncy, value: progress)
            VStack(spacing: 1) {
                Text(hasBudget ? "\(Int((progress * 100).rounded()))%" : "--")
                    .font(SumFont.mono(15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .numericRollTransition()
                Text("预算")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}

public struct TransactionRowView: View {
    @Environment(\.sumPalette) private var palette
    let tx: TransactionRecord
    let categoriesById: [String: CategoryRecord]
    let walletsById: [String: WalletAccount]

    public init(tx: TransactionRecord, categoriesById: [String: CategoryRecord], walletsById: [String: WalletAccount]) {
        self.tx = tx
        self.categoriesById = categoriesById
        self.walletsById = walletsById
    }

    public var body: some View {
        let cat = tx.categoryId.flatMap { categoriesById[$0] }
        let catName = tx.resolvedCategoryName(categoriesById: categoriesById)
        let archivedSuffix = (cat?.isArchived == true) ? "（已归档）" : ""
        let iconName = cat?.icon ?? "bookmark.fill"
        let walletName = tx.walletId.flatMap { walletsById[$0]?.name }

        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tx.type == .income ? palette.income : (tx.type == .transfer ? palette.transfer : palette.accent))
                .frame(width: 38, height: 38)
                .background(Circle().fill(palette.backgroundElevated))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(catName + archivedSuffix)
                        .font(SumFont.body(15, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    if let walletName {
                        Text(walletName)
                            .font(SumFont.mono(10))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.surfaceElevated))
                    }
                }
                if let note = tx.note, !note.isEmpty {
                    Text(note)
                        .font(SumFont.body(12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let sign = tx.type == .income ? "+" : (tx.type == .expense ? "-" : "")
                Text(sign + MoneyFormatter.formatYuan(cents: tx.amountCents))
                    .font(SumFont.mono(15, weight: .bold))
                    .foregroundStyle(tx.type == .income ? palette.income : (tx.type == .transfer ? palette.transfer : palette.textPrimary))
                Text(Self.shortDate(tx.createdAt))
                    .font(SumFont.mono(10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static func shortDate(_ ms: Int64) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df.string(from: PickBankClock.date(fromMs: ms))
    }
}
