import Foundation

public struct PickBankLedgerSnapshot: Codable, Sendable, Hashable {
    public var categories: [CategoryRecord]
    public var wallets: [WalletAccount]
    public var tags: [TagRecord]
    public var transactions: [TransactionRecord]
    public var budgets: [BudgetRecord]
    public var categoryLimits: [CategoryMonthlyLimitRecord]
    public var recurringRules: [RecurringRuleRecord]
    public var petState: PetStateBundle
    public var preferences: AppPreferences

    public init(
        categories: [CategoryRecord] = [],
        wallets: [WalletAccount] = [],
        tags: [TagRecord] = [],
        transactions: [TransactionRecord] = [],
        budgets: [BudgetRecord] = [],
        categoryLimits: [CategoryMonthlyLimitRecord] = [],
        recurringRules: [RecurringRuleRecord] = [],
        petState: PetStateBundle = PetStateBundle(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.categories = categories
        self.wallets = wallets
        self.tags = tags
        self.transactions = transactions
        self.budgets = budgets
        self.categoryLimits = categoryLimits
        self.recurringRules = recurringRules
        self.petState = petState
        self.preferences = preferences
    }
}

public struct PickBankArchiveV2: Codable, Sendable, Hashable {
    public var format: String
    public var schemaVersion: Int
    public var appVersion: String
    public var platform: String
    public var exportedAt: Int64
    public var sha256: String
    public var payload: PickBankLedgerSnapshot

    public static let formatIdentifier = "pickbank-archive-v2"
    public static let currentSchemaVersion = 2

    public init(
        format: String = PickBankArchiveV2.formatIdentifier,
        schemaVersion: Int = PickBankArchiveV2.currentSchemaVersion,
        appVersion: String = "2.0.0",
        platform: String = "iOS",
        exportedAt: Int64 = PickBankClock.nowMs(),
        sha256: String,
        payload: PickBankLedgerSnapshot
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.platform = platform
        self.exportedAt = exportedAt
        self.sha256 = sha256
        self.payload = payload
    }
}

public struct EncryptedBackupMeta: Codable, Sendable, Hashable {
    public var version: Int
    public var kdf: String
    public var iterations: Int
    public var salt: String
}

public struct EncryptedBackupEnvelope: Codable, Sendable, Hashable {
    public var version: Int
    public var algorithm: String
    public var iv: String
    public var ciphertext: String
}

public struct PickBankEncryptedBackup: Codable, Sendable, Hashable {
    public var format: String
    public var version: Int
    public var exportedAt: Int64
    public var meta: EncryptedBackupMeta
    public var envelope: EncryptedBackupEnvelope

    public static let formatIdentifier = "pickbank-encrypted-backup"
}

public enum BackupTriggerKind: String, Codable, Sendable, CaseIterable, Hashable {
    case auto = "AUTO"
    case manual = "MANUAL"
    case preImport = "PRE_IMPORT"
    case preDestructive = "PRE_DESTRUCTIVE"
}

public struct BackupSnapshotMetadata: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var fileName: String
    public var createdAt: Int64
    public var trigger: BackupTriggerKind
    public var isEncrypted: Bool
    public var isPinned: Bool
    public var transactionCount: Int
    public var categoryCount: Int
    public var petCount: Int
    public var byteSize: Int64
    public var sha256: String
    public var externalSynced: Bool

    public init(
        id: String = UUID().uuidString,
        fileName: String,
        createdAt: Int64 = PickBankClock.nowMs(),
        trigger: BackupTriggerKind,
        isEncrypted: Bool,
        isPinned: Bool = false,
        transactionCount: Int,
        categoryCount: Int,
        petCount: Int,
        byteSize: Int64,
        sha256: String,
        externalSynced: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.trigger = trigger
        self.isEncrypted = isEncrypted
        self.isPinned = isPinned
        self.transactionCount = transactionCount
        self.categoryCount = categoryCount
        self.petCount = petCount
        self.byteSize = byteSize
        self.sha256 = sha256
        self.externalSynced = externalSynced
    }
}

public enum AutoBackupFrequency: String, Codable, Sendable, CaseIterable, Hashable {
    case off = "OFF"
    case every6Hours = "EVERY_6_HOURS"
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case onBackgroundIfDirty = "ON_BACKGROUND_DIRTY"

    public var zhLabel: String {
        switch self {
        case .off: return "关闭自动备份"
        case .every6Hours: return "每 6 小时"
        case .daily: return "每日定时"
        case .weekly: return "每周定时"
        case .onBackgroundIfDirty: return "数据变更退至后台即备"
        }
    }

    public var enLabel: String {
        switch self {
        case .off: return "Off"
        case .every6Hours: return "Every 6 Hours"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .onBackgroundIfDirty: return "On Background When Changed"
        }
    }

