import Foundation
import PickBankCore
import SwiftUI
import UniformTypeIdentifiers

public enum RootDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case summary
    case details
    case ai
    case categories
    case pet
    case dataCenter

    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.home, .zhHans): return "记账"
        case (.home, .en): return "Records"
        case (.summary, .zhHans): return "总结"
        case (.summary, .en): return "Summary"
        case (.details, .zhHans): return "明细"
        case (.details, .en): return "Details"
        case (.ai, .zhHans): return "问账"
        case (.ai, .en): return "AI"
        case (.categories, .zhHans): return "分类"
        case (.categories, .en): return "Categories"
        case (.pet, .zhHans): return "伙伴"
        case (.pet, .en): return "Pets"
        case (.dataCenter, .zhHans): return "数据"
        case (.dataCenter, .en): return "Vault"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .home: return "sparkles.rectangle.stack.fill"
        case .summary: return "chart.pie.fill"
        case .details: return "list.bullet.rectangle.portrait.fill"
        case .ai: return "brain.head.profile"
        case .categories: return "square.grid.2x2.fill"
        case .pet: return "pawprint.fill"
        case .dataCenter: return "externaldrive.badge.checkmark"
        }
    }
}

public struct PetSlotManifestEntry: Decodable, Sendable {
    public let id: String
    public let canvas: [Int]
    public let anchor: [Double]
    public let size: Double
    public let frames: [String]
    public let sequence: [Int]
    public let frameDurationsMs: [Int]
    public let representative: Int
}

public struct PetSpeciesManifestEntry: Decodable, Sendable {
    public let authoredCanvas: [Int]
    public let dayRoom: String
    public let nightRoom: String
    public let slots: [PetSlotManifestEntry]
}

public struct PetAssetManifest: Decodable, Sendable {
    public let version: Int
    public let species: [String: PetSpeciesManifestEntry]
}

public struct UndoToastState: Identifiable, Equatable {
    public let id = UUID()
    public let message: String
    public let deletedTransaction: TransactionRecord?
}

public struct ExportTransferItem: Identifiable {
    public let id = UUID()
    public let url: URL
    public let title: String
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var snapshot = PickBankLedgerSnapshot()
    @Published public var backupConfig = BackupScheduleConfig()
    @Published public var snapshotsList: [BackupSnapshotMetadata] = []
    @Published public var storageBreakdown = LocalStorageBreakdown(
        ledgerDatabaseBytes: 0,
        autoBackupsBytes: 0,
        manualAndSafetySnapshotsBytes: 0,
        customPetMediaBytes: 0,
        tempExportsBytes: 0
    )

    @Published public var selectedTab: RootDestination = .home
    @Published public var selectedWalletFilterId: String? = nil

    // Home NLP & Manual Entry
    @Published public var nlpInputText: String = ""
    @Published public var liveParsedPills: [ParsedLedgerEntry] = []
    @Published public var showManualSheet = false
    @Published public var editingTransaction: TransactionRecord? = nil
    @Published public var showBudgetSetup = false
    @Published public var showRecurringSetup = false
    @Published public var shouldFocusNlpBar = false

    // Summary State (v1.9.2 anchor reset contract)
    @Published public var summaryPeriod: SummaryTimePeriod = .month
    @Published public var summaryAnchorDate: Date = Date()
    @Published public var summaryCustomStart: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @Published public var summaryCustomEnd: Date = Date()
    @Published public var summaryTypeTab: TransactionType = .expense
    @Published public var selectedSummaryDayBucket: SummaryBucketPoint? = nil

    // AI State
    @Published public var aiApiKey: String = ""
    @Published public var aiAdvice: String = ""
    @Published public var aiQuestion: String = ""
    @Published public var aiQuestionAnswer: String = ""
    @Published public var isAiLoading = false
    @Published public var aiTestStatus: String? = nil

    // Pet State & Encounter
    @Published public var selectedPetId: String? = nil
    @Published public var petVisualOverride: HabitatVisualPeriod? = nil
    @Published public var activeEncounterPet: PetProfile? = nil
    @Published public var petHeartBurstToken = 0
    @Published public var petManifest: PetAssetManifest? = nil

