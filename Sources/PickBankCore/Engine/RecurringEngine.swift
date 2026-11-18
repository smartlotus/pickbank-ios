import Foundation

public enum RecurringEngine {
    public static func nextRunDate(from date: Date, period: RecurringPeriod, calendar: Calendar = .current) -> Date {
        switch period {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86_400)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86_400)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date.addingTimeInterval(365 * 86_400)
        }
    }

    public static func evaluateDueRules(
        rules: [RecurringRuleRecord],
        asOf nowMs: Int64 = PickBankClock.nowMs(),
        categoriesById: [String: CategoryRecord],
        calendar: Calendar = .current
    ) -> (generatedTransactions: [TransactionRecord], updatedRules: [RecurringRuleRecord]) {
        var newTransactions: [TransactionRecord] = []
        var updatedRules: [RecurringRuleRecord] = []

        for var rule in rules {
            guard rule.isActive else {
                updatedRules.append(rule)
                continue
            }
            var runAt = rule.nextRunAt
            var safetyCounter = 0
            while runAt <= nowMs && safetyCounter < 120 {
                safetyCounter += 1
                let categoryName = rule.categoryId.flatMap { categoriesById[$0]?.name } ?? "未分类"
                let tx = TransactionRecord(
                    amountCents: rule.amountCents,
                    type: rule.type,
                    categoryId: rule.categoryId,
                    categoryNameSnapshot: categoryName,
                    walletId: rule.walletId,
                    note: rule.note ?? "固定账单",
                    rawInput: "固定账单自动入账",
                    createdAt: runAt,
                    updatedAt: nowMs
                )
                newTransactions.append(tx)
                let nextDate = nextRunDate(from: PickBankClock.date(fromMs: runAt), period: rule.period, calendar: calendar)
                runAt = PickBankClock.ms(from: nextDate)
            }
            if runAt != rule.nextRunAt {
                rule.nextRunAt = runAt
                rule.updatedAt = nowMs
            }
            updatedRules.append(rule)
        }

        return (newTransactions, updatedRules)
    }
}
