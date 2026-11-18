import Foundation

public struct ParsedLedgerEntry: Sendable, Hashable, Identifiable {
    public var id: String { "\(createdAt)-\(amountCents)-\(categoryName)-\(note ?? "")" }
    public var amountCents: Int64
    public var categoryName: String
    public var type: TransactionType
    public var walletName: String?
    public var tagNames: [String]
    public var note: String?
    public var rawInput: String
    public var createdAt: Int64

    public init(
        amountCents: Int64,
        categoryName: String,
        type: TransactionType,
        walletName: String? = nil,
        tagNames: [String] = [],
        note: String? = nil,
        rawInput: String,
        createdAt: Int64
    ) {
        self.amountCents = amountCents
        self.categoryName = categoryName
        self.type = type
        self.walletName = walletName
        self.tagNames = tagNames
        self.note = note
        self.rawInput = rawInput
        self.createdAt = createdAt
    }
}

public struct NlpParseEngine: Sendable {
    private static let categoryKeywords: [(String, TransactionType, [String])] = [
        // Expense categories (matching Android Pickbank + English equivalents)
        ("餐饮", .expense, ["饭", "餐", "吃", "外卖", "早餐", "午餐", "晚餐", "早饭", "午饭", "晚饭", "夜宵", "零食", "奶茶", "咖啡", "火锅", "烧烤", "食堂", "拉面", "面包", "水果", "饮料", "coffee", "lunch", "dinner", "breakfast", "food", "meal"]),
        ("交通", .expense, ["打车", "出租", "滴滴", "地铁", "公交", "高铁", "火车", "机票", "飞机", "油费", "加油", "停车", "过路费", "骑车", "单车", "uber", "taxi", "metro", "subway", "bus", "flight"]),
        ("购物", .expense, ["买", "购", "淘宝", "京东", "拼多多", "超市", "商场", "衣服", "鞋", "包", "数码", "电子", "日用", "amazon", "shop", "shopping"]),
        ("住房", .expense, ["房租", "租金", "水电", "物业", "暖气", "燃气", "网费", "宽带", "话费", "rent", "utility", "utilities"]),
        ("娱乐", .expense, ["电影", "游戏", "KTV", "旅游", "门票", "演唱会", "酒吧", "健身", "会员", "netflix", "game", "movie", "gym"]),
        ("医疗", .expense, ["医院", "药", "看病", "体检", "挂号", "手术", "牙科", "pharmacy", "doctor", "medical"]),
        ("教育", .expense, ["学费", "书", "培训", "课程", "考试", "学习", "文具", "book", "course", "tuition"]),
        // Income categories
        ("工资", .income, ["工资", "薪水", "薪资", "月薪", "发工资", "奖金", "年终奖", "salary", "payroll", "bonus"]),
        ("兼职", .income, ["兼职", "外快", "副业", "接单", "freelance"]),
        ("投资", .income, ["利息", "分红", "收益", "理财", "股票", "基金", "dividend", "interest"]),
        ("红包", .income, ["红包", "转账收", "收到", "报销", "退款", "refund", "reimburse"]),
        // Transfer
        ("转账", .transfer, ["转账给", "转入", "转出", "还信用卡", "transfer"])
    ]

    private static let walletKeywords: [(String, [String])] = [
        ("微信", ["微信", "wechat", "wx"]),
        ("支付宝", ["支付宝", "alipay", "花呗"]),
        ("银行卡", ["银行卡", "招行", "工行", "建行", "农行", "中行", "储蓄卡"]),
        ("信用卡", ["信用卡", "credit"]),
        ("现金", ["现金", "cash"])
    ]

    private static let chineseDigits: [Character: Int64] = [
        "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
    ]

    public init() {}

    public func parse(
        _ input: String,
        referenceDate: Date = Date(),
        customCategories: [CategoryRecord] = []
    ) -> ParsedLedgerEntry? {
        let baseDate = inferDate(from: input, referenceDate: referenceDate)
        return parseSingle(input, timestampMs: PickBankClock.ms(from: baseDate), customCategories: customCategories)
    }

