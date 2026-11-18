import Foundation

public struct BatchDeleteCriteria: Sendable {
    public var startMs: Int64?
    public var endMs: Int64?
    public var type: TransactionType?
    public var categoryId: String?
    public var onlyDemo: Bool

    public init(
        startMs: Int64? = nil,
        endMs: Int64? = nil,
        type: TransactionType? = nil,
        categoryId: String? = nil,
        onlyDemo: Bool = false
    ) {
        self.startMs = startMs
        self.endMs = endMs
        self.type = type
        self.categoryId = categoryId
        self.onlyDemo = onlyDemo
    }
}

public enum DataGovernanceService {
    public static func computeStorageBreakdown(
        store: PickBankStore,
        scheduler: AutoBackupScheduler
    ) async throws -> LocalStorageBreakdown {
        try await store.checkpointWAL()
        let fm = FileManager.default

        func fileSize(_ url: URL) -> Int64 {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(vals?.fileSize ?? 0)
        }

        func dirSize(_ dir: URL) -> Int64 {
            guard let enumr = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var sum: Int64 = 0
            for case let url as URL in enumr {
                sum += fileSize(url)
            }
            return sum
        }

        let dbBytes = fileSize(store.databaseURL)
            + fileSize(URL(fileURLWithPath: store.databaseURL.path + "-wal"))
            + fileSize(URL(fileURLWithPath: store.databaseURL.path + "-shm"))

        let snapshots = (try? await scheduler.listSnapshots()) ?? []
        let autoBytes = snapshots.filter { $0.trigger == .auto }.reduce(Int64(0)) { $0 + $1.byteSize }
        let manualBytes = snapshots.filter { $0.trigger != .auto }.reduce(Int64(0)) { $0 + $1.byteSize }
        let customPetBytes = dirSize(store.customPetsDirectory)
        let tempBytes = dirSize(store.tempExportsDirectory)

        return LocalStorageBreakdown(
            ledgerDatabaseBytes: dbBytes,
            autoBackupsBytes: autoBytes,
            manualAndSafetySnapshotsBytes: manualBytes,
            customPetMediaBytes: customPetBytes,
            tempExportsBytes: tempBytes
        )
    }

    public static func scanDuplicates(
        store: PickBankStore,
        windowMs: Int64 = 5 * 60 * 1000
    ) async throws -> [DuplicateTransactionGroup] {
        let snapshot = try await store.loadSnapshot()
        let txs = snapshot.transactions.sorted { $0.createdAt < $1.createdAt }
        var usedIds: Set<String> = []
        var groups: [DuplicateTransactionGroup] = []

        for i in txs.indices {
            let base = txs[i]
            if usedIds.contains(base.id) { continue }
            var dupes: [TransactionRecord] = []
            for j in (i + 1)..<txs.count {
                let candidate = txs[j]
                if candidate.createdAt - base.createdAt > windowMs { break }
                if candidate.type == base.type &&
                   candidate.amountCents == base.amountCents &&
                   candidate.categoryNameSnapshot == base.categoryNameSnapshot &&
                   (candidate.note ?? "") == (base.note ?? "") {
                    dupes.append(candidate)
                    usedIds.insert(candidate.id)
                }
            }
            if !dupes.isEmpty {
                usedIds.insert(base.id)
                groups.append(DuplicateTransactionGroup(primary: base, duplicates: dupes))
            }
        }
        return groups
    }

    @discardableResult
    public static func removeDuplicateGroups(
        _ groups: [DuplicateTransactionGroup],
        store: PickBankStore,
        scheduler: AutoBackupScheduler
    ) async throws -> Int {
        let idsToDelete = groups.flatMap { $0.duplicates.map(\.id) }
        guard !idsToDelete.isEmpty else { return 0 }
        _ = try? await scheduler.createSnapshot(trigger: .preDestructive, password: nil, pin: true)
        try await store.deleteTransactions(ids: idsToDelete)
        return idsToDelete.count
    }

