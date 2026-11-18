import PickBankCore
import SwiftUI

public struct DetailsStreamView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette

    @State private var preset: DetailsPreset = .thisMonth
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var keyword = ""
    @State private var typeFilter: TransactionType? = nil
    @State private var categoryNameFilter: String? = nil
    @State private var selectedTagIdFilter: String? = nil
    @State private var selectionMode = false
    @State private var selectedIds: Set<String> = []

    public enum DetailsPreset: String, CaseIterable, Identifiable {
        case today = "今天"
        case yesterday = "昨天"
        case thisWeek = "本周"
        case thisMonth = "本月"
        case lastMonth = "上月"
        case thisYear = "今年"
        case custom = "自定义"
        public var id: String { rawValue }
    }

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        let filtered = computeFilteredTransactions()
        let grouped = groupByDay(filtered)
        let expSum = filtered.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let incSum = filtered.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }
        let categoryChips = Array(Set(viewModel.snapshot.transactions.map {
            $0.resolvedCategoryName(categoriesById: viewModel.categoriesById)
        })).sorted()

        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(viewModel.language == .zhHans ? "账目明细流" : "Transaction Stream")
                        .font(SumFont.heading(24, hermes: palette.isHermes))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button(selectionMode ? "完成" : "多选") {
                        selectionMode.toggle()
                        if !selectionMode { selectedIds.removeAll() }
                    }
                    .pickbankGlassButton()
                }

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.textSecondary)
                    TextField("搜索分类名、#标签、备注或原文…", text: $keyword)
                        .foregroundStyle(palette.textPrimary)
                    if !keyword.isEmpty {
                        Button { keyword = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(palette.surface))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DetailsPreset.allCases) { p in
                            filterPill(title: p.rawValue, selected: preset == p) { preset = p }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill(title: "全部收支", selected: typeFilter == nil) { typeFilter = nil }
                        filterPill(title: "仅支出", selected: typeFilter == .expense) { typeFilter = .expense }
                        filterPill(title: "仅收入", selected: typeFilter == .income) { typeFilter = .income }
                        Divider().frame(height: 16)
                        filterPill(title: "全部分类", selected: categoryNameFilter == nil) { categoryNameFilter = nil }
                        ForEach(categoryChips, id: \.self) { name in
                            let isArchived = viewModel.snapshot.categories.first(where: { $0.name == name })?.isArchived ?? false
                            let label = isArchived ? "\(name)（已归档）" : name
                            filterPill(title: label, selected: categoryNameFilter == name) {
                                categoryNameFilter = (categoryNameFilter == name) ? nil : name
                            }
                        }
                        if !viewModel.snapshot.tags.isEmpty {
                            Divider().frame(height: 16)
                            ForEach(viewModel.snapshot.tags) { tag in
                                filterPill(title: "#\(tag.name)", selected: selectedTagIdFilter == tag.id) {
                                    selectedTagIdFilter = (selectedTagIdFilter == tag.id) ? nil : tag.id
                                }
                            }
                        }
                    }
                }

                if preset == .custom {
                    HStack {
                        DatePicker("起", selection: $customStart, displayedComponents: .date)
                        DatePicker("止", selection: $customEnd, displayedComponents: .date)
                    }
                    .font(.caption)
                }

                HStack {
                    Text("共 \(filtered.count) 笔 · 支出 \(MoneyFormatter.formatYuan(cents: expSum)) · 收入 \(MoneyFormatter.formatYuan(cents: incSum))")
                        .font(SumFont.mono(11))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    if selectionMode && !selectedIds.isEmpty {
                        Button("批量删除 (\(selectedIds.count))", role: .destructive) {
                            let ids = Array(selectedIds)
                            Task {
                                _ = try? await viewModel.scheduler.createSnapshot(trigger: .preDestructive, pin: true)
                                try? await viewModel.store.deleteTransactions(ids: ids)
                                selectedIds.removeAll()
                                selectionMode = false
                                await viewModel.reloadAll()
                                viewModel.showToast(message: "已批量删除 \(ids.count) 笔（删除前快照已保存）")
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(palette.expense)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            List {
                ForEach(grouped, id: \.dayLabel) { group in
                    Section {
                        ForEach(group.items) { tx in
                            HStack(spacing: 8) {
                                if selectionMode {
                                    Image(systemName: selectedIds.contains(tx.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIds.contains(tx.id) ? palette.accent : palette.textTertiary)
                                }
                                TransactionRowView(
                                    tx: tx,
                                    categoriesById: viewModel.categoriesById,
                                    walletsById: viewModel.walletsById,
                                    tagsById: viewModel.tagsById
                                )
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectionMode {
                                    if selectedIds.contains(tx.id) { selectedIds.remove(tx.id) } else { selectedIds.insert(tx.id) }
                                } else {
                                    viewModel.editingTransaction = tx
                                    viewModel.showManualSheet = true
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteTransaction(tx) }
                                } label: { Label("删除", systemImage: "trash") }
                                Button {
                                    Task { await viewModel.duplicateTransaction(tx) }
                                } label: { Label("复制", systemImage: "doc.on.doc") }
                                    .tint(.blue)
                            }
                            .listRowBackground(palette.surface.opacity(0.75))
                        }
                    } header: {
                        HStack {
                            Text(group.dayLabel).font(SumFont.mono(12, weight: .bold))
                            Spacer()
                            Text("支 \(MoneyFormatter.formatYuan(cents: group.expenseCents, showFractionIfWhole: false)) · 收 \(MoneyFormatter.formatYuan(cents: group.incomeCents, showFractionIfWhole: false))")
                                .font(SumFont.mono(11))
                        }
                        .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .pickbankInsetGroupedList()
            .scrollContentBackground(.hidden)
        }
    }

    private func filterPill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SumFont.body(12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.ink : palette.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? palette.accent : palette.surface))
        }
        .buttonStyle(SpringPressStyle())
    }

    private func computeFilteredTransactions() -> [TransactionRecord] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let bounds: (Date, Date) = {
            switch preset {
            case .today:
                return (startOfToday, cal.date(byAdding: .day, value: 1, to: startOfToday)!)
            case .yesterday:
                let y = cal.date(byAdding: .day, value: -1, to: startOfToday)!
                return (y, startOfToday)
            case .thisWeek:
                let b = SummaryAnalyticsEngine.rangeBounds(period: .week, anchorDate: now)
                return (b.start, b.end)
            case .thisMonth:
                let b = SummaryAnalyticsEngine.rangeBounds(period: .month, anchorDate: now)
                return (b.start, b.end)
            case .lastMonth:
                let lm = cal.date(byAdding: .month, value: -1, to: now)!
                let b = SummaryAnalyticsEngine.rangeBounds(period: .month, anchorDate: lm)
                return (b.start, b.end)
            case .thisYear:
                let b = SummaryAnalyticsEngine.rangeBounds(period: .year, anchorDate: now)
                return (b.start, b.end)
            case .custom:
                let s = cal.startOfDay(for: min(customStart, customEnd))
                let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(customStart, customEnd)))!
                return (s, e)
            }
        }()

        let sMs = PickBankClock.ms(from: bounds.0)
        let eMs = PickBankClock.ms(from: bounds.1)
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        return viewModel.filteredTransactions.filter { tx in
            guard tx.createdAt >= sMs && tx.createdAt < eMs else { return false }
            if let typeFilter, tx.type != typeFilter { return false }
            let resolvedCat = tx.resolvedCategoryName(categoriesById: viewModel.categoriesById)
            if let categoryNameFilter, resolvedCat != categoryNameFilter { return false }
            if let selectedTagIdFilter, !tx.tagIds.contains(selectedTagIdFilter) { return false }
            if !kw.isEmpty {
                let tagHit = tx.tagIds.compactMap { viewModel.tagsById[$0]?.name }
                    .contains { $0.localizedCaseInsensitiveContains(kw) }
                let hit = resolvedCat.localizedCaseInsensitiveContains(kw) ||
                    tagHit ||
                    (tx.note?.localizedCaseInsensitiveContains(kw) ?? false) ||
                    (tx.rawInput?.localizedCaseInsensitiveContains(kw) ?? false)
                if !hit { return false }
            }
            return true
        }
    }

    private struct DayBucket {
        let dayLabel: String
        let expenseCents: Int64
        let incomeCents: Int64
        let items: [TransactionRecord]
    }

    private func groupByDay(_ txs: [TransactionRecord]) -> [DayBucket] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd EEE"
        df.locale = Locale(identifier: "zh_CN")
        let grouped = Dictionary(grouping: txs) { tx in
            df.string(from: PickBankClock.date(fromMs: tx.createdAt))
        }
        return grouped.map { (key, list) in
            let sorted = list.sorted { $0.createdAt > $1.createdAt }
            let exp = sorted.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
            let inc = sorted.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }
            return DayBucket(dayLabel: key, expenseCents: exp, incomeCents: inc, items: sorted)
        }.sorted { ($0.items.first?.createdAt ?? 0) > ($1.items.first?.createdAt ?? 0) }
    }
}
