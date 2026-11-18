import Foundation

public enum SummaryTimePeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case day = "DAY"
    case week = "WEEK"
    case month = "MONTH"
    case year = "YEAR"
    case custom = "CUSTOM"

    public var zhLabel: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        case .custom: return "自定义"
        }
    }

    public var enLabel: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .custom: return "Custom"
        }
    }
}

public struct CategoryShareItem: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public var name: String
    public var amountCents: Int64
    public var percentage: Double
}

public struct SummaryBucketPoint: Identifiable, Sendable, Hashable {
    public var id: Int { index }
    public var index: Int
    public var label: String
    public var startMs: Int64
    public var endMs: Int64
    public var expenseCents: Int64
    public var incomeCents: Int64
}

public struct SummaryReport: Sendable, Hashable {
    public var period: SummaryTimePeriod
    public var rangeStartMs: Int64
    public var rangeEndMs: Int64
    public var rangeLabel: String
    public var previousRangeLabel: String
    public var totalExpenseCents: Int64
    public var totalIncomeCents: Int64
    public var previousExpenseCents: Int64
    public var previousIncomeCents: Int64
    public var expenseShares: [CategoryShareItem]
    public var incomeShares: [CategoryShareItem]
    public var buckets: [SummaryBucketPoint]
    public var periodTransactions: [TransactionRecord]
}