    @discardableResult
    public static func verifyAndRepairIntegrity(store: PickBankStore) async throws -> IntegrityReport {
        var snapshot = try await store.loadSnapshot()
        let catById = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
        let catByTypeAndName = Dictionary(
            snapshot.categories.map { ("\($0.type.rawValue):\($0.name)", $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let validTagIds = Set(snapshot.tags.map(\.id))

        var repairedSnapshots = 0
        var relinkedIds = 0
        var orphanTags = 0

        for i in snapshot.transactions.indices {
            var tx = snapshot.transactions[i]
            if let cid = tx.categoryId, let cat = catById[cid] {
                if tx.categoryNameSnapshot != cat.name {
                    tx.categoryNameSnapshot = cat.name
                    repairedSnapshots += 1
                }
            } else if tx.categoryId == nil {
                let kindRaw = (tx.type == .income ? CategoryKind.income : CategoryKind.expense).rawValue
                if let matched = catByTypeAndName["\(kindRaw):\(tx.categoryNameSnapshot)"] {
                    tx.categoryId = matched.id
                    relinkedIds += 1
                } else if tx.categoryNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tx.categoryNameSnapshot = "未分类"
                    repairedSnapshots += 1
                }
            }
            let filteredTags = tx.tagIds.filter { validTagIds.contains($0) }
            if filteredTags.count != tx.tagIds.count {
                orphanTags += (tx.tagIds.count - filteredTags.count)
                tx.tagIds = filteredTags
            }
            snapshot.transactions[i] = tx
        }

        // Normalize active sort orders
        var fixedOrders = 0
        for kind in CategoryKind.allCases {
            let activeIndices = snapshot.categories.indices
                .filter { !snapshot.categories[$0].isArchived && snapshot.categories[$0].type == kind }
                .sorted { snapshot.categories[$0].sortOrder < snapshot.categories[$1].sortOrder }
            for (rank, idx) in activeIndices.enumerated() {
                if snapshot.categories[idx].sortOrder != rank {
                    snapshot.categories[idx].sortOrder = rank
                    fixedOrders += 1
                }
            }
        }

        if repairedSnapshots > 0 || relinkedIds > 0 || orphanTags > 0 || fixedOrders > 0 {
            try await store.replaceAll(with: snapshot)
        }

        return IntegrityReport(
            totalTransactions: snapshot.transactions.count,
            repairedCategorySnapshots: repairedSnapshots,
            relinkedCategoryIds: relinkedIds,
            cleanedOrphanTagRefs: orphanTags,
            fixedSortOrders: fixedOrders,
            timestamp: PickBankClock.nowMs()
        )
    }

    public static func matchingTransactions(
        in snapshot: PickBankLedgerSnapshot,
        criteria: BatchDeleteCriteria
    ) -> [TransactionRecord] {
        snapshot.transactions.filter { tx in
            if criteria.onlyDemo && !tx.isDemo { return false }
            if let start = criteria.startMs, tx.createdAt < start { return false }
            if let end = criteria.endMs, tx.createdAt > end { return false }
            if let type = criteria.type, tx.type != type { return false }
            if let cid = criteria.categoryId, tx.categoryId != cid { return false }
            return true
        }
    }

    @discardableResult
    public static func executeBatchDelete(
        criteria: BatchDeleteCriteria,
        store: PickBankStore,
        scheduler: AutoBackupScheduler
    ) async throws -> Int {
        let snapshot = try await store.loadSnapshot()
        let victims = matchingTransactions(in: snapshot, criteria: criteria)
        guard !victims.isEmpty else { return 0 }
        _ = try? await scheduler.createSnapshot(trigger: .preDestructive, password: nil, pin: true)
        try await store.deleteTransactions(ids: victims.map(\.id))
        return victims.count
    }

    public static func purgeTemporaryExports(store: PickBankStore) throws -> Int64 {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: store.tempExportsDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var freed: Int64 = 0
        for url in files {
            let sz = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            try? fm.removeItem(at: url)
            freed += sz
        }
        return freed
    }

    @discardableResult
    public static func seedDemoLedger(store: PickBankStore, now: Date = Date()) async throws -> Int {
        let calendar = Calendar.current
        let entries: [(dayOffset: Int, hour: Int, cents: Int64, type: TransactionType, catId: String, catName: String, walletId: String, note: String)] = [
            (0, 8, 2800, .expense, "cat-exp-food", "餐饮", "wallet-wechat", "手冲拿铁与可颂"),
            (0, 12, 4600, .expense, "cat-exp-food", "餐饮", "wallet-alipay", "工作日简餐"),
            (0, 18, 2400, .expense, "cat-exp-transport", "交通", "wallet-wechat", "晚高峰网约车"),
            (-1, 19, 16800, .expense, "cat-exp-food", "餐饮", "wallet-wechat", "双人寿喜锅晚餐"),
            (-1, 21, 5900, .expense, "cat-exp-shopping", "购物", "wallet-alipay", "补充咖啡豆与滤纸"),
            (-2, 10, 1250000, .income, "cat-inc-salary", "工资", "wallet-bank", "月度薪资入账"),
            (-2, 15, 7800, .expense, "cat-exp-edu", "教育", "wallet-alipay", "购买 Swift 设计书籍"),
            (-3, 14, 12900, .expense, "cat-exp-fun", "娱乐", "wallet-wechat", "周末 IMAX 电影双人票"),
            (-4, 9, 600, .expense, "cat-exp-transport", "交通", "wallet-wechat", "早高峰地铁"),
            (-5, 11, 32000, .expense, "cat-exp-housing", "住房", "wallet-bank", "宽带与水电物业分摊"),
            (-6, 16, 48000, .income, "cat-inc-side", "兼职", "wallet-alipay", "设计顾问津贴")
        ]

        var records: [TransactionRecord] = []
        for (idx, item) in entries.enumerated() {
            let day = calendar.date(byAdding: .day, value: item.dayOffset, to: calendar.startOfDay(for: now)) ?? now
            let dt = calendar.date(bySettingHour: item.hour, minute: (idx * 7) % 50, second: 0, of: day) ?? day
            let ms = PickBankClock.ms(from: dt)
            records.append(TransactionRecord(
                id: "demo-tx-\(idx)-\(ms)",
                amountCents: item.cents,
                type: item.type,
                categoryId: item.catId,
                categoryNameSnapshot: item.catName,
                walletId: item.walletId,
                note: item.note,
                rawInput: "演示数据",
                isDemo: true,
                createdAt: ms,
                updatedAt: ms
            ))
        }
        _ = try await store.insertTransactions(records)

        // Ensure a sensible monthly budget exists if none set yet
        let snapshot = try await store.loadSnapshot()
        if snapshot.budgets.isEmpty {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
            try await store.upsertBudget(BudgetRecord(
                amountCents: 450_000,
                periodType: .nextMonth,
                timeKey: "\(PickBankClock.ms(from: monthStart))_\(PickBankClock.ms(from: monthEnd))",
                startMs: PickBankClock.ms(from: monthStart),
                endMs: PickBankClock.ms(from: monthEnd)
            ))
        }

        // Adopt a default pixel cat if pet module has no companions yet
        var petState = try await store.loadPetState()
        if petState.profiles.isEmpty {
            petState.settings.isEnabled = true
            petState.settings.budgetAmountCents = 15_000
            petState.wallet.availableEnergy = max(petState.wallet.availableEnergy, 42)
            petState.wallet.lifetimeEarnedEnergy = max(petState.wallet.lifetimeEarnedEnergy, 42)
            try await store.savePetState(petState)
            _ = try await store.adoptPet(species: PetSpecies.cat.rawValue, name: "拾念小橘", today: now)
        }
        return records.count
    }

    public static func factoryReset(
        store: PickBankStore,
        scheduler: AutoBackupScheduler,
        createFinalBackup: Bool = true
    ) async throws -> BackupSnapshotMetadata? {
        var safety: BackupSnapshotMetadata?
        if createFinalBackup {
            safety = try? await scheduler.createSnapshot(trigger: .preDestructive, password: nil, pin: true)
        }
        let current = try await store.loadSnapshot()
        let defaultCats = current.categories.filter(\.isDefault)
        let defaultWallets = current.wallets
        let fresh = PickBankLedgerSnapshot(
            categories: defaultCats,
            wallets: defaultWallets,
            tags: [],
            transactions: [],
            budgets: [],
            categoryLimits: [],
            recurringRules: [],
            petState: PetStateBundle(),
            preferences: current.preferences
        )
        try await store.replaceAll(with: fresh)
        return safety
    }
}
