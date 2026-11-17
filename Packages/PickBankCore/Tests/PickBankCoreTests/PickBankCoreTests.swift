import Foundation
import Testing
@testable import PickBankCore

@Suite("PickBankCore Comprehensive Suite")
struct PickBankCoreTests {
    private func makeTempStore() throws -> (PickBankStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickBankCoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = try PickBankStore(baseDirectory: dir)
        return (store, dir)
    }

    // MARK: - Money & Arithmetic Keypad

    @Test("Integer cents formatting and grouping")
    func moneyFormatting() {
        #expect(MoneyFormatter.formatYuan(cents: 3500) == "¥35.00")
        #expect(MoneyFormatter.formatYuan(cents: 1250050, includeSymbol: true, showFractionIfWhole: false) == "¥12,500.50")
        #expect(MoneyFormatter.formatYuan(cents: -4200, includeSymbol: true, showFractionIfWhole: false) == "-¥42")
        #expect(MoneyFormatter.formatPlainDecimal(cents: 809) == "8.09")
    }

    @Test("Arithmetic keypad evaluation handles operators, parentheses, and division by zero")
    func arithmeticKeypad() {
        #expect(MoneyFormatter.parseToCents("35 + 12.5 * 2") == 6000)
        #expect(MoneyFormatter.parseToCents("(100 - 25) / 2") == 3750)
        #expect(MoneyFormatter.parseToCents("¥1,234.56") == 123456)
        #expect(MoneyFormatter.parseToCents("10 / 0") == nil)
    }

    // MARK: - NLP Multi-Entry Parser