    public var intervalSeconds: TimeInterval? {
        switch self {
        case .off, .onBackgroundIfDirty: return nil
        case .every6Hours: return 6 * 3600
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }
}

public struct BackupScheduleConfig: Codable, Sendable, Hashable {
    public var frequency: AutoBackupFrequency
    public var preferredHour: Int
    public var maxRetainedAutoBackups: Int
    public var encryptAutoBackups: Bool
    public var includeCustomPetMediaInManualFullExport: Bool
    public var externalFolderDisplayName: String?
    public var externalFolderBookmarkBase64: String?
    public var lastBackupAt: Int64?
    public var lastBackupStatus: String?
    public var lastDirtyMutationAt: Int64?

    public init(
        frequency: AutoBackupFrequency = .daily,
        preferredHour: Int = 2,
        maxRetainedAutoBackups: Int = 14,
        encryptAutoBackups: Bool = false,
        includeCustomPetMediaInManualFullExport: Bool = true,
        externalFolderDisplayName: String? = nil,
        externalFolderBookmarkBase64: String? = nil,
        lastBackupAt: Int64? = nil,
        lastBackupStatus: String? = nil,
        lastDirtyMutationAt: Int64? = nil
    ) {
        self.frequency = frequency
        self.preferredHour = min(23, max(0, preferredHour))
        self.maxRetainedAutoBackups = min(100, max(1, maxRetainedAutoBackups))
        self.encryptAutoBackups = encryptAutoBackups
        self.includeCustomPetMediaInManualFullExport = includeCustomPetMediaInManualFullExport
        self.externalFolderDisplayName = externalFolderDisplayName
        self.externalFolderBookmarkBase64 = externalFolderBookmarkBase64
        self.lastBackupAt = lastBackupAt
        self.lastBackupStatus = lastBackupStatus
        self.lastDirtyMutationAt = lastDirtyMutationAt
    }
}

public enum ImportSourceFormat: String, Codable, Sendable, Hashable {
    case pickbankArchiveV2 = "PickBank 完整备份 (.pickbank.json)"
    case pickbankEncrypted = "PickBank 加密备份 (.enc.json)"
    case androidMigrationJson = "Android Pickbank 迁移包 (.json)"
    case pickbankXlsx = "PickBank Excel 工作簿 (.xlsx)"
    case wechatPayCsv = "微信支付账单 (.csv)"
    case alipayCsv = "支付宝账单 (.csv)"
    case genericCsv = "通用 CSV 账单 (.csv)"
}

public enum ImportExecutionMode: String, Codable, Sendable, CaseIterable, Hashable {
    case smartMerge = "SMART_MERGE"
    case cleanReplace = "CLEAN_REPLACE"
}

public struct ImportPreviewReport: Sendable, Hashable {
    public var sourceName: String
    public var detectedFormat: ImportSourceFormat
    public var checksumVerified: Bool
    public var incomingTransactions: [TransactionRecord]
    public var incomingCategories: [CategoryRecord]
    public var incomingBudgets: [BudgetRecord]
    public var incomingCategoryLimits: [CategoryMonthlyLimitRecord]
    public var incomingRecurringRules: [RecurringRuleRecord]
    public var incomingWallets: [WalletAccount]
    public var incomingTags: [TagRecord]
    public var incomingPetState: PetStateBundle?
    public var incomingPreferences: AppPreferences?
    public var duplicateCount: Int
    public var netNewCount: Int
    public var warnings: [String]
}

public struct ImportExecutionResult: Sendable, Hashable {
    public var importedTransactions: Int
    public var skippedDuplicates: Int
    public var importedCategories: Int
    public var restoredPetModule: Bool
    public var safetySnapshotMetadata: BackupSnapshotMetadata?
}

public struct DuplicateTransactionGroup: Identifiable, Sendable, Hashable {
    public var id: String { primary.id }
    public var primary: TransactionRecord
    public var duplicates: [TransactionRecord]
}

public struct LocalStorageBreakdown: Sendable, Hashable {
    public var ledgerDatabaseBytes: Int64
    public var autoBackupsBytes: Int64
    public var manualAndSafetySnapshotsBytes: Int64
    public var customPetMediaBytes: Int64
    public var tempExportsBytes: Int64

    public init(
        ledgerDatabaseBytes: Int64 = 0,
        autoBackupsBytes: Int64 = 0,
        manualAndSafetySnapshotsBytes: Int64 = 0,
        customPetMediaBytes: Int64 = 0,
        tempExportsBytes: Int64 = 0
    ) {
        self.ledgerDatabaseBytes = ledgerDatabaseBytes
        self.autoBackupsBytes = autoBackupsBytes
        self.manualAndSafetySnapshotsBytes = manualAndSafetySnapshotsBytes
        self.customPetMediaBytes = customPetMediaBytes
        self.tempExportsBytes = tempExportsBytes
    }

    public var totalBytes: Int64 {
        ledgerDatabaseBytes + autoBackupsBytes + manualAndSafetySnapshotsBytes + customPetMediaBytes + tempExportsBytes
    }
}

public struct IntegrityReport: Sendable, Hashable {
    public var totalTransactions: Int
    public var repairedCategorySnapshots: Int
    public var relinkedCategoryIds: Int
    public var cleanedOrphanTagRefs: Int
    public var fixedSortOrders: Int
    public var timestamp: Int64
}
