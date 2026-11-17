import Foundation

public enum TransactionType: Int, Codable, Sendable, CaseIterable, Hashable {
    case expense = 0
    case income = 1
    case transfer = 2

    public var zhLabel: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        }
    }

    public var enLabel: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }
}

public enum CategoryKind: Int, Codable, Sendable, CaseIterable, Hashable {
    case expense = 0
    case income = 1
}

public struct CategoryRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var icon: String
    public var type: CategoryKind
    public var sortOrder: Int
    public var isDefault: Bool
    public var isArchived: Bool
    public var colorHex: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String,
        type: CategoryKind,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        isArchived: Bool = false,
        colorHex: String? = nil,
        createdAt: Int64 = PickBankClock.nowMs(),
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.type = type
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.isArchived = isArchived
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WalletAccount: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var icon: String
    public var initialBalanceCents: Int64
    public var isDefault: Bool
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        icon: String,
        initialBalanceCents: Int64 = 0,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.initialBalanceCents = initialBalanceCents
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }
}

public struct TagRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var colorHex: String?

    public init(id: String = UUID().uuidString, name: String, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

public struct TransactionRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    /// Integer cents (e.g. ¥35.00 == 3500) to eliminate floating-point drift.
    public var amountCents: Int64
    public var type: TransactionType
    public var categoryId: String?
    /// Permanent category name snapshot stamped at write time so history survives category deletion.
    public var categoryNameSnapshot: String
    public var walletId: String?
    public var note: String?
    public var rawInput: String?
    public var tagIds: [String]
    public var isDemo: Bool
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: String = UUID().uuidString,
        amountCents: Int64,
        type: TransactionType,
        categoryId: String? = nil,
        categoryNameSnapshot: String = "未分类",
        walletId: String? = nil,
        note: String? = nil,
        rawInput: String? = nil,
        tagIds: [String] = [],
        isDemo: Bool = false,
        createdAt: Int64 = PickBankClock.nowMs(),
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.id = id
        self.amountCents = abs(amountCents)
        self.type = type
        self.categoryId = categoryId
        self.categoryNameSnapshot = categoryNameSnapshot
        self.walletId = walletId
        self.note = note
        self.rawInput = rawInput
        self.tagIds = tagIds
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func resolvedCategoryName(categoriesById: [String: CategoryRecord]) -> String {
        if let categoryId, let cat = categoriesById[categoryId], !cat.name.isEmpty {
            return cat.name
        }
        if !categoryNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return categoryNameSnapshot
        }
        return "未分类"
    }
}

public enum BudgetPeriodType: String, Codable, Sendable, CaseIterable, Hashable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"
    case custom = "CUSTOM"
    case nextDay = "NEXT_DAY"
    case nextWeek = "NEXT_WEEK"
    case nextMonth = "NEXT_MONTH"
}

public struct BudgetRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var amountCents: Int64
    public var periodType: BudgetPeriodType
    public var customDays: Int
    public var timeKey: String
    public var startMs: Int64?
    public var endMs: Int64?
    public var categoryId: String?

    public init(
        id: String = UUID().uuidString,
        amountCents: Int64,
        periodType: BudgetPeriodType,
        customDays: Int = 0,
        timeKey: String,
        startMs: Int64? = nil,
        endMs: Int64? = nil,
        categoryId: String? = nil
    ) {
        self.id = id
        self.amountCents = amountCents
        self.periodType = periodType
        self.customDays = customDays
        self.timeKey = timeKey
        self.startMs = startMs
        self.endMs = endMs
        self.categoryId = categoryId
    }
}

public struct CategoryMonthlyLimitRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String { categoryId }
    public var categoryId: String
    public var monthlyLimitCents: Int64
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        categoryId: String,
        monthlyLimitCents: Int64,
        createdAt: Int64 = PickBankClock.nowMs(),
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.categoryId = categoryId
        self.monthlyLimitCents = monthlyLimitCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum RecurringPeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"
}

public struct RecurringRuleRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var amountCents: Int64
    public var type: TransactionType
    public var categoryId: String?
    public var walletId: String?
    public var note: String?
    public var period: RecurringPeriod
    public var nextRunAt: Int64
    public var isActive: Bool
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: String = UUID().uuidString,
        amountCents: Int64,
        type: TransactionType,
        categoryId: String? = nil,
        walletId: String? = nil,
        note: String? = nil,
        period: RecurringPeriod = .monthly,
        nextRunAt: Int64 = PickBankClock.nowMs(),
        isActive: Bool = true,
        createdAt: Int64 = PickBankClock.nowMs(),
        updatedAt: Int64 = PickBankClock.nowMs()
    ) {
        self.id = id
        self.amountCents = amountCents
        self.type = type
        self.categoryId = categoryId
        self.walletId = walletId
        self.note = note
        self.period = period
        self.nextRunAt = nextRunAt
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PickBankClock {
    public static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    public static func date(fromMs ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }

    public static func ms(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    }

    public static func dateKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }

    public static func parseDateKey(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
