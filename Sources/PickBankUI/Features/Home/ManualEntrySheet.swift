import PickBankCore
import SwiftUI

public struct ManualEntrySheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var amountExpr: String = ""
    @State private var txType: TransactionType = .expense
    @State private var selectedCategoryId: String?
    @State private var selectedWalletId: String?
    @State private var selectedTagIds: Set<String> = []
    @State private var newTagInput: String = ""
    @State private var newCategoryInput: String = ""
    @State private var showAddCategoryField = false
    @State private var note: String = ""
    @State private var entryDate: Date = Date()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let zh = (viewModel.language == .zhHans)
        let activeCats = viewModel.snapshot.categories.filter {
            !$0.isArchived && (txType == .income ? $0.type == .income : $0.type == .expense)
        }
        let evaluatedCents = MoneyFormatter.parseToCents(amountExpr)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $txType) {
                        Text(zh ? "支出" : "Expense").tag(TransactionType.expense)
                        Text(zh ? "收入" : "Income").tag(TransactionType.income)
                        Text(zh ? "转账" : "Transfer").tag(TransactionType.transfer)
                    }
                    .pickerStyle(.segmented)

                    SumCard(highlightAccent: true) {
                        VStack(alignment: .trailing, spacing: 4) {
                            TextField("0.00 (支持如 35+12.5*2)", text: $amountExpr)
                                .font(SumFont.display(30, hermes: palette.isHermes))
                                .foregroundStyle(palette.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .pickbankNumbersAndPunctuationKeyboard()
                            if let cents = evaluatedCents {
                                Text("= \(MoneyFormatter.formatYuan(cents: cents))")
                                    .font(SumFont.mono(13, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .padding(16)
                    }

                    HStack {
                        Text(zh ? "选择分类" : "Category")
                            .font(SumFont.mono(11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Button(showAddCategoryField ? "收起" : "+ 新增分类") {
                            showAddCategoryField.toggle()
                        }
                        .font(SumFont.body(12, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    }

                    if showAddCategoryField {
                        HStack(spacing: 8) {
                            TextField("输入新分类名", text: $newCategoryInput)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(palette.surface))
                            Button("创建并选中") {
                                let name = newCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                let kind: CategoryKind = txType == .income ? .income : .expense
                                Task {
                                    if let created = try? await viewModel.store.addCategory(name: name, icon: "star.fill", type: kind) {
                                        selectedCategoryId = created.id
                                        newCategoryInput = ""
                                        showAddCategoryField = false
                                        await viewModel.reloadAll()
                                    }
                                }
                            }
                            .pickbankGlassButton(prominent: true, tint: palette.accent)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                        ForEach(activeCats) { cat in
                            let selected = (selectedCategoryId == cat.id)
                            Button {
                                Haptics.light()
                                selectedCategoryId = cat.id
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 18))
                                    Text(cat.name)
                                        .font(SumFont.body(12, weight: selected ? .semibold : .regular))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(selected ? palette.ink : palette.textPrimary)
                                .background {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selected ? palette.accent : palette.surface)
                                }
                            }
                            .buttonStyle(SpringPressStyle())
                        }
                    }

                    // Wallets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.snapshot.wallets) { w in
                                let sel = (selectedWalletId == w.id)
                                Button {
                                    selectedWalletId = w.id
                                } label: {
                                    Label(w.name, systemImage: w.icon)
                                        .font(SumFont.body(12))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(sel ? palette.ink : palette.textSecondary)
                                        .background(Capsule().fill(sel ? palette.accent : palette.surface))
                                }
                            }
                        }
                    }

                    // #Tags multi-select + inline add
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("#标签")
                                .font(SumFont.mono(11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            TextField("输入新标签后点添加", text: $newTagInput)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(palette.surface))
                                .font(SumFont.body(12))
                            Button("加标签") {
                                let name = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                Task {
                                    if let ids = try? await viewModel.store.ensureTags(names: [name]) {
                                        selectedTagIds.formUnion(ids)
                                        newTagInput = ""
                                        await viewModel.reloadAll()
                                    }
                                }
                            }
                            .font(SumFont.body(12, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        }
                        if !viewModel.snapshot.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(viewModel.snapshot.tags) { tag in
                                        let on = selectedTagIds.contains(tag.id)
                                        Button {
                                            if on { selectedTagIds.remove(tag.id) } else { selectedTagIds.insert(tag.id) }
                                        } label: {
                                            Text("#\(tag.name)")
                                                .font(SumFont.mono(11, weight: on ? .bold : .regular))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .foregroundStyle(on ? palette.ink : palette.textSecondary)
                                                .background(Capsule().fill(on ? palette.accent : palette.surface))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    TextField(zh ? "备注（可选）" : "Note (optional)", text: $note)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
                        .foregroundStyle(palette.textPrimary)

                    DatePicker(zh ? "记账时间" : "Date", selection: $entryDate)
                        .tint(palette.accent)

                    ArithmeticPadGrid(expression: $amountExpr)
                }
                .padding(18)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(viewModel.editingTransaction == nil ? (zh ? "记一笔" : "New Record") : (zh ? "编辑记录" : "Edit Record"))
            .pickbankInlineNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "保存" : "Save") {
                        guard let cents = evaluatedCents, cents > 0 else { return }
                        let fallbackCat = selectedCategoryId ?? activeCats.first?.id
                        Task {
                            await viewModel.saveManualTransaction(
                                existingId: viewModel.editingTransaction?.id,
                                amountCents: cents,
                                type: txType,
                                categoryId: fallbackCat,
                                walletId: selectedWalletId,
                                note: note,
                                tagIds: Array(selectedTagIds),
                                date: entryDate
                            )
                            dismiss()
                        }
                    }
                    .disabled((evaluatedCents ?? 0) <= 0)
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                if let edit = viewModel.editingTransaction {
                    amountExpr = MoneyFormatter.formatPlainDecimal(cents: edit.amountCents)
                    txType = edit.type
                    selectedCategoryId = edit.categoryId
                    selectedWalletId = edit.walletId
                    selectedTagIds = Set(edit.tagIds)
                    note = edit.note ?? ""
                    entryDate = PickBankClock.date(fromMs: edit.createdAt)
                } else {
                    selectedCategoryId = activeCats.first?.id
                    selectedWalletId = viewModel.selectedWalletFilterId ?? viewModel.snapshot.wallets.first(where: \.isDefault)?.id
                }
            }
        }
    }
}

private struct ArithmeticPadGrid: View {
    @Environment(\.sumPalette) private var palette
    @Binding var expression: String

    private let rows: [[String]] = [
        ["7", "8", "9", "+"],
        ["4", "5", "6", "-"],
        ["1", "2", "3", "*"],
        [".", "0", "⌫", "/"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            Haptics.light()
                            if key == "⌫" {
                                if !expression.isEmpty { expression.removeLast() }
                            } else {
                                expression.append(key)
                            }
                        } label: {
                            Text(key)
                                .font(SumFont.mono(18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .foregroundStyle(["+", "-", "*", "/"].contains(key) ? palette.accent : palette.textPrimary)
                                .background(RoundedRectangle(cornerRadius: 12).fill(palette.surfaceElevated))
                        }
                        .buttonStyle(SpringPressStyle())
                    }
                }
            }
        }
    }
}