    // Data Sovereignty & Export/Import
    @Published public var backupPasswordDraft: String = ""
    @Published public var pendingImportReport: ImportPreviewReport? = nil
    @Published public var pendingImportRawData: Data? = nil
    @Published public var pendingImportFileName: String = ""
    @Published public var importNeedsPasswordPrompt = false
    @Published public var importPasswordInput = ""
    @Published public var duplicateGroups: [DuplicateTransactionGroup] = []
    @Published public var lastIntegrityReport: IntegrityReport? = nil
    @Published public var exportShareItem: ExportTransferItem? = nil

    // Toast & Theme Transition
    @Published public var toast: UndoToastState? = nil
    @Published public var themeRevealTrigger = 0
    @Published public var isLoaded = false

    public let store: PickBankStore
    public let scheduler: AutoBackupScheduler
    private let secretStore: SecretStoring
    private let aiClient = OpenAICompatibleClient()
    private let nlpEngine = NlpParseEngine()

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let baseDir = docs.appendingPathComponent("PickBank", isDirectory: true)
        do {
            self.store = try PickBankStore(baseDirectory: baseDir)
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("PickBankFallback", isDirectory: true)
            self.store = try! PickBankStore(baseDirectory: fallback)
        }
        self.scheduler = AutoBackupScheduler(store: self.store)
        self.secretStore = KeychainHelper()
        self.petManifest = Self.loadPetManifest()
        Task { await bootstrap() }
    }

    public func bootstrap() async {
        do {
            _ = try await store.processDueRecurringRules()
            _ = try await store.settleCompletedPetDays()
            await reloadAll()
            self.aiApiKey = secretStore.loadSecret(account: "ai_api_key") ?? ""
            self.backupPasswordDraft = secretStore.loadSecret(account: "auto_backup_pwd") ?? ""
            self.isLoaded = true
            await triggerScheduledBackupIfDue(onBackground: false)
        } catch {
            showToast(message: "初始化失败：\(error.localizedDescription)")
        }
    }

    public func reloadAll() async {
        do {
            let snap = try await store.loadSnapshot()
            let cfg = try await store.loadBackupSchedule()
            let snaps = try await scheduler.listSnapshots()
            let breakdown = try await DataGovernanceService.computeStorageBreakdown(store: store, scheduler: scheduler)
            self.snapshot = snap
            self.backupConfig = cfg
            self.snapshotsList = snaps
            self.storageBreakdown = breakdown
            if self.selectedPetId == nil || !snap.petState.profiles.contains(where: { $0.id == self.selectedPetId }) {
                self.selectedPetId = activePets.first?.id ?? snap.petState.profiles.first?.id
            }
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    // MARK: - Derived Helpers

    public var palette: SumPalette {
        SumPalette.palette(for: snapshot.preferences.themeMode)
    }

    public var language: AppLanguage {
        snapshot.preferences.language
    }

    public var categoriesById: [String: CategoryRecord] {
        Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
    }

    public var walletsById: [String: WalletAccount] {
        Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0) })
    }

    public var filteredTransactions: [TransactionRecord] {
        guard let wid = selectedWalletFilterId else { return snapshot.transactions }
        return snapshot.transactions.filter { $0.walletId == wid }
    }

    public var currentMonthSummary: SummaryReport {
        SummaryAnalyticsEngine.buildReport(
            transactions: filteredTransactions,
            categoriesById: categoriesById,
            period: .month,
            anchorDate: Date()
        )
    }

    public var activeSummaryReport: SummaryReport {
        SummaryAnalyticsEngine.buildReport(
            transactions: filteredTransactions,
            categoriesById: categoriesById,
            period: summaryPeriod,
            anchorDate: summaryAnchorDate,
            customStart: summaryCustomStart,
            customEnd: summaryCustomEnd
        )
    }

    public var activeBudgetStatus: (budget: BudgetRecord, spentCents: Int64, remainingCents: Int64, progress: Double)? {
        guard let budget = snapshot.budgets.first(where: { $0.categoryId == nil }) else { return nil }
        let start = budget.startMs ?? currentMonthSummary.rangeStartMs
        let end = budget.endMs ?? currentMonthSummary.rangeEndMs
        let spent = filteredTransactions
            .filter { $0.type == .expense && $0.createdAt >= start && $0.createdAt < end }
            .reduce(Int64(0)) { $0 + $1.amountCents }
        let rem = budget.amountCents - spent
        let prog = budget.amountCents > 0 ? Double(spent) / Double(budget.amountCents) : 0
        return (budget, spent, rem, max(0, prog))
    }

    public var last7DaysSparkline: [Double] {
        SummaryAnalyticsEngine.last7DaysExpenses(transactions: filteredTransactions).map { Double($0) / 100.0 }
    }

    public var activePets: [PetProfile] {
        let released = Set(snapshot.petState.releasedRecords.map(\.petId))
        let tlMap = Dictionary(uniqueKeysWithValues: snapshot.petState.timelines.map { ($0.petId, $0) })
        let todayKey = PickBankClock.dateKey()
        return snapshot.petState.profiles.filter { pet in
            if released.contains(pet.id) { return false }
            if let tl = tlMap[pet.id], PetLifecycleEngine.evaluate(timeline: tl, todayKey: todayKey).vitalState == .deceased {
                return false
            }
            return true
        }
    }

    public var memorialPets: [PetProfile] {
        let activeIds = Set(activePets.map(\.id))
        return snapshot.petState.profiles.filter { !activeIds.contains($0.id) }
    }

    // MARK: - Theme & Language

    public func toggleTheme() async {
        var prefs = snapshot.preferences
        prefs.themeMode = (prefs.themeMode == .classic) ? .hermes : .classic
        themeRevealTrigger += 1
        try? await store.savePreferences(prefs)
        await reloadAll()
        Haptics.medium()
    }

    public func setLanguage(_ lang: AppLanguage) async {
        var prefs = snapshot.preferences
        prefs.language = lang
        try? await store.savePreferences(prefs)
        await reloadAll()
        Haptics.light()
    }

    // MARK: - Live NLP & Transactions

    public func updateNlpDraft(_ text: String) {
        nlpInputText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            liveParsedPills = []
        } else {
            liveParsedPills = nlpEngine.parseMany(trimmed, customCategories: snapshot.categories)
        }
    }

    public func submitNlpInput() async {
        let entries = nlpEngine.parseMany(nlpInputText, customCategories: snapshot.categories)
        guard !entries.isEmpty else {
            showToast(message: language == .zhHans ? "未识别到金额，例如：午饭 35，打车 18" : "No amount detected, e.g. Coffee 4.5")
            return
        }
        var toInsert: [TransactionRecord] = []
        for item in entries {
            let targetKind: CategoryKind = item.type == .income ? .income : .expense
            let matchedCat = snapshot.categories.first { !$0.isArchived && $0.type == targetKind && $0.name == item.categoryName }
                ?? snapshot.categories.first { !$0.isArchived && $0.type == targetKind && $0.name.contains("其他") }
            let matchedWallet = item.walletName.flatMap { wn in
                snapshot.wallets.first { $0.name == wn }?.id
            } ?? selectedWalletFilterId ?? snapshot.wallets.first(where: \.isDefault)?.id

            toInsert.append(TransactionRecord(
                amountCents: item.amountCents,
                type: item.type,
                categoryId: matchedCat?.id,
                categoryNameSnapshot: matchedCat?.name ?? item.categoryName,
                walletId: matchedWallet,
                note: item.note,
                rawInput: item.rawInput,
                createdAt: item.createdAt,
                updatedAt: PickBankClock.nowMs()
            ))
        }
        do {
            _ = try await store.insertTransactions(toInsert)
            nlpInputText = ""
            liveParsedPills = []
            Haptics.success()
            let total = toInsert.reduce(Int64(0)) { $0 + $1.amountCents }
            showToast(message: "已记录 \(toInsert.count) 笔 · \(MoneyFormatter.formatYuan(cents: total))")
            maybeTriggerPetEncounter(strength: toInsert.count > 1 ? 0.42 : 0.24)
            await reloadAll()
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func saveManualTransaction(
        existingId: String?,
        amountCents: Int64,
        type: TransactionType,
        categoryId: String?,
        walletId: String?,
        note: String?,
        date: Date
    ) async {
        let ms = PickBankClock.ms(from: date)
        let catName = categoryId.flatMap { categoriesById[$0]?.name } ?? "未分类"
        let record = TransactionRecord(
            id: existingId ?? UUID().uuidString,
            amountCents: amountCents,
            type: type,
            categoryId: categoryId,
            categoryNameSnapshot: catName,
            walletId: walletId ?? snapshot.wallets.first(where: \.isDefault)?.id,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? note : nil,
            rawInput: existingId == nil ? "手动录入" : nil,
            createdAt: ms,
            updatedAt: PickBankClock.nowMs()
        )
        do {
            _ = try await store.insertTransaction(record)
            Haptics.success()
            showManualSheet = false
            editingTransaction = nil
            await reloadAll()
            maybeTriggerPetEncounter(strength: 0.24)
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func deleteTransaction(_ tx: TransactionRecord) async {
        do {
            try await store.deleteTransaction(id: tx.id)
            Haptics.warning()
            await reloadAll()
            toast = UndoToastState(
                message: "已删除 \(tx.categoryNameSnapshot) \(MoneyFormatter.formatYuan(cents: tx.amountCents))",
                deletedTransaction: tx
            )
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func undoDelete(_ tx: TransactionRecord) async {
        _ = try? await store.insertTransaction(tx)
        toast = nil
        Haptics.success()
        await reloadAll()
    }

    public func duplicateTransaction(_ tx: TransactionRecord) async {
        var copy = tx
        copy.id = UUID().uuidString
        copy.createdAt = PickBankClock.nowMs()
        copy.updatedAt = copy.createdAt
        copy.rawInput = "复制记录"
        _ = try? await store.insertTransaction(copy)
        Haptics.light()
        showToast(message: "已复制一笔：\(tx.categoryNameSnapshot)")
        await reloadAll()
    }

    // MARK: - Summary Period Selection (v1.9.2 Contract: reset anchor on dimension tab switch!)

    public func selectSummaryPeriod(_ period: SummaryTimePeriod) {
        summaryPeriod = period
        summaryAnchorDate = Date()
        Haptics.light()
    }

    public func shiftSummaryAnchor(direction: Int) {
        summaryAnchorDate = SummaryAnalyticsEngine.shiftAnchor(summaryAnchorDate, period: summaryPeriod, direction: direction)
        Haptics.light()
    }

    // MARK: - Budgets, Recurring & Categories

    public func saveBudget(amountCents: Int64, period: BudgetPeriodType, customStart: Date?, customEnd: Date?) async {
        let now = Date()
        let cal = Calendar.current
        let start = customStart ?? cal.startOfDay(for: now)
        let end: Date
        switch period {
        case .nextDay, .daily:
            end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        case .nextWeek, .weekly:
            end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        case .nextMonth, .monthly:
            end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        default:
            end = max(start.addingTimeInterval(86_400), customEnd ?? start)
        }
        let sMs = PickBankClock.ms(from: start)
        let eMs = PickBankClock.ms(from: end)
        let budget = BudgetRecord(
            amountCents: amountCents,
            periodType: period,
            timeKey: "\(sMs)_\(eMs)",
            startMs: sMs,
            endMs: eMs
        )
        try? await store.upsertBudget(budget)
        showBudgetSetup = false
        Haptics.success()
        await reloadAll()
    }

    // MARK: - AI Assistant

    public func saveAiConfig(providerName: String, baseUrl: String, modelId: String, apiKey: String) async {
        var prefs = snapshot.preferences
        prefs.selectedAiProviderName = providerName
        prefs.customAiBaseUrl = baseUrl
        prefs.aiModelId = modelId
        try? await store.savePreferences(prefs)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            secretStore.deleteSecret(account: "ai_api_key")
        } else {
            try? secretStore.saveSecret(trimmedKey, account: "ai_api_key")
        }
        self.aiApiKey = trimmedKey
        await reloadAll()
        showToast(message: "AI 配置已保存至本地钥匙串")
    }

    public func runAiPeriodAdvice() async {
        let report = activeSummaryReport
        let trimmedKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            aiAdvice = OpenAICompatibleClient.offlineInsight(for: report)
            return
        }
        isAiLoading = true
        defer { isAiLoading = false }
        let preset = snapshot.preferences.promptPresets.first { $0.id == snapshot.preferences.selectedPromptPresetId }
            ?? AiPromptPreset.defaultPresets[0]
        let prompt = OpenAICompatibleClient.buildLedgerContextPrompt(report: report, question: nil)
        do {
            aiAdvice = try await aiClient.chat(
                baseUrl: snapshot.preferences.customAiBaseUrl,
                modelId: snapshot.preferences.aiModelId,
                apiKey: trimmedKey,
                systemPrompt: preset.prompt,
                userPrompt: prompt
            )
        } catch {
            aiAdvice = OpenAICompatibleClient.offlineInsight(for: report) + "\n\n（在线 AI 调用回退提示：\(error.localizedDescription)）"
        }
    }

    public func askAiQuestion() async {
        let q = aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let report = activeSummaryReport
        let trimmedKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            aiQuestionAnswer = OpenAICompatibleClient.offlineInsight(for: report, question: q)
            return
        }
        isAiLoading = true
        defer { isAiLoading = false }
        let prompt = OpenAICompatibleClient.buildLedgerContextPrompt(report: report, question: q)
        do {
            aiQuestionAnswer = try await aiClient.chat(
                baseUrl: snapshot.preferences.customAiBaseUrl,
                modelId: snapshot.preferences.aiModelId,
                apiKey: trimmedKey,
                systemPrompt: "你是 PickBank 的理性极简记账分析师，严格依据提供的真实账本数据回答，不编造数字。",
                userPrompt: prompt
            )
        } catch {
            aiQuestionAnswer = OpenAICompatibleClient.offlineInsight(for: report, question: q)
        }
    }

    public func testAiConnectivity() async {
        aiTestStatus = "正在测试连接..."
        do {
            let reply = try await aiClient.testConnection(
                baseUrl: snapshot.preferences.customAiBaseUrl,
                modelId: snapshot.preferences.aiModelId,
                apiKey: aiApiKey
            )
            aiTestStatus = "连接成功：\(reply)"
        } catch {
            aiTestStatus = error.localizedDescription
        }
    }

    // MARK: - Pet Actions & Encounter

    public func adoptBuiltInPet(species: PetSpecies, name: String) async {
        do {
            let created = try await store.adoptPet(species: species.rawValue, name: name)
            selectedPetId = created.id
            Haptics.success()
            showToast(message: "欢迎「\(created.name)」入住拾念家园！")
            await reloadAll()
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func feedSelectedPet(energy: Int) async {
        guard let pid = selectedPetId else { return }
        let accepted = (try? await store.feedPet(id: pid, requestedEnergy: energy)) ?? 0
        if accepted > 0 {
            Haptics.success()
            petHeartBurstToken += 1
            showToast(message: "已投喂 +\(accepted) 能量")
            await reloadAll()
        } else {
            showToast(message: "能量不足或伙伴已吃饱")
        }
    }

    public func interactSelectedPet() async {
        guard let pid = selectedPetId else { return }
        let gained = (try? await store.interactWithPet(id: pid)) ?? false
        petHeartBurstToken += 1
        Haptics.light()
        if gained {
            showToast(message: "好感 +1")
            await reloadAll()
        }
    }

    public func releaseSelectedPet() async {
        guard let pid = selectedPetId else { return }
        do {
            let record = try await store.releasePet(id: pid)
            Haptics.medium()
            showToast(message: "已为「\(record.petName)」封存纪念档案")
            await reloadAll()
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    private func maybeTriggerPetEncounter(strength: Double) {
        guard snapshot.petState.settings.isEnabled,
              snapshot.petState.settings.globalEncountersEnabled,
              let pet = activePets.first(where: { $0.builtInSpecies != nil && $0.satiety > 0 }) else { return }
        if strength >= 0.24 {
            activeEncounterPet = pet
        }
    }

    // MARK: - Data Sovereignty: Export, Import, Auto-Backup, External Folder & Governance

    public func prepareExport(kind: ExportFileKind, password: String? = nil) async {
        do {
            let nowStamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                .replacingOccurrences(of: "/", with: "-")
            let data: Data
            let fileName: String
            switch kind {
            case .losslessJson:
                data = try ArchiveCodec.encodeLosslessJSON(snapshot: snapshot)
                fileName = "PickBank_Archive_\(nowStamp).pickbank.json"
            case .encryptedJson:
                let pwd = (password ?? backupPasswordDraft).trimmingCharacters(in: .whitespacesAndNewlines)
                data = try ArchiveCodec.encodeEncryptedBackup(snapshot: snapshot, password: pwd)
                fileName = "PickBank_Encrypted_\(nowStamp).pickbank.enc.json"
            case .csv:
                data = ArchiveCodec.exportCSV(snapshot: snapshot, language: language)
                fileName = "PickBank_Ledger_\(nowStamp).csv"
            case .xlsx:
                data = try ArchiveCodec.exportXLSX(snapshot: snapshot, language: language)
                fileName = "PickBank_Workbook_\(nowStamp).xlsx"
            }
            let outURL = store.tempExportsDirectory.appendingPathComponent(fileName)
            try data.write(to: outURL, options: .atomic)
            exportShareItem = ExportTransferItem(url: outURL, title: fileName)
            Haptics.success()
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func handlePickedImportURL(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingImportRawData = data
            pendingImportFileName = url.lastPathComponent
            await previewPendingImport(password: nil)
        } catch {
            showToast(message: "读取导入文件失败：\(error.localizedDescription)")
        }
    }

    public func previewPendingImport(password: String?) async {
        guard let data = pendingImportRawData else { return }
        do {
            let report = try UniversalImporter.inspectAndPreview(
                data: data,
                fileName: pendingImportFileName,
                password: password,
                existingSnapshot: snapshot
            )
            importNeedsPasswordPrompt = false
            pendingImportReport = report
        } catch UniversalImportError.requiresPassword {
            importNeedsPasswordPrompt = true
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func executePendingImport(mode: ImportExecutionMode) async {
        guard let report = pendingImportReport else { return }
        do {
            let result = try await UniversalImporter.applyImport(
                report: report,
                mode: mode,
                store: store,
                backupScheduler: scheduler
            )
            pendingImportReport = nil
            pendingImportRawData = nil
            importPasswordInput = ""
            Haptics.success()
            showToast(message: "导入完成：新增 \(result.importedTransactions) 笔，跳过重复 \(result.skippedDuplicates) 笔")
            await reloadAll()
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func createBackupNow(pin: Bool = false) async {
        do {
            let pwd = backupConfig.encryptAutoBackups ? backupPasswordDraft : nil
            let writer = buildExternalFolderWriter()
            let meta = try await scheduler.createSnapshot(trigger: .manual, password: pwd, pin: pin, externalWriter: writer)
            Haptics.success()
            showToast(message: "本地快照已保存：\(meta.fileName)")
            await reloadAll()
        } catch {
            showToast(message: error.localizedDescription)
        }
    }

    public func triggerScheduledBackupIfDue(onBackground: Bool) async {
        let writer = buildExternalFolderWriter()
        let pwd = backupConfig.encryptAutoBackups ? backupPasswordDraft : nil
        if let meta = try? await scheduler.runScheduledCheckIfDue(
            forceOnDirtyBackground: onBackground,
            password: pwd,
            externalWriter: writer
        ) {
            await reloadAll()
            _ = meta
        }
    }

    public func setExternalBackupFolder(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            var cfg = backupConfig
            cfg.externalFolderDisplayName = url.lastPathComponent
            cfg.externalFolderBookmarkBase64 = bookmark.base64EncodedString()
            try await store.saveBackupSchedule(cfg)
            await reloadAll()
            Haptics.success()
            showToast(message: "已绑定外部同步目录：\(url.lastPathComponent)")
        } catch {
            showToast(message: "绑定目录失败：\(error.localizedDescription)")
        }
    }

    public func saveBackupScheduleConfig(_ cfg: BackupScheduleConfig, autoBackupPassword: String) async {
        let trimmed = autoBackupPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secretStore.deleteSecret(account: "auto_backup_pwd")
        } else {
            try? secretStore.saveSecret(trimmed, account: "auto_backup_pwd")
        }
        self.backupPasswordDraft = trimmed
        var updated = cfg
        if updated.encryptAutoBackups && trimmed.isEmpty {
            updated.encryptAutoBackups = false
        }
        try? await store.saveBackupSchedule(updated)
        try? await scheduler.enforceRetentionPolicy(maxAutoBackups: updated.maxRetainedAutoBackups)
        await reloadAll()
        Haptics.success()
        showToast(message: "自动备份策略已更新")
    }

    private func buildExternalFolderWriter() -> ExternalFolderWriter? {
        guard let b64 = backupConfig.externalFolderBookmarkBase64,
              let data = Data(base64Encoded: b64) else { return nil }
        return ExternalFolderWriter { fileName, bytes in
            var isStale = false
            guard let folderUrl = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
                return false
            }
            let accessed = folderUrl.startAccessingSecurityScopedResource()
            defer { if accessed { folderUrl.stopAccessingSecurityScopedResource() } }
            let target = folderUrl.appendingPathComponent(fileName)
            try bytes.write(to: target, options: .atomic)
            return true
        }
    }

    public func runDuplicateScan() async {
        duplicateGroups = (try? await DataGovernanceService.scanDuplicates(store: store)) ?? []
        if duplicateGroups.isEmpty {
            showToast(message: "扫描完毕，未发现疑似重复账目")
        }
    }

    public func cleanAllDetectedDuplicates() async {
        let count = (try? await DataGovernanceService.removeDuplicateGroups(duplicateGroups, store: store, scheduler: scheduler)) ?? 0
        duplicateGroups = []
        Haptics.success()
        showToast(message: "已安全清理 \(count) 笔重复记录（已先生成防误删快照）")
        await reloadAll()
    }

    public func runIntegrityCheck() async {
        lastIntegrityReport = try? await DataGovernanceService.verifyAndRepairIntegrity(store: store)
        Haptics.success()
        await reloadAll()
    }

    public func seedDemoData() async {
        let count = (try? await DataGovernanceService.seedDemoLedger(store: store)) ?? 0
        Haptics.success()
        showToast(message: "已注入 \(count) 笔演示账单与示例伙伴")
        await reloadAll()
    }

    public func clearDemoData() async {
        let deleted = (try? await DataGovernanceService.executeBatchDelete(criteria: BatchDeleteCriteria(onlyDemo: true), store: store, scheduler: scheduler)) ?? 0
        Haptics.success()
        showToast(message: "已清理 \(deleted) 笔演示数据")
        await reloadAll()
    }

    public func performFactoryReset() async {
        _ = try? await DataGovernanceService.factoryReset(store: store, scheduler: scheduler, createFinalBackup: true)
        Haptics.warning()
        showToast(message: "已重置账本（重置前快照已保留在时光机）")
        await reloadAll()
    }

    public func showToast(message: String) {
        toast = UndoToastState(message: message, deletedTransaction: nil)
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if self.toast?.message == message {
                self.toast = nil
            }
        }
    }

    private static func loadPetManifest() -> PetAssetManifest? {
        guard let url = Bundle.main.url(forResource: "pet_manifest", withExtension: "json", subdirectory: "PetAssets"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PetAssetManifest.self, from: data)
    }
}

public enum ExportFileKind: String, CaseIterable, Identifiable {
    case losslessJson
    case encryptedJson
    case xlsx
    case csv

    public var id: String { rawValue }
}
