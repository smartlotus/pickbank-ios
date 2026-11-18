import Foundation
import SQLite3

public enum PickBankStoreError: LocalizedError, Sendable {
    case sqliteError(String)
    case notFound(String)
    case validationError(String)

    public var errorDescription: String? {
        switch self {
        case .sqliteError(let msg): return msg
        case .notFound(let msg): return msg
        case .validationError(let msg): return msg
        }
    }
}

private final class SQLiteHandleBox: @unchecked Sendable {
    let ptr: OpaquePointer
    init(_ ptr: OpaquePointer) { self.ptr = ptr }
    deinit { sqlite3_close(ptr) }
}

public actor PickBankStore {
    public let baseDirectory: URL
    public let databaseURL: URL
    public let backupsDirectory: URL
    nonisolated public let customPetsDirectory: URL
    nonisolated public let tempExportsDirectory: URL

    private let dbBox: SQLiteHandleBox
    private var db: OpaquePointer { dbBox.ptr }
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL) throws {
        self.baseDirectory = baseDirectory
        self.databaseURL = baseDirectory.appendingPathComponent("sum_ledger.db")
        self.backupsDirectory = baseDirectory.appendingPathComponent("Backups", isDirectory: true)
        self.customPetsDirectory = baseDirectory.appendingPathComponent("CustomPets", isDirectory: true)
        self.tempExportsDirectory = baseDirectory.appendingPathComponent("Exports", isDirectory: true)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        let fm = FileManager.default
        try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: customPetsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: tempExportsDirectory, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open failed"
            if let handle { sqlite3_close(handle) }
            throw PickBankStoreError.sqliteError(msg)
        }
        self.dbBox = SQLiteHandleBox(handle)
        try Self.bootstrapSchema(db: handle)
        try Self.seedDefaultsIfNeeded(db: handle, encoder: encoder, decoder: decoder)
    }

    // MARK: - Schema & Defaults

    private static func bootstrapSchema(db: OpaquePointer) throws {
        let sql = """
        PRAGMA foreign_keys = ON;
        PRAGMA journal_mode = WAL;

        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon TEXT NOT NULL,
            type INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_default INTEGER NOT NULL DEFAULT 0,
            is_archived INTEGER NOT NULL DEFAULT 0,
            color_hex TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS wallets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon TEXT NOT NULL,
            initial_balance_cents INTEGER NOT NULL DEFAULT 0,
            is_default INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color_hex TEXT
        );

        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            amount_cents INTEGER NOT NULL,
            type INTEGER NOT NULL,
            category_id TEXT,
            category_name_snapshot TEXT NOT NULL,
            wallet_id TEXT,
            note TEXT,
            raw_input TEXT,
            tag_ids_json TEXT NOT NULL DEFAULT '[]',
            is_demo INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_tx_created_at ON transactions(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_tx_cat ON transactions(category_id, created_at DESC);

        CREATE TABLE IF NOT EXISTS budgets (
            id TEXT PRIMARY KEY,
            amount_cents INTEGER NOT NULL,
            period_type TEXT NOT NULL,
            custom_days INTEGER NOT NULL DEFAULT 0,
            time_key TEXT NOT NULL,
            start_ms INTEGER,
            end_ms INTEGER,
            category_id TEXT
        );

        CREATE TABLE IF NOT EXISTS category_monthly_limits (
            category_id TEXT PRIMARY KEY,
            monthly_limit_cents INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS recurring_rules (
            id TEXT PRIMARY KEY,
            amount_cents INTEGER NOT NULL,
            type INTEGER NOT NULL,
            category_id TEXT,
            wallet_id TEXT,
            note TEXT,
            period TEXT NOT NULL,
            next_run_at INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL
        );

        CREATE TABLE IF NOT EXISTS kv_blobs (
            key TEXT PRIMARY KEY,
            json_value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """
        try exec(db: db, sql: sql)
    }

    private static func seedDefaultsIfNeeded(db: OpaquePointer, encoder: JSONEncoder, decoder: JSONDecoder) throws {
        let count = try scalarInt(db: db, sql: "SELECT COUNT(*) FROM categories")
        let now = PickBankClock.nowMs()
        if count == 0 {
            let defaults: [(String, String, String, CategoryKind, Int)] = [
                ("cat-exp-food", "餐饮", "fork.knife", .expense, 0),
                ("cat-exp-transport", "交通", "car.fill", .expense, 1),
                ("cat-exp-shopping", "购物", "bag.fill", .expense, 2),
                ("cat-exp-housing", "住房", "house.fill", .expense, 3),
                ("cat-exp-fun", "娱乐", "gamecontroller.fill", .expense, 4),
                ("cat-exp-medical", "医疗", "cross.case.fill", .expense, 5),
                ("cat-exp-edu", "教育", "book.fill", .expense, 6),
                ("cat-exp-other", "其他", "ellipsis.circle.fill", .expense, 99),
                ("cat-inc-salary", "工资", "banknote.fill", .income, 0),
                ("cat-inc-side", "兼职", "briefcase.fill", .income, 1),
                ("cat-inc-invest", "投资", "chart.line.uptrend.xyaxis", .income, 2),
                ("cat-inc-gift", "红包", "gift.fill", .income, 3),
                ("cat-inc-other", "其他收入", "plus.circle.fill", .income, 99)
            ]
            for (id, name, icon, kind, order) in defaults {
                let rec = CategoryRecord(
                    id: id,
                    name: name,
                    icon: icon,
                    type: kind,
                    sortOrder: order,
                    isDefault: true,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now
                )
                try upsertCategoryRow(db: db, category: rec)
            }
        }

        let walletCount = try scalarInt(db: db, sql: "SELECT COUNT(*) FROM wallets")
        if walletCount == 0 {
            let wallets: [WalletAccount] = [
                WalletAccount(id: "wallet-default", name: "日常账户", icon: "wallet.bifold.fill", isDefault: true, sortOrder: 0),
                WalletAccount(id: "wallet-wechat", name: "微信", icon: "message.fill", isDefault: false, sortOrder: 1),
                WalletAccount(id: "wallet-alipay", name: "支付宝", icon: "qrcode", isDefault: false, sortOrder: 2),
                WalletAccount(id: "wallet-bank", name: "银行卡", icon: "creditcard.fill", isDefault: false, sortOrder: 3),
                WalletAccount(id: "wallet-cash", name: "现金", icon: "banknote", isDefault: false, sortOrder: 4)
            ]
            for w in wallets {
                try upsertWalletRow(db: db, wallet: w)
            }
        }

        if try getBlob(db: db, key: "pet_state") == nil {
            try saveBlob(db: db, key: "pet_state", value: PetStateBundle(), encoder: encoder)
        }
        if try getBlob(db: db, key: "app_preferences") == nil {
            try saveBlob(db: db, key: "app_preferences", value: AppPreferences(), encoder: encoder)
        }
        if try getBlob(db: db, key: "backup_schedule") == nil {
            try saveBlob(db: db, key: "backup_schedule", value: BackupScheduleConfig(), encoder: encoder)
        }
        _ = decoder
    }

    // MARK: - Snapshot & Restore

    public func loadSnapshot() throws -> PickBankLedgerSnapshot {
        let db = try requireDB()
        return PickBankLedgerSnapshot(
            categories: try fetchAllCategories(db: db),
            wallets: try fetchAllWallets(db: db),
            tags: try fetchAllTags(db: db),
            transactions: try fetchAllTransactions(db: db),
            budgets: try fetchAllBudgets(db: db),
            categoryLimits: try fetchAllCategoryLimits(db: db),
            recurringRules: try fetchAllRecurringRules(db: db),
            petState: try loadPetState(),
            preferences: try loadPreferences()
        )
    }

    public func replaceAll(with snapshot: PickBankLedgerSnapshot) throws {
        let db = try requireDB()
        try Self.withTransaction(db: db) {
            try Self.exec(db: db, sql: """
            DELETE FROM transactions;
            DELETE FROM category_monthly_limits;
            DELETE FROM recurring_rules;
            DELETE FROM budgets;
            DELETE FROM tags;
            DELETE FROM wallets;
            DELETE FROM categories;
            """)
            for cat in snapshot.categories {
                try Self.upsertCategoryRow(db: db, category: cat)
            }
            for w in snapshot.wallets {
                try Self.upsertWalletRow(db: db, wallet: w)
            }
            for tag in snapshot.tags {
                try Self.upsertTagRow(db: db, tag: tag)
            }
            let catMap = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
            for var tx in snapshot.transactions {
                if let cid = tx.categoryId, let cat = catMap[cid] {
                    tx.categoryNameSnapshot = cat.name
                }
                try Self.upsertTransactionRow(db: db, tx: tx, encoder: encoder)
            }
            for b in snapshot.budgets {
                try Self.upsertBudgetRow(db: db, budget: b)
            }
            for lim in snapshot.categoryLimits {
                try Self.upsertCategoryLimitRow(db: db, limit: lim)
            }
            for r in snapshot.recurringRules {
                try Self.upsertRecurringRuleRow(db: db, rule: r)
            }
            try Self.saveBlob(db: db, key: "pet_state", value: snapshot.petState, encoder: encoder)
            try Self.saveBlob(db: db, key: "app_preferences", value: snapshot.preferences, encoder: encoder)
        }
        try markDirty()
    }

    // MARK: - Transactions (with Permanent Category Snapshot)

    public func insertTransaction(_ tx: TransactionRecord) throws -> TransactionRecord {
        let db = try requireDB()
        var resolved = tx
        let categories = try fetchAllCategories(db: db)
        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        if let cid = resolved.categoryId, let cat = catMap[cid] {
            resolved.categoryNameSnapshot = cat.name
        } else if resolved.categoryNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved.categoryNameSnapshot = "未分类"
        }
        try Self.upsertTransactionRow(db: db, tx: resolved, encoder: encoder)
        try markDirty()
        return resolved
    }

    public func insertTransactions(_ items: [TransactionRecord]) throws -> [TransactionRecord] {
        let db = try requireDB()
        let categories = try fetchAllCategories(db: db)
        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var saved: [TransactionRecord] = []
        try Self.withTransaction(db: db) {
            for var item in items {
                if let cid = item.categoryId, let cat = catMap[cid] {
                    item.categoryNameSnapshot = cat.name
                } else if item.categoryNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    item.categoryNameSnapshot = "未分类"
                }
                try Self.upsertTransactionRow(db: db, tx: item, encoder: encoder)
                saved.append(item)
            }
        }
        if !items.isEmpty { try markDirty() }
        return saved
    }

    public func updateTransaction(_ tx: TransactionRecord) throws -> TransactionRecord {
        var updated = tx
        updated.updatedAt = PickBankClock.nowMs()
        return try insertTransaction(updated)
    }

    public func deleteTransaction(id: String) throws {
        let db = try requireDB()
        try Self.withPrepared(db: db, sql: "DELETE FROM transactions WHERE id = ?") { stmt in
            Self.bindText(stmt, index: 1, value: id)
            try Self.stepDone(stmt, db: db)
        }
        try markDirty()
    }

    public func deleteTransactions(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let db = try requireDB()
        try Self.withTransaction(db: db) {
            for id in ids {
                try Self.withPrepared(db: db, sql: "DELETE FROM transactions WHERE id = ?") { stmt in
                    Self.bindText(stmt, index: 1, value: id)
                    try Self.stepDone(stmt, db: db)
                }
            }
        }
        try markDirty()
    }

    // MARK: - Categories (Archive + Restore + Delete Forever + Active Reorder)

    public func activeCategories(kind: CategoryKind? = nil) throws -> [CategoryRecord] {
        let db = try requireDB()
        let all = try fetchAllCategories(db: db)
        return all.filter { !$0.isArchived && (kind == nil || $0.type == kind) }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    public func addCategory(name: String, icon: String = "bookmark.fill", type: CategoryKind, colorHex: String? = nil) throws -> CategoryRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PickBankStoreError.validationError("分类名称不能为空") }
        let db = try requireDB()
        let existing = try fetchAllCategories(db: db)
        if let dup = existing.first(where: { $0.type == type && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            if dup.isArchived {
                try restoreCategory(id: dup.id)
                return try fetchAllCategories(db: db).first(where: { $0.id == dup.id }) ?? dup
            }
            return dup
        }
        let maxOrder = existing.filter { !$0.isArchived && $0.type == type }.map(\.sortOrder).max() ?? -1
        let now = PickBankClock.nowMs()
        let cat = CategoryRecord(
            name: trimmed,
            icon: icon,
            type: type,
            sortOrder: maxOrder + 1,
            isDefault: false,
            isArchived: false,
            colorHex: colorHex,
            createdAt: now,
            updatedAt: now
        )
        try Self.upsertCategoryRow(db: db, category: cat)
        try markDirty()
        return cat
    }

    public func renameCategory(id: String, newName: String, icon: String? = nil, colorHex: String? = nil) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PickBankStoreError.validationError("分类名称不能为空") }
        let db = try requireDB()
        guard var cat = try fetchAllCategories(db: db).first(where: { $0.id == id }) else {
            throw PickBankStoreError.notFound("未找到分类")
        }
        cat.name = trimmed
        if let icon { cat.icon = icon }
        if let colorHex { cat.colorHex = colorHex }
        cat.updatedAt = PickBankClock.nowMs()
        try Self.withTransaction(db: db) {
            try Self.upsertCategoryRow(db: db, category: cat)
            // Keep linked transactions' snapshot name in sync when renaming an existing category
            try Self.withPrepared(db: db, sql: "UPDATE transactions SET category_name_snapshot = ? WHERE category_id = ?") { stmt in
                Self.bindText(stmt, index: 1, value: trimmed)
                Self.bindText(stmt, index: 2, value: id)
                try Self.stepDone(stmt, db: db)
            }
        }
        try markDirty()
    }

    public func archiveCategory(id: String) throws {
        let db = try requireDB()
        guard var cat = try fetchAllCategories(db: db).first(where: { $0.id == id }) else { return }
        cat.isArchived = true
        cat.updatedAt = PickBankClock.nowMs()
        try Self.upsertCategoryRow(db: db, category: cat)
        try renumberActiveCategories(kind: cat.type)
        try markDirty()
    }

    public func restoreCategory(id: String) throws {
        let db = try requireDB()
        let all = try fetchAllCategories(db: db)
        guard var cat = all.first(where: { $0.id == id }) else { return }
        let maxActive = all.filter { !$0.isArchived && $0.type == cat.type && $0.id != id }.map(\.sortOrder).max() ?? -1
        cat.isArchived = false
        cat.sortOrder = maxActive + 1
        cat.updatedAt = PickBankClock.nowMs()
        try Self.upsertCategoryRow(db: db, category: cat)
        try renumberActiveCategories(kind: cat.type)
        try markDirty()
    }

    /// Permanently deletes a category. Existing transactions preserve `categoryNameSnapshot`.
    public func deleteCategoryForever(id: String) throws {
        let db = try requireDB()
        try Self.withTransaction(db: db) {
            // Ensure snapshots are stamped before FK sets category_id = NULL
            if let cat = try fetchAllCategories(db: db).first(where: { $0.id == id }) {
                try Self.withPrepared(db: db, sql: "UPDATE transactions SET category_name_snapshot = ? WHERE category_id = ?") { stmt in
                    Self.bindText(stmt, index: 1, value: cat.name)
                    Self.bindText(stmt, index: 2, value: id)
                    try Self.stepDone(stmt, db: db)
                }
            }
            try Self.withPrepared(db: db, sql: "DELETE FROM categories WHERE id = ?") { stmt in
                Self.bindText(stmt, index: 1, value: id)
                try Self.stepDone(stmt, db: db)
            }
        }
        try markDirty()
    }

    public func reorderActiveCategories(kind: CategoryKind, orderedIds: [String]) throws {
        let db = try requireDB()
        let all = try fetchAllCategories(db: db)
        var byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let now = PickBankClock.nowMs()
        try Self.withTransaction(db: db) {
            for (idx, id) in orderedIds.enumerated() {
                if var cat = byId[id], !cat.isArchived, cat.type == kind {
                    cat.sortOrder = idx
                    cat.updatedAt = now
                    try Self.upsertCategoryRow(db: db, category: cat)
                    byId[id] = cat
                }
            }
        }
        try markDirty()
    }

    private func renumberActiveCategories(kind: CategoryKind) throws {
        let db = try requireDB()
        let active = try activeCategories(kind: kind)
        for (idx, var cat) in active.enumerated() {
            if cat.sortOrder != idx {
                cat.sortOrder = idx
                try Self.upsertCategoryRow(db: db, category: cat)
            }
        }
    }

    // MARK: - Budgets, Limits, Recurring, Wallets

    public func upsertBudget(_ budget: BudgetRecord) throws {
        let db = try requireDB()
        try Self.withTransaction(db: db) {
            // Keep one active global budget per period/timeKey or replace active dashboard budget cleanly
            if budget.categoryId == nil {
                try Self.withPrepared(db: db, sql: "DELETE FROM budgets WHERE category_id IS NULL") { stmt in
                    try Self.stepDone(stmt, db: db)
                }
            }
            try Self.upsertBudgetRow(db: db, budget: budget)
        }
        try markDirty()
    }

    public func deleteBudget(id: String) throws {
        let db = try requireDB()
        try Self.withPrepared(db: db, sql: "DELETE FROM budgets WHERE id = ?") { stmt in
            Self.bindText(stmt, index: 1, value: id)
            try Self.stepDone(stmt, db: db)
        }
        try markDirty()
    }

    public func setCategoryMonthlyLimit(categoryId: String, monthlyLimitCents: Int64?) throws {
        let db = try requireDB()
        if let cents = monthlyLimitCents, cents > 0 {
            let now = PickBankClock.nowMs()
            try Self.upsertCategoryLimitRow(db: db, limit: CategoryMonthlyLimitRecord(categoryId: categoryId, monthlyLimitCents: cents, createdAt: now, updatedAt: now))
        } else {
            try Self.withPrepared(db: db, sql: "DELETE FROM category_monthly_limits WHERE category_id = ?") { stmt in
                Self.bindText(stmt, index: 1, value: categoryId)
                try Self.stepDone(stmt, db: db)
            }
        }
        try markDirty()
    }

    public func upsertRecurringRule(_ rule: RecurringRuleRecord) throws {
        let db = try requireDB()
        try Self.upsertRecurringRuleRow(db: db, rule: rule)
        try markDirty()
    }

    public func deleteRecurringRule(id: String) throws {
        let db = try requireDB()
        try Self.withPrepared(db: db, sql: "DELETE FROM recurring_rules WHERE id = ?") { stmt in
            Self.bindText(stmt, index: 1, value: id)
            try Self.stepDone(stmt, db: db)
        }
        try markDirty()
    }

    @discardableResult
    public func processDueRecurringRules(asOf nowMs: Int64 = PickBankClock.nowMs()) throws -> [TransactionRecord] {
        let db = try requireDB()
        let rules = try fetchAllRecurringRules(db: db)
        let cats = Dictionary(uniqueKeysWithValues: try fetchAllCategories(db: db).map { ($0.id, $0) })
        let result = RecurringEngine.evaluateDueRules(rules: rules, asOf: nowMs, categoriesById: cats)
        guard !result.generatedTransactions.isEmpty else { return [] }
        try Self.withTransaction(db: db) {
            for tx in result.generatedTransactions {
                try Self.upsertTransactionRow(db: db, tx: tx, encoder: encoder)
            }
            for rule in result.updatedRules {
                try Self.upsertRecurringRuleRow(db: db, rule: rule)
            }
        }
        try markDirty()
        return result.generatedTransactions
    }

    public func upsertWallet(_ wallet: WalletAccount) throws {
        let db = try requireDB()
        try Self.upsertWalletRow(db: db, wallet: wallet)
        try markDirty()
    }

    public func ensureTags(names: [String]) throws -> [String] {
        let db = try requireDB()
        var existing = try fetchAllTags(db: db)
        var ids: [String] = []
        var changed = false
        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let hit = existing.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                ids.append(hit.id)
            } else {
                let tag = TagRecord(name: trimmed)
                try Self.upsertTagRow(db: db, tag: tag)
                existing.append(tag)
                ids.append(tag.id)
                changed = true
            }
        }
        if changed { try markDirty() }
        return ids
    }

    public func renamePet(id: String, newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20 else {
            throw PickBankStoreError.validationError("宠物名字需为 1–20 个字符")
        }
        var petState = try loadPetState()
        guard let idx = petState.profiles.firstIndex(where: { $0.id == id }) else {
            throw PickBankStoreError.notFound("伙伴不存在")
        }
        petState.profiles[idx].name = trimmed
        petState.profiles[idx].updatedAt = PickBankClock.nowMs()
        try savePetState(petState)
    }

    public func deleteCustomPetDefinition(id: String) throws {
        var petState = try loadPetState()
        let adoptedSpecies = PetSpecies.customSpeciesString(definitionId: id)
        guard !petState.profiles.contains(where: { $0.species == adoptedSpecies }) else {
            throw PickBankStoreError.validationError("已被领养的自定义伙伴禁止删除，以保护历史档案完整性")
        }
        petState.customPets.removeAll { $0.id == id }
        try savePetState(petState)
        let dir = customPetsDirectory.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    public func acknowledgeMilestone(key: String) throws {
        var petState = try loadPetState()
        if !petState.acknowledgedMilestones.contains(key) {
            petState.acknowledgedMilestones.append(key)
            try savePetState(petState)
        }
    }

    // MARK: - Pet State, Preferences & Backup Schedule

    public func loadPetState() throws -> PetStateBundle {
        let db = try requireDB()
        if let json = try Self.getBlob(db: db, key: "pet_state"),
           let data = json.data(using: .utf8),
           let parsed = try? decoder.decode(PetStateBundle.self, from: data) {
            return parsed
        }
        return PetStateBundle()
    }

    public func savePetState(_ petState: PetStateBundle) throws {
        let db = try requireDB()
        try Self.saveBlob(db: db, key: "pet_state", value: petState, encoder: encoder)
        try markDirty()
    }

    public func loadPreferences() throws -> AppPreferences {
        let db = try requireDB()
        if let json = try Self.getBlob(db: db, key: "app_preferences"),
           let data = json.data(using: .utf8),
           let parsed = try? decoder.decode(AppPreferences.self, from: data) {
            return parsed
        }
        return AppPreferences()
    }

    public func savePreferences(_ prefs: AppPreferences) throws {
        let db = try requireDB()
        try Self.saveBlob(db: db, key: "app_preferences", value: prefs, encoder: encoder)
    }

    public func loadBackupSchedule() throws -> BackupScheduleConfig {
        let db = try requireDB()
        if let json = try Self.getBlob(db: db, key: "backup_schedule"),
           let data = json.data(using: .utf8),
           let parsed = try? decoder.decode(BackupScheduleConfig.self, from: data) {
            return parsed
        }
        return BackupScheduleConfig()
    }

    public func saveBackupSchedule(_ config: BackupScheduleConfig) throws {
        let db = try requireDB()
        try Self.saveBlob(db: db, key: "backup_schedule", value: config, encoder: encoder)
    }

    public func markDirty(at ms: Int64 = PickBankClock.nowMs()) throws {
        var config = try loadBackupSchedule()
        config.lastDirtyMutationAt = ms
        try saveBackupSchedule(config)
    }

    public func checkpointWAL() throws {
        let db = try requireDB()
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    // MARK: - Pet Domain Operations (Mirroring Android PetRepository)

    @discardableResult
    public func settleCompletedPetDays(today: Date = Date(), calendar: Calendar = .current) throws -> PetStateBundle {
        var petState = try loadPetState()
        guard petState.settings.isEnabled, petState.settings.budgetAmountCents > 0 else { return petState }

        let todayStart = calendar.startOfDay(for: today)
        let todayKey = PickBankClock.dateKey(for: todayStart, calendar: calendar)
        var cursorDate: Date
        if let lastKey = petState.settings.lastSettledDateKey,
           let parsed = PickBankClock.parseDateKey(lastKey, calendar: calendar) {
            cursorDate = parsed
        } else {
            cursorDate = todayStart
        }

        let db = try requireDB()
        let transactions = try fetchAllTransactions(db: db)
        let settledKeys = Set(petState.settlements.map(\.dateKey))
        var streak = petState.settings.overspendStreak
        var didSettle = false

        while cursorDate < todayStart {
            let key = PickBankClock.dateKey(for: cursorDate, calendar: calendar)
            if !settledKeys.contains(key) {
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursorDate)!
                let sMs = PickBankClock.ms(from: cursorDate)
                let eMs = PickBankClock.ms(from: dayEnd)
                let dayTxs = transactions.filter { $0.createdAt >= sMs && $0.createdAt < eMs }
                let exp = dayTxs.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
                let inc = dayTxs.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }

                let allowance: Int64
                if petState.settings.budgetMode == .monthly {
                    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: cursorDate))!
                    let mStartMs = PickBankClock.ms(from: monthStart)
                    let prevSpent = transactions
                        .filter { $0.type == .expense && $0.createdAt >= mStartMs && $0.createdAt < sMs }
                        .reduce(Int64(0)) { $0 + $1.amountCents }
                    let daysInMonth = calendar.range(of: .day, in: .month, for: cursorDate)?.count ?? 30
                    let dayOfMonth = calendar.component(.day, from: cursorDate)
                    let remDays = max(1, daysInMonth - dayOfMonth + 1)
                    allowance = max(0, petState.settings.budgetAmountCents - prevSpent) / Int64(remDays)
                } else {
                    allowance = petState.settings.budgetAmountCents
                }

                let calc = PetAdoptionPolicy.computeDayEnergy(
                    allowanceCents: allowance,
                    expenseCents: exp,
                    incomeCents: inc,
                    priorOverspendStreak: streak
                )
                streak = calc.nextStreak
                let earned = calc.savingEnergy + calc.incomeEnergy
                petState.wallet.availableEnergy += earned
                petState.wallet.lifetimeEarnedEnergy += earned
                petState.wallet.updatedAt = PickBankClock.nowMs()

                let releasedSet = Set(petState.releasedRecords.map(\.petId))
                let timelineMap = Dictionary(uniqueKeysWithValues: petState.timelines.map { ($0.petId, $0) })
                for idx in petState.profiles.indices {
                    let pet = petState.profiles[idx]
                    guard !releasedSet.contains(pet.id) else { continue }
                    if let tl = timelineMap[pet.id], PetLifecycleEngine.evaluateAt(timeline: tl, dateKey: key, calendar: calendar).vitalState == .deceased {
                        continue
                    }
                    petState.profiles[idx].satiety = max(0, pet.satiety - calc.satietyLoss)
                    petState.profiles[idx].updatedAt = PickBankClock.nowMs()
                }

                petState.settlements.append(PetDailySettlement(
                    dateKey: key,
                    budgetCents: allowance,
                    expenseCents: exp,
                    incomeCents: inc,
                    savingEnergy: calc.savingEnergy,
                    incomeEnergy: calc.incomeEnergy,
                    satietyLoss: calc.satietyLoss,
                    overspendStreak: streak
                ))
                petState.settings.lastSettledDateKey = key
                petState.settings.overspendStreak = streak
                didSettle = true
            }
            cursorDate = calendar.date(byAdding: .day, value: 1, to: cursorDate)!
        }

        // Advance monotonic timeline dates & reconcile unlocked slots
        let releasedSet = Set(petState.releasedRecords.map(\.petId))
        for idx in petState.timelines.indices {
            if releasedSet.contains(petState.timelines[idx].petId) { continue }
            if todayKey > petState.timelines[idx].lastEvaluatedDateKey {
                petState.timelines[idx].lastEvaluatedDateKey = todayKey
                didSettle = true
            }
        }
        reconcilePetSlots(in: &petState, todayKey: todayKey)
        if didSettle {
            try savePetState(petState)
        }
        return petState
    }

    public func adoptPet(species: String, name: String, today: Date = Date()) throws -> PetProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20 else {
            throw PickBankStoreError.validationError("宠物名字需为 1–20 个字符")
        }
        var petState = try loadPetState()
        let todayKey = PickBankClock.dateKey(for: today)
        reconcilePetSlots(in: &petState, todayKey: todayKey)

        let activeCount = activePetCount(in: petState, todayKey: todayKey)
        guard activeCount < petState.slotState.unlockedSlots else {
            throw PickBankStoreError.validationError("当前栏位已满（\(activeCount)/\(petState.slotState.unlockedSlots)），陪伴达标或放生纪念后可解锁新栏位")
        }
        if PetSpecies.customDefinitionId(from: species) != nil,
           petState.profiles.contains(where: { $0.species == species }) {
            throw PickBankStoreError.validationError("同一个自定义伙伴只能领养一次")
        }

        let now = PickBankClock.nowMs()
        let nextOrder = (petState.profiles.map(\.adoptOrder).max() ?? -1) + 1
        let profile = PetProfile(
            species: species,
            name: trimmed,
            growth: 0,
            affection: 0,
            satiety: 70,
            adoptOrder: nextOrder,
            createdAt: now,
            updatedAt: now
        )
        let timeline = PetLifecycleEngine.createTimeline(petId: profile.id, species: species, adoptionDate: today)
        petState.settings.isEnabled = true
        if petState.settings.lastSettledDateKey == nil {
            petState.settings.lastSettledDateKey = todayKey
        }
        petState.profiles.append(profile)
        petState.timelines.append(timeline)
        try savePetState(petState)
        return profile
    }

    @discardableResult
    public func feedPet(id: String, requestedEnergy: Int) throws -> Int {
        guard requestedEnergy > 0 else { return 0 }
        var petState = try loadPetState()
        let todayKey = PickBankClock.dateKey()
        guard let idx = petState.profiles.firstIndex(where: { $0.id == id }) else { return 0 }
        if petState.releasedRecords.contains(where: { $0.petId == id }) { return 0 }
        if let tl = petState.timelines.first(where: { $0.petId == id }),
           PetLifecycleEngine.evaluate(timeline: tl, todayKey: todayKey).vitalState == .deceased {
            return 0
        }
        let room = max(0, 100 - petState.profiles[idx].satiety)
        let accepted = min(requestedEnergy, min(petState.wallet.availableEnergy, room))
        guard accepted > 0 else { return 0 }

        let now = PickBankClock.nowMs()
        petState.wallet.availableEnergy -= accepted
        petState.wallet.updatedAt = now
        petState.profiles[idx].satiety = min(100, petState.profiles[idx].satiety + accepted)
        petState.profiles[idx].growth += accepted
        petState.profiles[idx].updatedAt = now
        reconcilePetSlots(in: &petState, todayKey: todayKey)
        try savePetState(petState)
        return accepted
    }

    @discardableResult
    public func interactWithPet(id: String, today: Date = Date()) throws -> Bool {
        var petState = try loadPetState()
        let todayKey = PickBankClock.dateKey(for: today)
        guard let idx = petState.profiles.firstIndex(where: { $0.id == id }) else { return false }
        if petState.releasedRecords.contains(where: { $0.petId == id }) { return false }
        if let tl = petState.timelines.first(where: { $0.petId == id }),
           PetLifecycleEngine.evaluate(timeline: tl, todayKey: todayKey).vitalState == .deceased {
            return false
        }

        let countIdx = petState.interactions.firstIndex(where: { $0.petId == id && $0.dateKey == todayKey })
        let currentCount = countIdx.map { petState.interactions[$0].interactionCount } ?? 0
        guard currentCount < PetAdoptionPolicy.maxDailyAffectionInteractions else { return false }

        if let countIdx {
            petState.interactions[countIdx].interactionCount += 1
        } else {
            petState.interactions.append(PetDailyInteraction(petId: id, dateKey: todayKey, interactionCount: 1))
        }
        petState.profiles[idx].affection = min(100, petState.profiles[idx].affection + 1)
        petState.profiles[idx].updatedAt = PickBankClock.nowMs()
        reconcilePetSlots(in: &petState, todayKey: todayKey)
        try savePetState(petState)
        return true
    }

    public func releasePet(id: String, today: Date = Date()) throws -> PetReleaseRecord {
        var petState = try loadPetState()
        let todayKey = PickBankClock.dateKey(for: today)
        guard let profile = petState.profiles.first(where: { $0.id == id }) else {
            throw PickBankStoreError.notFound("伙伴不存在。")
        }
        let tl = petState.timelines.first(where: { $0.petId == id })
        let snap = tl.map { PetLifecycleEngine.evaluate(timeline: $0, todayKey: todayKey) }
        let released = petState.releasedRecords.contains(where: { $0.petId == id })
        if let reason = PetAdoptionPolicy.releaseBlockReason(profile: profile, timeline: tl, snapshot: snap, isReleased: released, todayKey: todayKey) {
            throw PickBankStoreError.validationError(reason)
        }
        let record = PetReleaseRecord(
            petId: profile.id,
            petName: profile.name,
            species: profile.species,
            adoptionDays: PetAdoptionPolicy.adoptionDays(profile: profile, timeline: tl, todayKey: todayKey),
            growthAtRelease: profile.growth,
            affectionAtRelease: profile.affection,
            releasedAt: PickBankClock.nowMs(),
            releaseDateKey: todayKey
        )
        petState.releasedRecords.append(record)
        reconcilePetSlots(in: &petState, todayKey: todayKey)
        try savePetState(petState)
        return record
    }

    private func activePetCount(in petState: PetStateBundle, todayKey: String) -> Int {
        let released = Set(petState.releasedRecords.map(\.petId))
        let tlMap = Dictionary(uniqueKeysWithValues: petState.timelines.map { ($0.petId, $0) })
        return petState.profiles.filter { pet in
            if released.contains(pet.id) { return false }
            if let tl = tlMap[pet.id], PetLifecycleEngine.evaluate(timeline: tl, todayKey: todayKey).vitalState == .deceased {
                return false
            }
            return true
        }.count
    }

    private func reconcilePetSlots(in petState: inout PetStateBundle, todayKey: String) {
        let tlMap = Dictionary(uniqueKeysWithValues: petState.timelines.map { ($0.petId, $0) })
        for pet in petState.profiles {
            if PetAdoptionPolicy.slotQualified(profile: pet, timeline: tlMap[pet.id], todayKey: todayKey) {
                petState.slotState.qualifiedPetIds.insert(pet.id)
            }
        }
        let expected = min(PetAdoptionPolicy.maxUnlockedSlots, PetAdoptionPolicy.baseSlots + petState.slotState.qualifiedPetIds.count)
        petState.slotState.unlockedSlots = max(petState.slotState.unlockedSlots, expected)
    }

    // MARK: - SQLite Row Helpers

    private func requireDB() throws -> OpaquePointer {
        db
    }

    private static func exec(db: OpaquePointer, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw PickBankStoreError.sqliteError(msg)
        }
    }

    private static func withTransaction(db: OpaquePointer, body: () throws -> Void) throws {
        try exec(db: db, sql: "BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try exec(db: db, sql: "COMMIT")
        } catch {
            try? exec(db: db, sql: "ROLLBACK")
            throw error
        }
    }

    private static func withPrepared<T>(db: OpaquePointer, sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw PickBankStoreError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        return try body(stmt)
    }

    private static func stepDone(_ stmt: OpaquePointer, db: OpaquePointer) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw PickBankStoreError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func scalarInt(db: OpaquePointer, sql: String) throws -> Int {
        try withPrepared(db: db, sql: sql) { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int64(stmt, 0))
            }
            return 0
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bindText(_ stmt: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func bindInt64(_ stmt: OpaquePointer, index: Int32, value: Int64?) {
        if let value {
            sqlite3_bind_int64(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func colText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private static func colInt64Opt(_ stmt: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    private static func upsertCategoryRow(db: OpaquePointer, category c: CategoryRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO categories (id, name, icon, type, sort_order, is_default, is_archived, color_hex, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: c.id)
            bindText(stmt, index: 2, value: c.name)
            bindText(stmt, index: 3, value: c.icon)
            sqlite3_bind_int(stmt, 4, Int32(c.type.rawValue))
            sqlite3_bind_int(stmt, 5, Int32(c.sortOrder))
            sqlite3_bind_int(stmt, 6, c.isDefault ? 1 : 0)
            sqlite3_bind_int(stmt, 7, c.isArchived ? 1 : 0)
            bindText(stmt, index: 8, value: c.colorHex)
            sqlite3_bind_int64(stmt, 9, c.createdAt)
            sqlite3_bind_int64(stmt, 10, c.updatedAt)
            try stepDone(stmt, db: db)
        }
    }

    private static func upsertWalletRow(db: OpaquePointer, wallet w: WalletAccount) throws {
        let sql = """
        INSERT OR REPLACE INTO wallets (id, name, icon, initial_balance_cents, is_default, sort_order)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: w.id)
            bindText(stmt, index: 2, value: w.name)
            bindText(stmt, index: 3, value: w.icon)
            sqlite3_bind_int64(stmt, 4, w.initialBalanceCents)
            sqlite3_bind_int(stmt, 5, w.isDefault ? 1 : 0)
            sqlite3_bind_int(stmt, 6, Int32(w.sortOrder))
            try stepDone(stmt, db: db)
        }
    }

    private static func upsertTagRow(db: OpaquePointer, tag t: TagRecord) throws {
        let sql = "INSERT OR REPLACE INTO tags (id, name, color_hex) VALUES (?, ?, ?)"
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: t.id)
            bindText(stmt, index: 2, value: t.name)
            bindText(stmt, index: 3, value: t.colorHex)
            try stepDone(stmt, db: db)
        }
    }

    private static func upsertTransactionRow(db: OpaquePointer, tx: TransactionRecord, encoder: JSONEncoder) throws {
        let tagData = (try? encoder.encode(tx.tagIds)) ?? Data("[]".utf8)
        let tagJson = String(data: tagData, encoding: .utf8) ?? "[]"
        let sql = """
        INSERT OR REPLACE INTO transactions
        (id, amount_cents, type, category_id, category_name_snapshot, wallet_id, note, raw_input, tag_ids_json, is_demo, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: tx.id)
            sqlite3_bind_int64(stmt, 2, tx.amountCents)
            sqlite3_bind_int(stmt, 3, Int32(tx.type.rawValue))
            bindText(stmt, index: 4, value: tx.categoryId)
            bindText(stmt, index: 5, value: tx.categoryNameSnapshot)
            bindText(stmt, index: 6, value: tx.walletId)
            bindText(stmt, index: 7, value: tx.note)
            bindText(stmt, index: 8, value: tx.rawInput)
            bindText(stmt, index: 9, value: tagJson)
            sqlite3_bind_int(stmt, 10, tx.isDemo ? 1 : 0)
            sqlite3_bind_int64(stmt, 11, tx.createdAt)
            sqlite3_bind_int64(stmt, 12, tx.updatedAt)
            try stepDone(stmt, db: db)
        }
    }

    private static func upsertBudgetRow(db: OpaquePointer, budget b: BudgetRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO budgets (id, amount_cents, period_type, custom_days, time_key, start_ms, end_ms, category_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: b.id)
            sqlite3_bind_int64(stmt, 2, b.amountCents)
            bindText(stmt, index: 3, value: b.periodType.rawValue)
            sqlite3_bind_int(stmt, 4, Int32(b.customDays))
            bindText(stmt, index: 5, value: b.timeKey)
            bindInt64(stmt, index: 6, value: b.startMs)
            bindInt64(stmt, index: 7, value: b.endMs)
            bindText(stmt, index: 8, value: b.categoryId)
            try stepDone(stmt, db: db)
        }
    }

    private static func upsertCategoryLimitRow(db: OpaquePointer, limit l: CategoryMonthlyLimitRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO category_monthly_limits (category_id, monthly_limit_cents, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        """
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: l.categoryId)
            sqlite3_bind_int64(stmt, 2, l.monthlyLimitCents)
            sqlite3_bind_int64(stmt, 3, l.createdAt)
            sqlite3_bind_int64(stmt, 4, l.updatedAt)
            try stepDone(stmt, db: db)
        }
    }

    private static func upsertRecurringRuleRow(db: OpaquePointer, rule r: RecurringRuleRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO recurring_rules (id, amount_cents, type, category_id, wallet_id, note, period, next_run_at, is_active, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: r.id)
            sqlite3_bind_int64(stmt, 2, r.amountCents)
            sqlite3_bind_int(stmt, 3, Int32(r.type.rawValue))
            bindText(stmt, index: 4, value: r.categoryId)
            bindText(stmt, index: 5, value: r.walletId)
            bindText(stmt, index: 6, value: r.note)
            bindText(stmt, index: 7, value: r.period.rawValue)
            sqlite3_bind_int64(stmt, 8, r.nextRunAt)
            sqlite3_bind_int(stmt, 9, r.isActive ? 1 : 0)
            sqlite3_bind_int64(stmt, 10, r.createdAt)
            sqlite3_bind_int64(stmt, 11, r.updatedAt)
            try stepDone(stmt, db: db)
        }
    }

    private func fetchAllCategories(db: OpaquePointer) throws -> [CategoryRecord] {
        try Self.withPrepared(db: db, sql: "SELECT id, name, icon, type, sort_order, is_default, is_archived, color_hex, created_at, updated_at FROM categories ORDER BY type ASC, sort_order ASC, created_at ASC") { stmt in
            var rows: [CategoryRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(CategoryRecord(
                    id: Self.colText(stmt, 0) ?? UUID().uuidString,
                    name: Self.colText(stmt, 1) ?? "未分类",
                    icon: Self.colText(stmt, 2) ?? "bookmark.fill",
                    type: CategoryKind(rawValue: Int(sqlite3_column_int(stmt, 3))) ?? .expense,
                    sortOrder: Int(sqlite3_column_int(stmt, 4)),
                    isDefault: sqlite3_column_int(stmt, 5) != 0,
                    isArchived: sqlite3_column_int(stmt, 6) != 0,
                    colorHex: Self.colText(stmt, 7),
                    createdAt: sqlite3_column_int64(stmt, 8),
                    updatedAt: sqlite3_column_int64(stmt, 9)
                ))
            }
            return rows
        }
    }

    private func fetchAllWallets(db: OpaquePointer) throws -> [WalletAccount] {
        try Self.withPrepared(db: db, sql: "SELECT id, name, icon, initial_balance_cents, is_default, sort_order FROM wallets ORDER BY sort_order ASC") { stmt in
            var rows: [WalletAccount] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(WalletAccount(
                    id: Self.colText(stmt, 0) ?? UUID().uuidString,
                    name: Self.colText(stmt, 1) ?? "账户",
                    icon: Self.colText(stmt, 2) ?? "wallet.bifold.fill",
                    initialBalanceCents: sqlite3_column_int64(stmt, 3),
                    isDefault: sqlite3_column_int(stmt, 4) != 0,
                    sortOrder: Int(sqlite3_column_int(stmt, 5))
                ))
            }
            return rows
        }
    }

    private func fetchAllTags(db: OpaquePointer) throws -> [TagRecord] {
        try Self.withPrepared(db: db, sql: "SELECT id, name, color_hex FROM tags ORDER BY name ASC") { stmt in
            var rows: [TagRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(TagRecord(
                    id: Self.colText(stmt, 0) ?? UUID().uuidString,
                    name: Self.colText(stmt, 1) ?? "",
                    colorHex: Self.colText(stmt, 2)
                ))
            }
            return rows
        }
    }

    private func fetchAllTransactions(db: OpaquePointer) throws -> [TransactionRecord] {
        try Self.withPrepared(db: db, sql: "SELECT id, amount_cents, type, category_id, category_name_snapshot, wallet_id, note, raw_input, tag_ids_json, is_demo, created_at, updated_at FROM transactions ORDER BY created_at DESC") { stmt in
            var rows: [TransactionRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let tagJson = Self.colText(stmt, 8) ?? "[]"
                let tagIds = (try? decoder.decode([String].self, from: Data(tagJson.utf8))) ?? []
                rows.append(TransactionRecord(
                    id: Self.colText(stmt, 0) ?? UUID().uuidString,
                    amountCents: sqlite3_column_int64(stmt, 1),
                    type: TransactionType(rawValue: Int(sqlite3_column_int(stmt, 2))) ?? .expense,
                    categoryId: Self.colText(stmt, 3),
                    categoryNameSnapshot: Self.colText(stmt, 4) ?? "未分类",
                    walletId: Self.colText(stmt, 5),
                    note: Self.colText(stmt, 6),
                    rawInput: Self.colText(stmt, 7),
                    tagIds: tagIds,
                    isDemo: sqlite3_column_int(stmt, 9) != 0,
                    createdAt: sqlite3_column_int64(stmt, 10),
                    updatedAt: sqlite3_column_int64(stmt, 11)
                ))
            }
            return rows
        }
    }

    private func fetchAllBudgets(db: OpaquePointer) throws -> [BudgetRecord] {
        try Self.withPrepared(db: db, sql: "SELECT id, amount_cents, period_type, custom_days, time_key, start_ms, end_ms, category_id FROM budgets") { stmt in
            var rows: [BudgetRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let pRaw = Self.colText(stmt, 2) ?? "MONTHLY"
                rows.append(BudgetRecord(
                    id: Self.colText(stmt, 0) ?? UUID().uuidString,
                    amountCents: sqlite3_column_int64(stmt, 1),
                    periodType: BudgetPeriodType(rawValue: pRaw) ?? .monthly,
                    customDays: Int(sqlite3_column_int(stmt, 3)),
                    timeKey: Self.colText(stmt, 4) ?? "",
                    startMs: Self.colInt64Opt(stmt, 5),
                    endMs: Self.colInt64Opt(stmt, 6),
                    categoryId: Self.colText(stmt, 7)
                ))
            }
            return rows
        }
    }

    private func fetchAllCategoryLimits(db: OpaquePointer) throws -> [CategoryMonthlyLimitRecord] {
        try Self.withPrepared(db: db, sql: "SELECT category_id, monthly_limit_cents, created_at, updated_at FROM category_monthly_limits") { stmt in
            var rows: [CategoryMonthlyLimitRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(CategoryMonthlyLimitRecord(
                    categoryId: Self.colText(stmt, 0) ?? "",
                    monthlyLimitCents: sqlite3_column_int64(stmt, 1),
                    createdAt: sqlite3_column_int64(stmt, 2),
                    updatedAt: sqlite3_column_int64(stmt, 3)
                ))
            }
            return rows
        }
    }

    private func fetchAllRecurringRules(db: OpaquePointer) throws -> [RecurringRuleRecord] {
        try Self.withPrepared(db: db, sql: "SELECT id, amount_cents, type, category_id, wallet_id, note, period, next_run_at, is_active, created_at, updated_at FROM recurring_rules") { stmt in
            var rows: [RecurringRuleRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let pRaw = Self.colText(stmt, 6) ?? "MONTHLY"
                rows.append(RecurringRuleRecord(
                    id: Self.colText(stmt, 0) ?? UUID().uuidString,
                    amountCents: sqlite3_column_int64(stmt, 1),
                    type: TransactionType(rawValue: Int(sqlite3_column_int(stmt, 2))) ?? .expense,
                    categoryId: Self.colText(stmt, 3),
                    walletId: Self.colText(stmt, 4),
                    note: Self.colText(stmt, 5),
                    period: RecurringPeriod(rawValue: pRaw) ?? .monthly,
                    nextRunAt: sqlite3_column_int64(stmt, 7),
                    isActive: sqlite3_column_int(stmt, 8) != 0,
                    createdAt: sqlite3_column_int64(stmt, 9),
                    updatedAt: sqlite3_column_int64(stmt, 10)
                ))
            }
            return rows
        }
    }

    private static func getBlob(db: OpaquePointer, key: String) throws -> String? {
        try withPrepared(db: db, sql: "SELECT json_value FROM kv_blobs WHERE key = ?") { stmt in
            bindText(stmt, index: 1, value: key)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return colText(stmt, 0)
            }
            return nil
        }
    }

    private static func saveBlob<T: Encodable>(db: OpaquePointer, key: String, value: T, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let sql = "INSERT OR REPLACE INTO kv_blobs (key, json_value, updated_at) VALUES (?, ?, ?)"
        try withPrepared(db: db, sql: sql) { stmt in
            bindText(stmt, index: 1, value: key)
            bindText(stmt, index: 2, value: json)
            sqlite3_bind_int64(stmt, 3, PickBankClock.nowMs())
            try stepDone(stmt, db: db)
        }
    }
}
