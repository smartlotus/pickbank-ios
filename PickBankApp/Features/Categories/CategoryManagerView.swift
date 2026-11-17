import PickBankCore
import SwiftUI

public struct CategoryManagerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette

    @State private var selectedKind: CategoryKind = .expense
    @State private var newName = ""
    @State private var newIcon = "star.fill"
    @State private var editingLimitCategory: CategoryRecord? = nil
    @State private var limitDraft = ""
    @State private var deleteForeverTarget: CategoryRecord? = nil

    private let iconChoices = [
        "fork.knife", "cup.and.saucer.fill", "car.fill", "tram.fill", "bag.fill",
        "house.fill", "gamecontroller.fill", "cross.case.fill", "book.fill",
        "pawprint.fill", "airplane", "gift.fill", "banknote.fill", "briefcase.fill",
        "chart.line.uptrend.xyaxis", "heart.fill", "star.fill", "sparkles"
    ]

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        let activeCats = viewModel.snapshot.categories
            .filter { !$0.isArchived && $0.type == selectedKind }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        let archivedCats = viewModel.snapshot.categories
            .filter { $0.isArchived && $0.type == selectedKind }
        let limitMap = Dictionary(uniqueKeysWithValues: viewModel.snapshot.categoryLimits.map { ($0.categoryId, $0.monthlyLimitCents) })

        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(viewModel.language == .zhHans ? "分类与限额管理" : "Categories & Limits")
                        .font(SumFont.heading(24, hermes: palette.isHermes))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    EditButton()
                        .foregroundStyle(palette.accent)
                }

                Picker("", selection: $selectedKind) {
                    Text("支出分类").tag(CategoryKind.expense)
                    Text("收入分类").tag(CategoryKind.income)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(iconChoices, id: \.self) { icon in
                            Button { newIcon = icon } label: {
                                Label(icon, systemImage: icon)
                            }
                        }
                    } label: {
                        Image(systemName: newIcon)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(palette.surfaceElevated))
                            .foregroundStyle(palette.accent)
                    }

                    TextField("新增自定义分类名称…", text: $newName)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
                        .foregroundStyle(palette.textPrimary)

                    Button("添加") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            _ = try? await viewModel.store.addCategory(name: name, icon: newIcon, type: selectedKind)
                            newName = ""
                            Haptics.success()
                            await viewModel.reloadAll()
                        }
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            List {
                Section("活跃分类（支持拖拽排序 · 归档不丢历史）") {
                    ForEach(activeCats) { cat in
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .foregroundStyle(palette.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.name)
                                    .font(SumFont.body(15, weight: .medium))
                                    .foregroundStyle(palette.textPrimary)
                                if let limitCents = limitMap[cat.id] {
                                    Text("月限额 \(MoneyFormatter.formatYuan(cents: limitCents, showFractionIfWhole: false))")
                                        .font(SumFont.mono(11))
                                        .foregroundStyle(palette.transfer)
                                }
                            }
                            Spacer()
                            if selectedKind == .expense {
                                Button("月限额") {
                                    limitDraft = limitMap[cat.id].map { MoneyFormatter.formatPlainDecimal(cents: $0) } ?? ""
                                    editingLimitCategory = cat
                                }
                                .font(.caption)
                                .foregroundStyle(palette.accent)
                            }
                            if !cat.isDefault {
                                Button("归档") {
                                    Task {
                                        try? await viewModel.store.archiveCategory(id: cat.id)
                                        Haptics.light()
                                        await viewModel.reloadAll()
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .listRowBackground(palette.surface.opacity(0.8))
                    }
                    .onMove { source, destination in
                        var reordered = activeCats
                        reordered.move(fromOffsets: source, toOffset: destination)
                        let ids = reordered.map(\.id)
                        Task {
                            try? await viewModel.store.reorderActiveCategories(kind: selectedKind, orderedIds: ids)
                            await viewModel.reloadAll()
                        }
                    }
                }

                if !archivedCats.isEmpty {
                    Section("已归档分类（历史账单与统计依然保留）") {
                        ForEach(archivedCats) { cat in
                            HStack {
                                Image(systemName: cat.icon).foregroundStyle(palette.textTertiary)
                                Text(cat.name).foregroundStyle(palette.textSecondary)
                                Spacer()
                                Button("恢复") {
                                    Task {
                                        try? await viewModel.store.restoreCategory(id: cat.id)
                                        await viewModel.reloadAll()
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(palette.income)

                                Button("彻底删除", role: .destructive) {
                                    deleteForeverTarget = cat
                                }
                                .font(.caption)
                                .foregroundStyle(palette.expense)
                            }
                            .listRowBackground(palette.surface.opacity(0.55))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .sheet(item: $editingLimitCategory) { cat in
            NavigationStack {
                Form {
                    Section("\(cat.name) · 每月消费警戒上限（元）") {
                        TextField("留空或 0 表示取消限额", text: $limitDraft)
                            .keyboardType(.decimalPad)
                    }
                }
                .navigationTitle("分类月限额")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { editingLimitCategory = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let cents = MoneyFormatter.parseToCents(limitDraft)
                            Task {
                                try? await viewModel.store.setCategoryMonthlyLimit(categoryId: cat.id, monthlyLimitCents: cents)
                                editingLimitCategory = nil
                                await viewModel.reloadAll()
                            }
                        }
                    }
                }
            }
        }
        .alert("彻底删除分类？", isPresented: Binding(get: { deleteForeverTarget != nil }, set: { if !$0 { deleteForeverTarget = nil } })) {
            Button("取消", role: .cancel) { deleteForeverTarget = nil }
            Button("彻底删除", role: .destructive) {
                if let target = deleteForeverTarget {
                    Task {
                        try? await viewModel.store.deleteCategoryForever(id: target.id)
                        deleteForeverTarget = nil
                        await viewModel.reloadAll()
                        viewModel.showToast(message: "已删除分类，历史账单保留「\(target.name)」名称快照")
                    }
                }
            }
        } message: {
            Text("彻底删除后该分类不可恢复，但所有历史账单仍会永久显示其写入时快照名称，统计数据不受损。")
        }
    }
}
