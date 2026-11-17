import Charts
import PickBankCore
import SwiftUI
import UniformTypeIdentifiers

public struct DataSovereigntyCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.sumPalette) private var palette

    @State private var showImportPicker = false
    @State private var showFolderPicker = false
    @State private var showExportEncryptionPrompt = false
    @State private var exportPasswordInput = ""
    @State private var showResetConfirm = false
    @State private var scheduleDraft = BackupScheduleConfig()
    @State private var schedulePwdDraft = ""
    @State private var showBatchDeleteSheet = false

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                backupHealthAndQuickActionsCard
                storageBreakdownCard
                autoBackupConfigCard
                snapshotTimeMachineSection
                localDataGovernanceSection
            }
            .padding(18)
        }
        .onAppear {
            scheduleDraft = viewModel.backupConfig
            schedulePwdDraft = viewModel.backupPasswordDraft
        }
        .onChange(of: viewModel.backupConfig) { _, cfg in
            scheduleDraft = cfg
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json, .commaSeparatedText, .spreadsheet, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.handlePickedImportURL(url) }
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.setExternalBackupFolder(url: url) }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingImportReport != nil },
            set: { if !$0 { viewModel.pendingImportReport = nil } }
        )) {
            if let report = viewModel.pendingImportReport {
                ImportWizardPreviewSheet(viewModel: viewModel, report: report)
                    .environment(\.sumPalette, palette)
            }
        }
        .sheet(isPresented: $showBatchDeleteSheet) {
            BatchDeleteGovernanceSheet(viewModel: viewModel)
                .environment(\.sumPalette, palette)
        }
        .alert("输入密码以导出加密备份", isPresented: $showExportEncryptionPrompt) {
            SecureField("设置 AES-256-GCM 解密密码", text: $exportPasswordInput)
            Button("取消", role: .cancel) { exportPasswordInput = "" }
            Button("加密导出") {
                let pwd = exportPasswordInput
                exportPasswordInput = ""
                Task { await viewModel.prepareExport(kind: .encryptedJson, password: pwd) }
            }
        }
        .alert("需要输入加密备份密码", isPresented: $viewModel.importNeedsPasswordPrompt) {
            SecureField("备份密码", text: $viewModel.importPasswordInput)
            Button("取消", role: .cancel) { viewModel.importPasswordInput = "" }
            Button("解密并预览") {
                let pwd = viewModel.importPasswordInput
                Task { await viewModel.previewPendingImport(password: pwd) }
            }
        }
        .alert("确定重置本机账本数据？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("先留备份并重置", role: .destructive) {
                Task { await viewModel.performFactoryReset() }
            }
        } message: {
            Text("重置前系统会自动为你保留一份锁定快照在本地时光机与外部目录，之后随时可一键找回。")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DATA SOVEREIGNTY · ZERO CLOUD LOCK-IN")
                .font(SumFont.mono(11, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text("本地数据主权与自动备份")
                .font(SumFont.heading(24, hermes: palette.isHermes))
                .foregroundStyle(palette.textPrimary)
            Text("全量账单、分类归档与像素伙伴均保存在本机 SQLite 与「文件」App 可见备份目录中。")
                .font(SumFont.body(13))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var backupHealthAndQuickActionsCard: some View {
        SumCard(cornerRadius: 24, highlightAccent: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近本地快照")
                            .font(SumFont.mono(11))
                            .foregroundStyle(palette.textSecondary)
                        if let lastMs = viewModel.backupConfig.lastBackupAt {
                            Text(Self.formatDateTime(lastMs))
                                .font(SumFont.mono(15, weight: .bold))
                                .foregroundStyle(palette.income)
                        } else {
                            Text("尚未执行备份")
                                .font(SumFont.mono(15, weight: .bold))
                                .foregroundStyle(palette.transfer)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.createBackupNow(pin: true) }
                    } label: {
                        Label("立即快照", systemImage: "externaldrive.badge.plus")
                    }
                    .pickbankGlassButton(prominent: true, tint: palette.accent)
                }

                Divider().overlay(palette.divider)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                    Button { showImportPicker = true } label: {
                        Label("智能导入文件", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton(prominent: false)

                    Button { Task { await viewModel.prepareExport(kind: .losslessJson) } } label: {
                        Label("无损备份 (.pickbank)", systemImage: "doc.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton(prominent: false)

                    Button { showExportEncryptionPrompt = true } label: {
                        Label("AES 加密导出", systemImage: "lock.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton(prominent: false)

                    Button { Task { await viewModel.prepareExport(kind: .xlsx) } } label: {
                        Label("Excel (.xlsx)", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton(prominent: false)

                    Button { Task { await viewModel.prepareExport(kind: .csv) } } label: {
                        Label("表格 (.csv)", systemImage: "doc.plaintext")
                            .frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton(prominent: false)
                }
            }
            .padding(16)
        }
    }

    private var storageBreakdownCard: some View {
        let bd = viewModel.storageBreakdown
        let slices: [(String, Int64, Color)] = [
            ("SQLite 账本库", bd.ledgerDatabaseBytes, palette.accent),
            ("自动备份快照", bd.autoBackupsBytes, palette.income),
            ("锁定/安全快照", bd.manualAndSafetySnapshotsBytes, palette.transfer),
            ("自定义伙伴媒体", bd.customPetMediaBytes, palette.expense),
            ("临时导出缓存", bd.tempExportsBytes, palette.textTertiary)
        ]

        return SumCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本地占用空间分析")
                        .font(SumFont.body(15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: bd.totalBytes, countStyle: .file))
                        .font(SumFont.mono(13, weight: .bold))
                        .foregroundStyle(palette.accent)
                }

                ForEach(slices, id: \.0) { label, bytes, color in
                    HStack {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(label).font(SumFont.body(13)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(SumFont.mono(12))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            .padding(16)
        }
    }

    private var autoBackupConfigCard: some View {
        SumCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("自动定时本地备份设置")
                    .font(SumFont.body(16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                Picker("触发频率", selection: $scheduleDraft.frequency) {
                    ForEach(AutoBackupFrequency.allCases, id: \.self) { freq in
                        Text(freq.zhLabel).tag(freq)
                    }
                }
                .pickerStyle(.menu)
                .tint(palette.accent)

                if scheduleDraft.frequency == .daily {
                    Stepper("每日备份时段：\(String(format: "%02d:00", scheduleDraft.preferredHour))", value: $scheduleDraft.preferredHour, in: 0...23)
                        .font(SumFont.body(14))
                }

                Stepper("自动保留最近 \(scheduleDraft.maxRetainedAutoBackups) 份", value: $scheduleDraft.maxRetainedAutoBackups, in: 1...60)
                    .font(SumFont.body(14))

                Toggle("自动备份启用 AES-256-GCM 加密", isOn: $scheduleDraft.encryptAutoBackups)
                    .tint(palette.accent)

                if scheduleDraft.encryptAutoBackups {
                    SecureField("设置自动备份加密密码（存入钥匙串）", text: $schedulePwdDraft)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.backgroundElevated))
                }

                // External Security-Scoped Folder Bookmark for 7-day sideload reinstall resilience!
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("外部防丢同步目录（Files / iCloud Drive）")
                                .font(SumFont.body(13, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            Text(scheduleDraft.externalFolderDisplayName.map { "已绑定：\($0)" } ?? "未绑定（推荐绑定以防止 7 天免签重装丢失数据）")
                                .font(SumFont.body(11))
                                .foregroundStyle(scheduleDraft.externalFolderDisplayName != nil ? palette.income : palette.transfer)
                        }
                        Spacer()
                        Button(scheduleDraft.externalFolderDisplayName == nil ? "选择目录" : "更换") {
                            showFolderPicker = true
                        }
                        .pickbankGlassButton()
                    }
                }

                Button {
                    Task { await viewModel.saveBackupScheduleConfig(scheduleDraft, autoBackupPassword: schedulePwdDraft) }
                } label: {
                    Text("保存自动备份策略")
                        .frame(maxWidth: .infinity)
                }
                .pickbankGlassButton(prominent: true, tint: palette.accent)
            }
            .padding(16)
        }
    }

    private var snapshotTimeMachineSection: some View {
        SumCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本地备份时光机（\(viewModel.snapshotsList.count) 份）")
                        .font(SumFont.body(15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("支持文件 App 查看")
                        .font(SumFont.mono(10))
                        .foregroundStyle(palette.textTertiary)
                }

                if viewModel.snapshotsList.isEmpty {
                    Text("暂无本地快照，点击上方「立即快照」或开启自动备份。")
                        .font(SumFont.body(13))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(viewModel.snapshotsList) { meta in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(meta.trigger.rawValue)
                                    .font(SumFont.mono(10, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(palette.backgroundElevated))
                                    .foregroundStyle(meta.isPinned ? palette.accent : palette.textSecondary)
                                if meta.isEncrypted {
                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(palette.transfer)
                                }
                                Text(Self.formatDateTime(meta.createdAt))
                                    .font(SumFont.mono(12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: meta.byteSize, countStyle: .file))
                                    .font(SumFont.mono(11))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Text("\(meta.transactionCount) 笔账单 · \(meta.categoryCount) 分类 · \(meta.petCount) 伙伴 · SHA \(meta.sha256.prefix(8))")
                                .font(SumFont.mono(10))
                                .foregroundStyle(palette.textTertiary)
                            HStack(spacing: 12) {
                                Button(meta.isPinned ? "取消锁定" : "锁定防清理") {
                                    Task {
                                        _ = try? await viewModel.scheduler.togglePin(id: meta.id)
                                        await viewModel.reloadAll()
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(palette.accent)

                                Button("分享/导出") {
                                    Task {
                                        if let (_, _, url) = try? await viewModel.scheduler.readSnapshotBytes(id: meta.id) {
                                            viewModel.exportShareItem = ExportTransferItem(url: url, title: meta.fileName)
                                        }
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(palette.textPrimary)

                                Button("恢复到此快照") {
                                    Task {
                                        _ = try? await viewModel.scheduler.restoreSnapshot(id: meta.id, password: viewModel.backupPasswordDraft)
                                        Haptics.success()
                                        await viewModel.reloadAll()
                                        viewModel.showToast(message: "已从快照恢复（恢复前状态已保留安全快照）")
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(palette.income)

                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        try? await viewModel.scheduler.deleteSnapshot(id: meta.id)
                                        await viewModel.reloadAll()
                                    }
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .foregroundStyle(palette.expense)
                            }
                        }
                        .padding(.vertical, 6)
                        if meta.id != viewModel.snapshotsList.last?.id {
                            Divider().overlay(palette.divider)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var localDataGovernanceSection: some View {
        SumCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("本地数据治理与维护")
                    .font(SumFont.body(15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                    Button {
                        Task { await viewModel.runDuplicateScan() }
                    } label: {
                        Label("扫描重复账目", systemImage: "doc.on.doc.fill").frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton()

                    Button {
                        Task { await viewModel.runIntegrityCheck() }
                    } label: {
                        Label("一致性体检修复", systemImage: "checkmark.shield").frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton()

                    Button { showBatchDeleteSheet = true } label: {
                        Label("按条件批量清理", systemImage: "line.3.horizontal.decrease.circle").frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton()

                    Button {
                        Task {
                            let freed = (try? DataGovernanceService.purgeTemporaryExports(store: viewModel.store)) ?? 0
                            await viewModel.reloadAll()
                            viewModel.showToast(message: "已清理导出缓存 \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))")
                        }
                    } label: {
                        Label("清理导出缓存", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton()

                    Button {
                        Task { await viewModel.seedDemoData() }
                    } label: {
                        Label("注入演示账单", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton()

                    Button {
                        Task { await viewModel.clearDemoData() }
                    } label: {
                        Label("清空演示数据", systemImage: "eraser").frame(maxWidth: .infinity)
                    }
                    .pickbankGlassButton()
                }

                if !viewModel.duplicateGroups.isEmpty {
                    HStack {
                        Text("发现 \(viewModel.duplicateGroups.count) 组疑似重复账目")
                            .font(SumFont.body(13, weight: .semibold))
                            .foregroundStyle(palette.transfer)
                        Spacer()
                        Button("一键安全合并") {
                            Task { await viewModel.cleanAllDetectedDuplicates() }
                        }
                        .pickbankGlassButton(prominent: true, tint: palette.accent)
                    }
                    .padding(.top, 4)
                }

                if let integrity = viewModel.lastIntegrityReport {
                    Text("体检完成：总账目 \(integrity.totalTransactions) 笔，补全快照 \(integrity.repairedCategorySnapshots)，重连分类 \(integrity.relinkedCategoryIds)。")
                        .font(SumFont.mono(11))
                        .foregroundStyle(palette.income)
                }

                Divider().overlay(palette.divider)

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("重置本机账本（自动留存安全备份）", systemImage: "trash.slash")
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(palette.expense)
                .padding(.vertical, 6)
            }
            .padding(16)
        }
    }

    private static func formatDateTime(_ ms: Int64) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: PickBankClock.date(fromMs: ms))
    }
}

private struct ImportPreviewBox: Identifiable {
    let id = UUID()
    let report: ImportPreviewReport
}

private struct ImportWizardPreviewSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let report: ImportPreviewReport
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ImportExecutionMode = .smartMerge

    var body: some View {
        NavigationStack {
            Form {
                Section("文件自动识别与校验") {
                    LabeledContent("文件名", value: report.sourceName)
                    LabeledContent("识别格式", value: report.detectedFormat.rawValue)
                    LabeledContent("校验状态", value: report.checksumVerified ? "SHA-256 完整校验通过" : "无签名 / 外部格式")
                }
                Section("预演统计（尚未写入数据库）") {
                    LabeledContent("文件内账目数", value: "\(report.incomingTransactions.count) 笔")
                    LabeledContent("智能识别重复", value: "\(report.duplicateCount) 笔")
                    LabeledContent("预计净新增", value: "\(report.netNewCount) 笔")
                    LabeledContent("包含分类数", value: "\(report.incomingCategories.count) 个")
                }
                Section("导入合并策略") {
                    Picker("导入模式", selection: $mode) {
                        Text("智能合并去重（推荐）").tag(ImportExecutionMode.smartMerge)
                        Text("全量覆盖替换（先自动生成安全快照）").tag(ImportExecutionMode.cleanReplace)
                    }
                }
                if !report.warnings.isEmpty {
                    Section("提示") {
                        ForEach(report.warnings, id: \.self) { w in
                            Text(w).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("数据导入预演")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入") {
                        Task {
                            await viewModel.executePendingImport(mode: mode)
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct BatchDeleteGovernanceSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var filterType: Int = -1
    @State private var previewCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("清理条件范围") {
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    Picker("收支类型", selection: $filterType) {
                        Text("全部类型").tag(-1)
                        Text("仅支出").tag(0)
                        Text("仅收入").tag(1)
                    }
                }
                Section("预览结果") {
                    Text("符合条件的记录：\(previewCount) 笔（删除前将自动锁定安全快照）")
                }
            }
            .navigationTitle("按条件批量清理")
            .onAppear { updatePreview() }
            .onChange(of: startDate) { _, _ in updatePreview() }
            .onChange(of: endDate) { _, _ in updatePreview() }
            .onChange(of: filterType) { _, _ in updatePreview() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认清理", role: .destructive) {
                        let criteria = currentCriteria()
                        Task {
                            let deleted = (try? await DataGovernanceService.executeBatchDelete(criteria: criteria, store: viewModel.store, scheduler: viewModel.scheduler)) ?? 0
                            await viewModel.reloadAll()
                            viewModel.showToast(message: "已清理 \(deleted) 笔记录（已先存安全快照）")
                            dismiss()
                        }
                    }
                    .disabled(previewCount == 0)
                }
            }
        }
    }

    private func currentCriteria() -> BatchDeleteCriteria {
        let cal = Calendar.current
        let s = PickBankClock.ms(from: cal.startOfDay(for: min(startDate, endDate)))
        let e = PickBankClock.ms(from: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(startDate, endDate)))!)
        return BatchDeleteCriteria(startMs: s, endMs: e, type: TransactionType(rawValue: filterType))
    }

    private func updatePreview() {
        previewCount = DataGovernanceService.matchingTransactions(in: viewModel.snapshot, criteria: currentCriteria()).count
    }
}