public struct BudgetSetupSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var period: BudgetPeriodType = .nextMonth
    @State private var customStart = Date()
    @State private var customEnd = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        NavigationStack {
            Form {
                Section("预算金额（元）") {
                    TextField("例如：4500", text: $amountText)
                        .pickbankDecimalKeyboard()
                        .font(SumFont.mono(22, weight: .bold))
                }
                Section("预算周期") {
                    Picker("周期", selection: $period) {
                        Text("未来一天").tag(BudgetPeriodType.nextDay)
                        Text("未来一周").tag(BudgetPeriodType.nextWeek)
                        Text("未来一月").tag(BudgetPeriodType.nextMonth)
                        Text("自定义区间").tag(BudgetPeriodType.custom)
                    }
                    if period == .custom {
                        DatePicker("开始", selection: $customStart, displayedComponents: .date)
                        DatePicker("结束", selection: $customEnd, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("预算设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let cents = MoneyFormatter.parseToCents(amountText), cents > 0 else { return }
                        Task {
                            await viewModel.saveBudget(amountCents: cents, period: period, customStart: customStart, customEnd: customEnd)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if let existing = viewModel.snapshot.budgets.first(where: { $0.categoryId == nil }) {
                    amountText = MoneyFormatter.formatPlainDecimal(cents: existing.amountCents)
                    period = existing.periodType
                }
            }
        }
    }
}

public struct RecurringRulesSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var type: TransactionType = .expense
    @State private var period: RecurringPeriod = .monthly
    @State private var categoryId: String?
    @State private var note = ""
    @State private var startDate = Date()

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        let activeCats = viewModel.snapshot.categories.filter { !$0.isArchived && ($0.type == (type == .income ? .income : .expense)) }
        NavigationStack {
            List {
                Section("新增固定账单") {
                    Picker("类型", selection: $type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }.pickerStyle(.segmented)
                    TextField("金额（元）", text: $amountText).pickbankDecimalKeyboard()
                    Picker("分类", selection: $categoryId) {
                        ForEach(activeCats) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                    }
                    Picker("周期", selection: $period) {
                        Text("每日").tag(RecurringPeriod.daily)
                        Text("每周").tag(RecurringPeriod.weekly)
                        Text("每月").tag(RecurringPeriod.monthly)
                        Text("每年").tag(RecurringPeriod.yearly)
                    }
                    TextField("备注（如房租/工资）", text: $note)
                    DatePicker("下次执行", selection: $startDate, displayedComponents: .date)
                    Button("添加固定账单") {
                        guard let cents = MoneyFormatter.parseToCents(amountText), cents > 0 else { return }
                        let rule = RecurringRuleRecord(
                            amountCents: cents,
                            type: type,
                            categoryId: categoryId ?? activeCats.first?.id,
                            note: note.isEmpty ? nil : note,
                            period: period,
                            nextRunAt: PickBankClock.ms(from: startDate)
                        )
                        Task {
                            try? await viewModel.store.upsertRecurringRule(rule)
                            await viewModel.reloadAll()
                            amountText = ""; note = ""
                        }
                    }
                }

                Section("已设规则（\(viewModel.snapshot.recurringRules.count)）") {
                    ForEach(viewModel.snapshot.recurringRules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.note ?? (viewModel.categoriesById[rule.categoryId ?? ""]?.name ?? "固定账单"))
                                    .fontWeight(.semibold)
                                Text("\(rule.period.rawValue) · \(MoneyFormatter.formatYuan(cents: rule.amountCents))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task {
                                    try? await viewModel.store.deleteRecurringRule(id: rule.id)
                                    await viewModel.reloadAll()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("周期固定账单")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onAppear { categoryId = activeCats.first?.id }
        }
    }
}