    public func parseMany(
        _ input: String,
        referenceDate: Date = Date(),
        customCategories: [CategoryRecord] = []
    ) -> [ParsedLedgerEntry] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let baseTimestamp = PickBankClock.ms(from: inferDate(from: trimmed, referenceDate: referenceDate))
        let segments = splitSegments(trimmed)
        let parsed = segments.compactMap { seg -> ParsedLedgerEntry? in
            let segDate = inferDate(from: seg, referenceDate: referenceDate, defaultDate: PickBankClock.date(fromMs: baseTimestamp))
            return parseSingle(seg, timestampMs: PickBankClock.ms(from: segDate), customCategories: customCategories)
        }
        if !parsed.isEmpty { return parsed }
        if let single = parseSingle(trimmed, timestampMs: baseTimestamp, customCategories: customCategories) {
            return [single]
        }
        return []
    }

    private func splitSegments(_ text: String) -> [String] {
        // Split on punctuation (excluding decimal points between digits), newlines, or conjunctions
        let pattern = #"[，,；;。!！\n]+|(?<!\d)\.(?!\d)|然后|还买了|以及|\s+又\s*|\band\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var results: [String] = []
        var cursor = text.startIndex
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let range = Range(match.range, in: text) else { return }
            let part = String(text[cursor..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { results.append(part) }
            cursor = range.upperBound
        }
        let tail = String(text[cursor..<text.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { results.append(tail) }
        return results.isEmpty ? [text] : results
    }

    private func parseSingle(
        _ rawSegment: String,
        timestampMs: Int64,
        customCategories: [CategoryRecord]
    ) -> ParsedLedgerEntry? {
        let trimmed = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let (amountCents, matchedAmountText) = extractAmountCents(from: trimmed)
        guard let cents = amountCents, cents > 0 else { return nil }

        // 1. Match user-defined custom categories first if their exact name appears in text
        var resolvedCategory: String?
        var resolvedType: TransactionType = .expense

        for cat in customCategories where !cat.isArchived {
            if trimmed.localizedCaseInsensitiveContains(cat.name) {
                resolvedCategory = cat.name
                resolvedType = (cat.type == .income) ? .income : .expense
                break
            }
        }

        // 2. Built-in keyword matching
        if resolvedCategory == nil {
            for (name, txType, keywords) in Self.categoryKeywords {
                if keywords.contains(where: { lower.contains($0.lowercased()) }) {
                    resolvedCategory = name
                    resolvedType = txType
                    break
                }
            }
        }

        // 3. Explicit income/expense hints override default
        if resolvedCategory == nil {
            if lower.contains("收入") || lower.contains("进账") || lower.contains("earned") || lower.contains("income") {
                resolvedType = .income
                resolvedCategory = "其他"
            } else {
                resolvedCategory = "其他"
            }
        }

        // 4. Optional wallet detection
        var walletName: String?
        for (name, keywords) in Self.walletKeywords {
            if keywords.contains(where: { lower.contains($0.lowercased()) }) {
                walletName = name
                break
            }
        }

        // 5. Extract #tags and clean note text
        var tagNames: [String] = []
        var note = trimmed
        if let tagRegex = try? NSRegularExpression(pattern: #"#([A-Za-z0-9_\u4e00-\u9fa5]{1,16})"#) {
            let matches = tagRegex.matches(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed))
            for m in matches {
                if let tagRange = Range(m.range(at: 1), in: trimmed) {
                    let tag = String(trimmed[tagRange])
                    if !tagNames.contains(tag) { tagNames.append(tag) }
                }
            }
            note = tagRegex.stringByReplacingMatches(in: note, range: NSRange(note.startIndex..<note.endIndex, in: note), withTemplate: "")
        }
        if let amt = matchedAmountText {
            note = note.replacingOccurrences(of: amt, with: "")
        }
        let stripTokens = ["大前天", "前天", "昨天", "今天", "早上", "上午", "中午", "下午", "晚上", "刚刚", "刚才", "yesterday", "today", "花了", "用了", "人民币", "rmb", "RMB", "块钱", "元", "块"]
        for tok in stripTokens {
            note = note.replacingOccurrences(of: tok, with: "")
        }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedLedgerEntry(
            amountCents: cents,
            categoryName: resolvedCategory ?? "其他",
            type: resolvedType,
            walletName: walletName,
            tagNames: tagNames,
            note: cleanNote.isEmpty ? nil : cleanNote,
            rawInput: trimmed,
            createdAt: timestampMs
        )
    }

    private func extractAmountCents(from text: String) -> (Int64?, String?) {
        let arabicPattern = #"(\d+(?:\.\d{1,2})?)\s*(?:块钱|元|块|rmb|RMB|¥|￥)?"#
        if let regex = try? NSRegularExpression(pattern: arabicPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let fullRange = Range(match.range(at: 0), in: text),
           let numRange = Range(match.range(at: 1), in: text),
           let value = Double(text[numRange]), value > 0 {
            let cents = Int64((value * 100.0).rounded())
            return (cents, String(text[fullRange]))
        }

        let cnPattern = #"([零一二两三四五六七八九十百千万点]+)\s*(?:块钱|元|块)"#
        if let regex = try? NSRegularExpression(pattern: cnPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let fullRange = Range(match.range(at: 0), in: text),
           let numRange = Range(match.range(at: 1), in: text),
           let value = chineseNumberToDouble(String(text[numRange])), value > 0 {
            let cents = Int64((value * 100.0).rounded())
            return (cents, String(text[fullRange]))
        }
        return (nil, nil)
    }

    private func inferDate(
        from input: String,
        referenceDate: Date,
        defaultDate: Date? = nil
    ) -> Date {
        let calendar = Calendar.current
        var base = defaultDate ?? referenceDate
        var hasExplicitDay = false

        let lower = input.lowercased()
        if input.contains("大前天") {
            base = calendar.date(byAdding: .day, value: -3, to: referenceDate) ?? referenceDate
            hasExplicitDay = true
        } else if input.contains("前天") {
            base = calendar.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate
            hasExplicitDay = true
        } else if input.contains("昨天") || lower.contains("yesterday") {
            base = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            hasExplicitDay = true
        } else if input.contains("今天") || lower.contains("today") {
            base = referenceDate
            hasExplicitDay = true
        }

        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
        if input.contains("早上") || input.contains("上午") || lower.contains("morning") {
            comps.hour = 9; comps.minute = 0; comps.second = 0
        } else if input.contains("中午") || lower.contains("noon") {
            comps.hour = 12; comps.minute = 0; comps.second = 0
        } else if input.contains("下午") || lower.contains("afternoon") {
            comps.hour = 15; comps.minute = 0; comps.second = 0
        } else if input.contains("晚上") || input.contains("晚饭") || input.contains("夜宵") || lower.contains("dinner") {
            comps.hour = 19; comps.minute = 0; comps.second = 0
        } else if hasExplicitDay && defaultDate == nil {
            comps.hour = 12; comps.minute = 0; comps.second = 0
        }
        return calendar.date(from: comps) ?? base
    }

    private func chineseNumberToDouble(_ raw: String) -> Double? {
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "点", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = chineseIntegerToLong(String(parts[0]))
        var decimal = 0.0
        if parts.count > 1 {
            let digits = parts[1].compactMap { Self.chineseDigits[$0] }.map(String.init).joined()
            if !digits.isEmpty, let d = Double("0.\(digits)") {
                decimal = d
            }
        }
        return Double(integer) + decimal
    }

    private func chineseIntegerToLong(_ raw: String) -> Int64 {
        guard !raw.isEmpty else { return 0 }
        var result: Int64 = 0
        var section: Int64 = 0
        var number: Int64 = 0
        for ch in raw {
            switch ch {
            case "万":
                section = max(1, section + number) * 10_000
                result += section
                section = 0
                number = 0
            case "千":
                section += (number > 0 ? number : 1) * 1_000
                number = 0
            case "百":
                section += (number > 0 ? number : 1) * 100
                number = 0
            case "十":
                section += (number > 0 ? number : 1) * 10
                number = 0
            default:
                if let digit = Self.chineseDigits[ch] {
                    number = digit
                }
            }
        }
        return result + section + number
    }
}