public enum SummaryAnalyticsEngine {
    public static func rangeBounds(
        period: SummaryTimePeriod,
        anchorDate: Date,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date, prevStart: Date, prevEnd: Date) {
        switch period {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let prevStart = calendar.date(byAdding: .day, value: -1, to: start)!
            return (start, end, prevStart, start)
        case .week:
            var cal = calendar
            cal.firstWeekday = 2 // Monday start matching Chinese/ISO calendar
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchorDate)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: anchorDate)
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            let prevStart = cal.date(byAdding: .day, value: -7, to: start)!
            return (start, end, prevStart, start)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: anchorDate)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            let prevStart = calendar.date(byAdding: .month, value: -1, to: start)!
            return (start, end, prevStart, start)
        case .year:
            let comps = calendar.dateComponents([.year], from: anchorDate)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            let prevStart = calendar.date(byAdding: .year, value: -1, to: start)!
            return (start, end, prevStart, start)
        case .custom:
            let rawStart = customStart ?? anchorDate
            let rawEnd = customEnd ?? anchorDate
            let start = calendar.startOfDay(for: min(rawStart, rawEnd))
            let endDayStart = calendar.startOfDay(for: max(rawStart, rawEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: endDayStart)!
            let span = max(86_400, end.timeIntervalSince(start))
            let prevEnd = start
            let prevStart = start.addingTimeInterval(-span)
            return (start, end, prevStart, prevEnd)
        }
    }

    public static func shiftAnchor(
        _ anchorDate: Date,
        period: SummaryTimePeriod,
        direction: Int,
        calendar: Calendar = .current
    ) -> Date {
        switch period {
        case .day:
            return calendar.date(byAdding: .day, value: direction, to: anchorDate) ?? anchorDate
        case .week:
            return calendar.date(byAdding: .day, value: direction * 7, to: anchorDate) ?? anchorDate
        case .month:
            return calendar.date(byAdding: .month, value: direction, to: anchorDate) ?? anchorDate
        case .year:
            return calendar.date(byAdding: .year, value: direction, to: anchorDate) ?? anchorDate
        case .custom:
            return anchorDate
        }
    }

    public static func buildReport(
        transactions: [TransactionRecord],
        categoriesById: [String: CategoryRecord],
        period: SummaryTimePeriod,
        anchorDate: Date,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> SummaryReport {
        let bounds = rangeBounds(
            period: period,
            anchorDate: anchorDate,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar
        )
        let startMs = PickBankClock.ms(from: bounds.start)
        let endMs = PickBankClock.ms(from: bounds.end)
        let prevStartMs = PickBankClock.ms(from: bounds.prevStart)
        let prevEndMs = PickBankClock.ms(from: bounds.prevEnd)

        let currentTxs = transactions
            .filter { $0.createdAt >= startMs && $0.createdAt < endMs }
            .sorted { $0.createdAt > $1.createdAt }
        let prevTxs = transactions.filter { $0.createdAt >= prevStartMs && $0.createdAt < prevEndMs }

        let totalExpense = currentTxs.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let totalIncome = currentTxs.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }
        let prevExpense = prevTxs.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let prevIncome = prevTxs.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }

        let expenseShares = computeShares(txs: currentTxs, kind: .expense, total: totalExpense, categoriesById: categoriesById)
        let incomeShares = computeShares(txs: currentTxs, kind: .income, total: totalIncome, categoriesById: categoriesById)
        let buckets = buildBuckets(
            transactions: currentTxs,
            period: period,
            start: bounds.start,
            end: bounds.end,
            calendar: calendar
        )

        return SummaryReport(
            period: period,
            rangeStartMs: startMs,
            rangeEndMs: endMs,
            rangeLabel: formatRangeLabel(period: period, start: bounds.start, end: bounds.end),
            previousRangeLabel: formatRangeLabel(period: period, start: bounds.prevStart, end: bounds.prevEnd),
            totalExpenseCents: totalExpense,
            totalIncomeCents: totalIncome,
            previousExpenseCents: prevExpense,
            previousIncomeCents: prevIncome,
            expenseShares: expenseShares,
            incomeShares: incomeShares,
            buckets: buckets,
            periodTransactions: currentTxs
        )
    }

    public static func last7DaysExpenses(
        transactions: [TransactionRecord],
        asOf referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int64] {
        let todayStart = calendar.startOfDay(for: referenceDate)
        return (0..<7).map { offset in
            let dayOffset = offset - 6
            let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: todayStart)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let sMs = PickBankClock.ms(from: dayStart)
            let eMs = PickBankClock.ms(from: dayEnd)
            return transactions
                .filter { $0.type == .expense && $0.createdAt >= sMs && $0.createdAt < eMs }
                .reduce(0) { $0 + $1.amountCents }
        }
    }

    private static func computeShares(
        txs: [TransactionRecord],
        kind: TransactionType,
        total: Int64,
        categoriesById: [String: CategoryRecord]
    ) -> [CategoryShareItem] {
        var sums: [String: Int64] = [:]
        for tx in txs where tx.type == kind {
            let name = tx.resolvedCategoryName(categoriesById: categoriesById)
            sums[name, default: 0] += tx.amountCents
        }
        return sums.map { (name, cents) in
            CategoryShareItem(
                name: name,
                amountCents: cents,
                percentage: total > 0 ? Double(cents) / Double(total) : 0.0
            )
        }.sorted { $0.amountCents > $1.amountCents }
    }

    private static func buildBuckets(
        transactions: [TransactionRecord],
        period: SummaryTimePeriod,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [SummaryBucketPoint] {
        switch period {
        case .day:
            // 4-hour intervals (6 buckets)
            return (0..<6).map { idx in
                let bStart = calendar.date(byAdding: .hour, value: idx * 4, to: start)!
                let bEnd = calendar.date(byAdding: .hour, value: (idx + 1) * 4, to: start)!
                return bucketPoint(index: idx, label: String(format: "%02d:00", idx * 4), start: bStart, end: bEnd, txs: transactions)
            }
        case .week:
            let labels = ["一", "二", "三", "四", "五", "六", "日"]
            return (0..<7).map { idx in
                let bStart = calendar.date(byAdding: .day, value: idx, to: start)!
                let bEnd = calendar.date(byAdding: .day, value: 1, to: bStart)!
                return bucketPoint(index: idx, label: labels[idx], start: bStart, end: bEnd, txs: transactions)
            }
        case .month:
            let daysCount = max(28, calendar.dateComponents([.day], from: start, to: end).day ?? 30)
            return (0..<daysCount).map { idx in
                let bStart = calendar.date(byAdding: .day, value: idx, to: start)!
                let bEnd = calendar.date(byAdding: .day, value: 1, to: bStart)!
                let dayNum = calendar.component(.day, from: bStart)
                return bucketPoint(index: idx, label: "\(dayNum)", start: bStart, end: bEnd, txs: transactions)
            }
        case .year:
            return (0..<12).map { idx in
                let bStart = calendar.date(byAdding: .month, value: idx, to: start)!
                let bEnd = calendar.date(byAdding: .month, value: 1, to: bStart)!
                return bucketPoint(index: idx, label: "\(idx + 1)月", start: bStart, end: bEnd, txs: transactions)
            }
        case .custom:
            let totalDays = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
            let count = min(totalDays, 31)
            let stepHours = max(24, (totalDays * 24) / count)
            let df = DateFormatter()
            df.dateFormat = "M/d"
            return (0..<count).map { idx in
                let bStart = calendar.date(byAdding: .hour, value: idx * stepHours, to: start)!
                let bEnd = idx == count - 1 ? end : min(end, calendar.date(byAdding: .hour, value: (idx + 1) * stepHours, to: start)!)
                return bucketPoint(index: idx, label: df.string(from: bStart), start: bStart, end: bEnd, txs: transactions)
            }
        }
    }

    private static func bucketPoint(
        index: Int,
        label: String,
        start: Date,
        end: Date,
        txs: [TransactionRecord]
    ) -> SummaryBucketPoint {
        let sMs = PickBankClock.ms(from: start)
        let eMs = PickBankClock.ms(from: end)
        let slice = txs.filter { $0.createdAt >= sMs && $0.createdAt < eMs }
        let exp = slice.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let inc = slice.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }
        return SummaryBucketPoint(index: index, label: label, startMs: sMs, endMs: eMs, expenseCents: exp, incomeCents: inc)
    }

    private static func formatRangeLabel(period: SummaryTimePeriod, start: Date, end: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        switch period {
        case .day:
            df.dateFormat = "yyyy年M月d日"
            return df.string(from: start)
        case .week:
            df.dateFormat = "M月d日"
            let inclusiveEnd = end.addingTimeInterval(-1)
            return "\(df.string(from: start)) – \(df.string(from: inclusiveEnd))"
        case .month:
            df.dateFormat = "yyyy年M月"
            return df.string(from: start)
        case .year:
            df.dateFormat = "yyyy年"
            return df.string(from: start)
        case .custom:
            df.dateFormat = "yyyy/M/d"
            let inclusiveEnd = end.addingTimeInterval(-1)
            return "\(df.string(from: start)) – \(df.string(from: inclusiveEnd))"
        }
    }
}

public enum CategoryLimitEngine {
    public static func computeProgresses(
        limits: [CategoryMonthlyLimitRecord],
        categoriesById: [String: CategoryRecord],
        transactions: [TransactionRecord],
        monthAnchor: Date = Date(),
        calendar: Calendar = .current
    ) -> [CategoryLimitProgress] {
        let bounds = SummaryAnalyticsEngine.rangeBounds(period: .month, anchorDate: monthAnchor, calendar: calendar)
        let sMs = PickBankClock.ms(from: bounds.start)
        let eMs = PickBankClock.ms(from: bounds.end)

        var spentByCatId: [String: Int64] = [:]
        for tx in transactions where tx.type == .expense && tx.createdAt >= sMs && tx.createdAt < eMs {
            if let cid = tx.categoryId {
                spentByCatId[cid, default: 0] += tx.amountCents
            }
        }

        return limits.compactMap { lim in
            guard let cat = categoriesById[lim.categoryId] else { return nil }
            return CategoryLimitProgress(
                category: cat,
                monthlyLimitCents: lim.monthlyLimitCents,
                usedCents: spentByCatId[lim.categoryId] ?? 0
            )
        }
        .sorted { $0.ratio > $1.ratio }
    }
}