    @Test("NLP multi-entry parses Chinese numbers, relative dates, and wallet hints")
    func nlpMultiEntry() {
        let engine = NlpParseEngine()
        let refDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 0))!
        let parsed = engine.parseMany("微信早饭拿铁 28.5，昨天打车花了三十五元，今天发工资 12500", referenceDate: refDate)

        #expect(parsed.count == 3)
        #expect(parsed[0].amountCents == 2850)
        #expect(parsed[0].categoryName == "餐饮")
        #expect(parsed[0].walletName == "微信")
        #expect(parsed[0].type == .expense)

        #expect(parsed[1].amountCents == 3500)
        #expect(parsed[1].categoryName == "交通")
        #expect(parsed[1].type == .expense)
        #expect(parsed[1].createdAt < parsed[0].createdAt)

        #expect(parsed[2].amountCents == 1_250_000)
        #expect(parsed[2].categoryName == "工资")
        #expect(parsed[2].type == .income)
    }

    @Test("NLP matches custom categories and English inputs")
    func nlpCustomAndEnglish() {
        let custom = CategoryRecord(name: "宠物猫咪", icon: "pawprint.fill", type: .expense)
        let parsed = NlpParseEngine().parse("买宠物猫咪罐头 68", customCategories: [custom])
        #expect(parsed?.categoryName == "宠物猫咪")
        #expect(parsed?.amountCents == 6800)

        let eng = NlpParseEngine().parse("morning coffee 4.5 and uber 18")
        let engMany = NlpParseEngine().parseMany("morning coffee 4.5, uber 18")
        #expect(eng != nil)
        #expect(engMany.count == 2)
        #expect(engMany[0].categoryName == "餐饮")
        #expect(engMany[1].categoryName == "交通")
    }

    // MARK: - Ledger Store, Snapshots & Category Archiving

    @Test("Permanent category snapshot survives archive, restore, and delete forever")
    func permanentCategorySnapshotLifecycle() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let customCat = try await store.addCategory(name: "手冲咖啡", icon: "cup.and.saucer.fill", type: .expense)
        let inserted = try await store.insertTransaction(TransactionRecord(
            amountCents: 3800,
            type: .expense,
            categoryId: customCat.id,
            note: "耶加雪菲"
        ))
        #expect(inserted.categoryNameSnapshot == "手冲咖啡")

        try await store.archiveCategory(id: customCat.id)
        let activeAfterArchive = try await store.activeCategories(kind: .expense)
        #expect(!activeAfterArchive.contains(where: { $0.id == customCat.id }))

        try await store.restoreCategory(id: customCat.id)
        let activeAfterRestore = try await store.activeCategories(kind: .expense)
        #expect(activeAfterRestore.last?.id == customCat.id)

        try await store.deleteCategoryForever(id: customCat.id)
        let snapshot = try await store.loadSnapshot()
        let loadedTx = try #require(snapshot.transactions.first(where: { $0.id == inserted.id }))
        #expect(loadedTx.categoryId == nil)
        #expect(loadedTx.categoryNameSnapshot == "手冲咖啡")
        #expect(loadedTx.resolvedCategoryName(categoriesById: [:]) == "手冲咖啡")
    }

    @Test("Active category reordering maintains dense sort indices")
    func categoryReorder() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let active = try await store.activeCategories(kind: .expense)
        #expect(active.count >= 3)
        let reversedIds = Array(active.map(\.id).reversed())
        try await store.reorderActiveCategories(kind: .expense, orderedIds: reversedIds)
        let reloaded = try await store.activeCategories(kind: .expense)
        #expect(reloaded.map(\.id) == reversedIds)
        #expect(reloaded.map(\.sortOrder) == Array(0..<reloaded.count))
    }

    // MARK: - Summary & Recurring

    @Test("Summary report aggregates shares, period deltas, and 7-day sparkline")
    func summaryAnalytics() {
        let cal = Calendar.current
        let anchor = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12))!
        let yesterday = cal.date(byAdding: .day, value: -1, to: anchor)!
        let lastMonth = cal.date(byAdding: .month, value: -1, to: anchor)!

        let txs = [
            TransactionRecord(amountCents: 4500, type: .expense, categoryNameSnapshot: "餐饮", createdAt: PickBankClock.ms(from: anchor)),
            TransactionRecord(amountCents: 1500, type: .expense, categoryNameSnapshot: "交通", createdAt: PickBankClock.ms(from: yesterday)),
            TransactionRecord(amountCents: 800000, type: .income, categoryNameSnapshot: "工资", createdAt: PickBankClock.ms(from: anchor)),
            TransactionRecord(amountCents: 3000, type: .expense, categoryNameSnapshot: "餐饮", createdAt: PickBankClock.ms(from: lastMonth))
        ]

        let report = SummaryAnalyticsEngine.buildReport(transactions: txs, categoriesById: [:], period: .month, anchorDate: anchor)
        #expect(report.totalExpenseCents == 6000)
        #expect(report.totalIncomeCents == 800000)
        #expect(report.previousExpenseCents == 3000)
        #expect(report.expenseShares.first?.name == "餐饮")
        #expect(report.expenseShares.first?.amountCents == 4500)

        let spark = SummaryAnalyticsEngine.last7DaysExpenses(transactions: txs, asOf: anchor)
        #expect(spark.count == 7)
        #expect(spark[6] == 4500)
        #expect(spark[5] == 1500)
    }

    @Test("Recurring engine posts due cycles idempotently")
    func recurringProcessing() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let rule = RecurringRuleRecord(
            amountCents: 1800,
            type: .expense,
            categoryId: "cat-exp-housing",
            note: "每日咖啡订阅",
            period: .daily,
            nextRunAt: PickBankClock.ms(from: twoDaysAgo)
        )
        try await store.upsertRecurringRule(rule)
        let generated = try await store.processDueRecurringRules(asOf: PickBankClock.ms(from: now))
        #expect(generated.count == 3)
        #expect(generated.first?.categoryNameSnapshot == "住房")

        let secondPass = try await store.processDueRecurringRules(asOf: PickBankClock.ms(from: now))
        #expect(secondPass.isEmpty)
    }

    // MARK: - Pet Engine, Energy Settlement, Release & Slots

    @Test("Pet daily settlement, release guard, slot unlock, and monotonic lifecycle")
    func petLifecycleAndReleasePolicy() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cal = Calendar.current
        let adoptDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))!
        let nextDay = cal.date(byAdding: .day, value: 1, to: adoptDate)!

        var petState = try await store.loadPetState()
        petState.settings.isEnabled = true
        petState.settings.budgetMode = .daily
        petState.settings.budgetAmountCents = 10_000
        petState.settings.lastSettledDateKey = PickBankClock.dateKey(for: adoptDate)
        try await store.savePetState(petState)

        let cat = try await store.adoptPet(species: PetSpecies.cat.rawValue, name: "布丁", today: adoptDate)
        _ = try await store.insertTransaction(TransactionRecord(
            amountCents: 7000,
            type: .expense,
            categoryId: "cat-exp-food",
            createdAt: PickBankClock.ms(from: adoptDate)
        ))

        let settled = try await store.settleCompletedPetDays(today: nextDay)
        #expect(settled.wallet.availableEnergy == 30)
        #expect(settled.profiles.first?.satiety == 64)

        await #expect(throws: Error.self) {
            _ = try await store.adoptPet(species: PetSpecies.panda.rawValue, name: "圆圆", today: nextDay)
        }
        await #expect(throws: Error.self) {
            _ = try await store.releasePet(id: cat.id, today: nextDay)
        }

        var updated = try await store.loadPetState()
        updated.profiles[0].growth = 125
        updated.profiles[0].affection = 32
        try await store.savePetState(updated)

        let released = try await store.releasePet(id: cat.id, today: nextDay)
        #expect(released.petName == "布丁")

        let panda = try await store.adoptPet(species: PetSpecies.panda.rawValue, name: "竹子", today: nextDay)
        #expect(panda.species == PetSpecies.panda.rawValue)

        let timeline = PetLifecycleEngine.createTimeline(petId: "t1", species: PetSpecies.dog.rawValue, adoptionDate: adoptDate)
        var advanced = timeline
        advanced.lastEvaluatedDateKey = "2026-12-01"
        let snap = PetLifecycleEngine.evaluate(timeline: advanced, todayKey: "2026-10-05")
        #expect(snap.evaluatedDateKey == "2026-12-01")
        #expect(CircadianPhase.from(hour: 10).visualPeriod == .day)
        #expect(CircadianPhase.from(hour: 19).visualPeriod == .night)
    }

    // MARK: - Lossless, Encrypted, CSV, XLSX & Universal Import

    @Test("Lossless JSON, AES-GCM Encrypted, CSV, and native XLSX round-trips and merge dedup")
    func exportAndImportRoundTrips() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await DataGovernanceService.seedDemoLedger(store: store)
        let originalSnapshot = try await store.loadSnapshot()
        #expect(originalSnapshot.transactions.count == 11)

        // Lossless JSON v2
        let jsonData = try ArchiveCodec.encodeLosslessJSON(snapshot: originalSnapshot)
        let (decodedV2, validSha) = try ArchiveCodec.decodeLosslessJSON(jsonData)
        #expect(validSha)
        #expect(decodedV2.payload.transactions.count == 11)

        // Encrypted PBKDF2 + AES-GCM
        let encData = try ArchiveCodec.encodeEncryptedBackup(snapshot: originalSnapshot, password: "PickBankSecret#2026", iterations: 15_000)
        #expect(throws: Error.self) {
            _ = try ArchiveCodec.decodeEncryptedBackup(encData, password: "WrongPassword")
        }
        let (decEnc, validEncSha) = try ArchiveCodec.decodeEncryptedBackup(encData, password: "PickBankSecret#2026")
        #expect(validEncSha)
        #expect(decEnc.payload.transactions.count == 11)

        // CSV UTF-8 BOM
        let csvData = ArchiveCodec.exportCSV(snapshot: originalSnapshot, language: .zhHans)
        let csvPreview = try UniversalImporter.inspectAndPreview(data: csvData, fileName: "ledger.csv", existingSnapshot: originalSnapshot)
        #expect(csvPreview.detectedFormat == .genericCsv)
        #expect(csvPreview.incomingTransactions.count == 11)

        // Native OpenXML XLSX
        let xlsxData = try ArchiveCodec.exportXLSX(snapshot: originalSnapshot, language: .zhHans)
        let (store2, dir2) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir2) }
        let emptySnap = try await store2.loadSnapshot()
        let xlsxPreview = try UniversalImporter.inspectAndPreview(data: xlsxData, fileName: "pickbank.xlsx", existingSnapshot: emptySnap)
        #expect(xlsxPreview.detectedFormat == .pickbankXlsx)
        #expect(xlsxPreview.incomingTransactions.count == 11)

        let mergeRes = try await UniversalImporter.applyImport(report: xlsxPreview, mode: .smartMerge, store: store2)
        #expect(mergeRes.importedTransactions == 11)

        let snap2 = try await store2.loadSnapshot()
        let dupPreview = try UniversalImporter.inspectAndPreview(data: xlsxData, fileName: "pickbank.xlsx", existingSnapshot: snap2)
        #expect(dupPreview.duplicateCount == 11)
        let secondMerge = try await UniversalImporter.applyImport(report: dupPreview, mode: .smartMerge, store: store2)
        #expect(secondMerge.importedTransactions == 0)
        #expect(secondMerge.skippedDuplicates == 11)
    }

    @Test("Android migration JSON and WeChat Pay CSV parsing")
    func androidAndWeChatImports() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = try await store.loadSnapshot()

        let androidJson = """
        {
          "categories": [{"id": 1, "name": "夜市小吃", "type": 0, "sortOrder": 0}],
          "transactions": [{"id": 99, "amount": 2650, "type": 0, "categoryId": 1, "note": "章鱼烧", "createdAt": 1760000000000}]
        }
        """
        let androidPreview = try UniversalImporter.inspectAndPreview(
            data: Data(androidJson.utf8),
            fileName: "android_backup.json",
            existingSnapshot: existing
        )
        #expect(androidPreview.detectedFormat == .androidMigrationJson)
        #expect(androidPreview.incomingTransactions.first?.amountCents == 2650)
        #expect(androidPreview.incomingTransactions.first?.categoryNameSnapshot == "夜市小吃")

        let wechatCsv = """
        微信支付账单明细
        交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
        2026-11-16 12:30:00,商户消费,瑞幸咖啡,生椰拿铁,支出,¥19.90,零钱,支付成功,wx001,m001,/
        2026-11-16 18:00:00,二维码收款,朋友,AA聚餐,收入,¥85.00,零钱,已收钱,wx002,m002,/
        """
        let wxPreview = try UniversalImporter.inspectAndPreview(
            data: Data(wechatCsv.utf8),
            fileName: "微信支付账单.csv",
            existingSnapshot: existing
        )
        #expect(wxPreview.detectedFormat == .wechatPayCsv)
        #expect(wxPreview.incomingTransactions.count == 2)
        #expect(wxPreview.incomingTransactions[0].amountCents == 1990)
        #expect(wxPreview.incomingTransactions[1].type == .income)
    }

    // MARK: - Auto-Backup Retention, Snapshot Restore & Local Data Governance

    @Test("AutoBackupScheduler retention protects pinned snapshots and Governance handles duplicates & restore")
    func autoBackupAndGovernance() async throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let scheduler = AutoBackupScheduler(store: store)
        var schedule = try await store.loadBackupSchedule()
        schedule.maxRetainedAutoBackups = 2
        schedule.frequency = .every6Hours
        try await store.saveBackupSchedule(schedule)

        let manual = try await scheduler.createSnapshot(trigger: .manual, pin: true)
        _ = try await scheduler.createSnapshot(trigger: .auto)
        try await Task.sleep(for: .milliseconds(25))
        _ = try await scheduler.createSnapshot(trigger: .auto)
        try await Task.sleep(for: .milliseconds(25))
        _ = try await scheduler.createSnapshot(trigger: .auto)

        let list = try await scheduler.listSnapshots()
        let autoSnapshots = list.filter { $0.trigger == .auto }
        #expect(autoSnapshots.count == 2)
        #expect(list.contains(where: { $0.id == manual.id }))

        let tNow = PickBankClock.nowMs()
        _ = try await store.insertTransactions([
            TransactionRecord(amountCents: 3200, type: .expense, categoryId: "cat-exp-food", note: "拉面", createdAt: tNow),
            TransactionRecord(amountCents: 3200, type: .expense, categoryId: "cat-exp-food", note: "拉面", createdAt: tNow + 10_000)
        ])
        let dupGroups = try await DataGovernanceService.scanDuplicates(store: store)
        #expect(dupGroups.count == 1)
        let deleted = try await DataGovernanceService.removeDuplicateGroups(dupGroups, store: store, scheduler: scheduler)
        #expect(deleted == 1)

        let integrity = try await DataGovernanceService.verifyAndRepairIntegrity(store: store)
        #expect(integrity.totalTransactions == 1)

        let safetySnap = try #require(try await scheduler.listSnapshots().first(where: { $0.trigger == .preDestructive }))
        let restored = try await scheduler.restoreSnapshot(id: safetySnap.id)
        #expect(restored.importedTransactions == 2)

        let breakdown = try await DataGovernanceService.computeStorageBreakdown(store: store, scheduler: scheduler)
        #expect(breakdown.totalBytes > 0)
    }

    @Test("Keychain / InMemorySecretStore + Offline AI insight")
    func secretStoreAndOfflineAi() throws {
        let secrets = InMemorySecretStore()
        try secrets.saveSecret("sk-test-1234", account: "deepseek")
        #expect(secrets.loadSecret(account: "deepseek") == "sk-test-1234")
        secrets.deleteSecret(account: "deepseek")
        #expect(secrets.loadSecret(account: "deepseek") == nil)

        let report = SummaryAnalyticsEngine.buildReport(
            transactions: [
                TransactionRecord(amountCents: 5000, type: .expense, categoryNameSnapshot: "餐饮", note: "火锅")
            ],
            categoriesById: [:],
            period: .month,
            anchorDate: Date()
        )
        let insight = OpenAICompatibleClient.offlineInsight(for: report, question: "火锅")
        #expect(insight.contains("餐饮"))
        #expect(insight.contains("¥50.00"))
    }
}
