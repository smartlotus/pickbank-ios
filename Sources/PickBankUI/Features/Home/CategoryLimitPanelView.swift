import PickBankCore
import SwiftUI

public struct CategoryLimitPanelView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette

    @State private var isManaging = false
    @State private var editingCategory: CategoryRecord? = nil
    @State private var draftAmount = ""

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let progresses = viewModel.categoryLimitProgresses
        let expenseCats = viewModel.snapshot.categories.filter { !$0.isArchived && $0.type == .expense }
        let totalLimit = progresses.reduce(Int64(0)) { $0 + $1.monthlyLimitCents }
        let totalUsed = progresses.reduce(Int64(0)) { $0 + $1.usedCents }
        let totalRatio = totalLimit > 0 ? min(1.0, Double(totalUsed) / Double(totalLimit)) : 0.0
        let firstUnset = expenseCats.first { cat in !progresses.contains(where: { $0.category.id == cat.id }) }

        SumCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("分类月度限额")
                            .font(SumFont.body(15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(progresses.isEmpty
                             ? "为餐饮、购物、交通等支出分类设置每月警戒上限"
                             : "本月已设定 \(progresses.count) 个分类限额")
                            .font(SumFont.body(11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Button(isManaging ? "收起" : "管理") {
                        withAnimation(MotionTokens.springInteractive) {
                            isManaging.toggle()
                        }
                    }
                    .font(SumFont.body(13, weight: .semibold))
                    .foregroundStyle(palette.accent)
                }

                if !progresses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(MoneyFormatter.formatYuan(cents: totalUsed)) / \(MoneyFormatter.formatYuan(cents: totalLimit))")
                            .font(SumFont.mono(16, weight: .bold))
                            .foregroundStyle(totalUsed > totalLimit ? palette.expense : palette.textPrimary)
                        ProgressView(value: totalRatio)
                            .tint(totalUsed > totalLimit ? palette.expense : palette.accent)
                    }
                }

                if isManaging {
                    Divider().overlay(palette.divider)
                    HStack {
                        Text("本月分类用量")
                            .font(SumFont.mono(11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        if let nextCat = firstUnset {
                            Button {
                                draftAmount = ""
                                editingCategory = nextCat
                            } label: {
                                Label("添加限额", systemImage: "plus")
                                    .font(SumFont.body(12, weight: .semibold))
                            }
                            .foregroundStyle(palette.accent)
                        }
                    }

                    if progresses.isEmpty {
                        Text("暂未设置分类限额")
                            .font(SumFont.body(12))
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(progresses) { item in
                                limitRow(item: item)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .sheet(item: $editingCategory) { cat in
            let currentCats = expenseCats
            NavigationStack {
                Form {
                    Picker("支出分类", selection: Binding(
                        get: { cat.id },
                        set: { newId in
                            if let found = currentCats.first(where: { $0.id == newId }) {
                                editingCategory = found
                            }
                        }
                    )) {
                        ForEach(currentCats) { c in
                            Text(c.name).tag(c.id)
                        }
                    }
                    TextField("每月限额（元）", text: $draftAmount)
                        .pickbankDecimalKeyboard()
                }
                .navigationTitle("\(cat.name)的月度限额")
                .pickbankInlineNavBar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editingCategory = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let cents = MoneyFormatter.parseToCents(draftAmount)
                            Task {
                                await viewModel.setCategoryMonthlyLimit(categoryId: cat.id, cents: cents)
                                editingCategory = nil
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func limitRow(item: CategoryLimitProgress) -> some View {
        let barColor = item.isExceeded ? palette.expense : (item.isNearLimit ? palette.transfer : palette.accent)
        let statusText: String = {
            if item.isExceeded {
                return "超出 \(MoneyFormatter.formatYuan(cents: item.exceededCents))"
            } else if item.isNearLimit {
                return "接近限额，还剩 \(MoneyFormatter.formatYuan(cents: item.remainingCents))"
            } else {
                return "还剩 \(MoneyFormatter.formatYuan(cents: item.remainingCents))"
            }
        }()

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.category.name)
                        .font(SumFont.body(13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(statusText)
                        .font(SumFont.body(11))
                        .foregroundStyle(item.isExceeded ? palette.expense : palette.textSecondary)
                }
                Spacer()
                Text("\(MoneyFormatter.formatYuan(cents: item.usedCents, showFractionIfWhole: false)) / \(MoneyFormatter.formatYuan(cents: item.monthlyLimitCents, showFractionIfWhole: false))")
                    .font(SumFont.mono(12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Button {
                    Task { await viewModel.setCategoryMonthlyLimit(categoryId: item.category.id, cents: nil) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            ProgressView(value: item.ratio)
                .tint(barColor)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.backgroundElevated.opacity(0.68)))
        .contentShape(Rectangle())
        .onTapGesture {
            draftAmount = MoneyFormatter.formatPlainDecimal(cents: item.monthlyLimitCents)
            editingCategory = item.category
        }
    }
}
