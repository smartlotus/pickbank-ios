import Foundation

public enum AiClientError: LocalizedError, Sendable {
    case missingApiKey
    case invalidEndpoint
    case httpError(Int, String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingApiKey: return "尚未配置 API Key，已为您切换本地离线智能分析。"
        case .invalidEndpoint: return "AI 接口地址格式无效，请检查 Base URL。"
        case .httpError(let code, let detail): return "AI 服务响应异常 (HTTP \(code))：\(detail)"
        case .emptyResponse: return "AI 返回内容为空，请稍后重试。"
        }
    }
}

public struct OpenAICompatibleClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func testConnection(baseUrl: String, modelId: String, apiKey: String) async throws -> String {
        return try await chat(
            baseUrl: baseUrl,
            modelId: modelId,
            apiKey: apiKey,
            systemPrompt: "You are a connectivity test assistant.",
            userPrompt: "Reply with exactly: PickBank AI Ready."
        )
    }

    public func chat(
        baseUrl: String,
        modelId: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AiClientError.missingApiKey }

        var cleanBase = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleanBase.hasSuffix("/") { cleanBase.removeLast() }
        let endpointString = cleanBase.hasSuffix("/chat/completions")
            ? cleanBase
            : (cleanBase.hasSuffix("/v1") ? "\(cleanBase)/chat/completions" : "\(cleanBase)/v1/chat/completions")

        guard let url = URL(string: endpointString) else { throw AiClientError.invalidEndpoint }

        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable { let model: String; let messages: [Msg]; let temperature: Double }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Req(
            model: modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "deepseek-chat" : modelId,
            messages: [
                Msg(role: "system", content: systemPrompt),
                Msg(role: "user", content: userPrompt)
            ],
            temperature: 0.4
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AiClientError.invalidEndpoint
        }
        guard (200...299).contains(http.statusCode) else {
            let errText = String(data: data.prefix(300), encoding: .utf8) ?? "Unknown error"
            throw AiClientError.httpError(http.statusCode, errText)
        }

        struct Resp: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AiClientError.emptyResponse
        }
        return content
    }

    public static func buildLedgerContextPrompt(report: SummaryReport, question: String?) -> String {
        let expStr = MoneyFormatter.formatYuan(cents: report.totalExpenseCents)
        let incStr = MoneyFormatter.formatYuan(cents: report.totalIncomeCents)
        let topCats = report.expenseShares.prefix(5).map { share in
            let pct = Int((share.percentage * 100).rounded())
            return "• \(share.name): \(MoneyFormatter.formatYuan(cents: share.amountCents)) (\(pct)%)"
        }.joined(separator: "\n")

        let recentSample = report.periodTransactions.prefix(20).map { tx in
            let df = DateFormatter()
            df.dateFormat = "MM-dd HH:mm"
            let d = df.string(from: PickBankClock.date(fromMs: tx.createdAt))
            return "[\(d)] \(tx.type.zhLabel) \(tx.categoryNameSnapshot) \(MoneyFormatter.formatYuan(cents: tx.amountCents)) \(tx.note ?? "")"
        }.joined(separator: "\n")

        return """
        统计周期：\(report.rangeLabel)
        总支出：\(expStr)（上周期：\(MoneyFormatter.formatYuan(cents: report.previousExpenseCents))）
        总收入：\(incStr)（上周期：\(MoneyFormatter.formatYuan(cents: report.previousIncomeCents))）
        主要支出分类：
        \(topCats.isEmpty ? "暂无支出" : topCats)

        近期代表账目（最多20笔）：
        \(recentSample.isEmpty ? "暂无记录" : recentSample)

        \(question.map { "用户提问：\($0)" } ?? "请输出简明清晰的中文财务观察与可执行建议。")
        """
    }

    /// Deterministic offline financial insight generator when user hasn't configured an API key yet.
    public static func offlineInsight(for report: SummaryReport, question: String? = nil) -> String {
        let exp = report.totalExpenseCents
        let inc = report.totalIncomeCents
        let net = inc - exp
        let netLabel = net >= 0 ? "净结余 \(MoneyFormatter.formatYuan(cents: net))" : "超支 \(MoneyFormatter.formatYuan(cents: abs(net)))"

        var lines: [String] = [
            "【离线本地洞察 · \(report.rangeLabel)】",
            "• 收支概览：支出 \(MoneyFormatter.formatYuan(cents: exp))，收入 \(MoneyFormatter.formatYuan(cents: inc))，\(netLabel)。"
        ]
        if let top = report.expenseShares.first {
            let pct = Int((top.percentage * 100).rounded())
            lines.append("• 核心支出项：「\(top.name)」占比最高，达 \(pct)%（\(MoneyFormatter.formatYuan(cents: top.amountCents))）。")
        }
        if report.previousExpenseCents > 0 {
            let diff = exp - report.previousExpenseCents
            let pct = Int((Double(abs(diff)) / Double(report.previousExpenseCents) * 100).rounded())
            let dir = diff >= 0 ? "上升" : "下降"
            lines.append("• 环比变化：较上周期（\(report.previousRangeLabel)）支出\(dir) \(pct)%（\(MoneyFormatter.formatYuan(cents: abs(diff)))）。")
        }
        if let q = question, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matching = report.periodTransactions.filter {
                $0.categoryNameSnapshot.localizedCaseInsensitiveContains(q) ||
                ($0.note?.localizedCaseInsensitiveContains(q) ?? false)
            }
            if !matching.isEmpty {
                let sum = matching.reduce(Int64(0)) { $0 + $1.amountCents }
                lines.append("• 关键词匹配：共找到 \(matching.count) 笔相关记录，合计 \(MoneyFormatter.formatYuan(cents: sum))。")
            } else {
                lines.append("• 提示：如需语义级自然语言财务推理，可在「AI 设置」填入您的 DeepSeek / OpenAI / Kimi API Key。")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func offlineQuestionAnswer(result: AiLocalQueryResult) -> String {
        var lines: [String] = [
            "【本地检索报告 · \(result.rangeLabel)】",
            "• 命中记录：共 \(result.matchedTransactions.count) 笔（关键词：\(result.keywords.isEmpty ? "全量范围" : result.keywords.joined(separator: "、"))）",
            "• 合计支出：\(MoneyFormatter.formatYuan(cents: result.totalExpenseCents))",
            "• 合计收入：\(MoneyFormatter.formatYuan(cents: result.totalIncomeCents))"
        ]
        if result.matchedTransactions.isEmpty {
            lines.append("• 说明：该时间范围与关键词下未查到匹配账目。")
        } else {
            lines.append("• 明细摘要：")
            let df = DateFormatter()
            df.dateFormat = "MM-dd HH:mm"
            for tx in result.matchedTransactions.prefix(8) {
                let d = df.string(from: PickBankClock.date(fromMs: tx.createdAt))
                let sign = tx.type == .income ? "+" : "-"
                let notePart = (tx.note?.isEmpty == false) ? " · \(tx.note!)" : ""
                lines.append("  - [\(d)] \(tx.categoryNameSnapshot) \(sign)\(MoneyFormatter.formatYuan(cents: tx.amountCents))\(notePart)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public struct AiLocalQueryResult: Sendable, Hashable {
    public let startMs: Int64
    public let endMs: Int64
    public let rangeLabel: String
    public let keywords: [String]
    public let typeFilter: TransactionType?
    public let matchedTransactions: [TransactionRecord]
    public let totalExpenseCents: Int64
    public let totalIncomeCents: Int64
    public let contextPrompt: String
}

/// Faithful Swift port of Android `AiAssistantViewModel.parseQuery` & local DB search before LLM call.
public enum AiLocalQueryEngine {
    public static func execute(
        question: String,
        transactions: [TransactionRecord],
        categoriesById: [String: CategoryRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AiLocalQueryResult {
        let lower = question.lowercased()
        let todayStart = calendar.startOfDay(for: now)

        let (start, end, rangeLabel): (Date, Date, String) = {
            if question.contains("去年的今天") {
                let target = calendar.date(byAdding: .year, value: -1, to: todayStart)!
                return (target, calendar.date(byAdding: .day, value: 1, to: target)!, "去年的今天")
            } else if question.contains("昨天") || lower.contains("yesterday") {
                let y = calendar.date(byAdding: .day, value: -1, to: todayStart)!
                return (y, todayStart, "昨天")
            } else if question.contains("今天") || lower.contains("today") {
                return (todayStart, calendar.date(byAdding: .day, value: 1, to: todayStart)!, "今天")
            } else if question.contains("最近7天") || question.contains("近7天") || question.contains("近七天") {
                let s = calendar.date(byAdding: .day, value: -6, to: todayStart)!
                return (s, calendar.date(byAdding: .day, value: 1, to: todayStart)!, "最近 7 天")
            } else if question.contains("最近30天") || question.contains("近30天") {
                let s = calendar.date(byAdding: .day, value: -29, to: todayStart)!
                return (s, calendar.date(byAdding: .day, value: 1, to: todayStart)!, "最近 30 天")
            } else if question.contains("上个月") || question.contains("上月") || lower.contains("last month") {
                let lm = calendar.date(byAdding: .month, value: -1, to: now)!
                let b = SummaryAnalyticsEngine.rangeBounds(period: .month, anchorDate: lm, calendar: calendar)
                return (b.start, b.end, "上个月")
            } else if question.contains("本周") || question.contains("这周") || lower.contains("this week") {
                let b = SummaryAnalyticsEngine.rangeBounds(period: .week, anchorDate: now, calendar: calendar)
                return (b.start, b.end, "本周")
            } else if question.contains("去年") || lower.contains("last year") {
                let ly = calendar.date(byAdding: .year, value: -1, to: now)!
                let b = SummaryAnalyticsEngine.rangeBounds(period: .year, anchorDate: ly, calendar: calendar)
                return (b.start, b.end, "去年")
            } else if question.contains("今年") || lower.contains("this year") {
                let b = SummaryAnalyticsEngine.rangeBounds(period: .year, anchorDate: now, calendar: calendar)
                return (b.start, b.end, "今年")
            } else {
                let b = SummaryAnalyticsEngine.rangeBounds(period: .month, anchorDate: now, calendar: calendar)
                return (b.start, b.end, "本月")
            }
        }()

        let sMs = PickBankClock.ms(from: start)
        let eMs = PickBankClock.ms(from: end)

        let typeFilter: TransactionType?
        if question.contains("收入") || question.contains("进账") || question.contains("工资") {
            typeFilter = .income
        } else if question.contains("支出") || question.contains("花费") || question.contains("花了") || question.contains("消费") {
            typeFilter = .expense
        } else {
            typeFilter = nil
        }

        // Extract meaningful entity/category keywords from known categories + non-stopword nouns
        var keywords: [String] = []
        for cat in categoriesById.values {
            if question.localizedCaseInsensitiveContains(cat.name) && !keywords.contains(cat.name) {
                keywords.append(cat.name)
            }
        }
        let sampleObjects = ["咖啡", "奶茶", "外卖", "打车", "地铁", "房租", "超市", "电影", "火锅", "机票", "水电", "咖啡豆", "拿铁", "coffee", "uber", "taxi", "lunch", "dinner", "ramen"]
        for obj in sampleObjects {
            if lower.contains(obj.lowercased()) && !keywords.contains(obj) {
                keywords.append(obj)
            }
        }

        let inRange = transactions.filter { tx in
            guard tx.createdAt >= sMs && tx.createdAt < eMs else { return false }
            if let typeFilter, tx.type != typeFilter { return false }
            return true
        }

        let matched: [TransactionRecord]
        if keywords.isEmpty {
            matched = inRange.sorted { $0.createdAt > $1.createdAt }
        } else {
            matched = inRange.filter { tx in
                let catName = tx.resolvedCategoryName(categoriesById: categoriesById)
                return keywords.contains { kw in
                    catName.localizedCaseInsensitiveContains(kw) ||
                    (tx.note?.localizedCaseInsensitiveContains(kw) ?? false) ||
                    (tx.rawInput?.localizedCaseInsensitiveContains(kw) ?? false)
                }
            }.sorted { $0.createdAt > $1.createdAt }
        }

        let exp = matched.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let inc = matched.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let header = """
        用户问题：\(question)
        本地解析时间：\(rangeLabel)（\(df.string(from: start)) 至 \(df.string(from: end))）
        本地解析关键词：\(keywords.isEmpty ? "无" : keywords.joined(separator: "、"))
        命中条数：\(matched.count)
        支出总额：\(MoneyFormatter.formatYuan(cents: exp))
        收入总额：\(MoneyFormatter.formatYuan(cents: inc))
        """
        let lines = matched.prefix(120).enumerated().map { idx, tx in
            let cat = tx.resolvedCategoryName(categoriesById: categoriesById)
            return "\(idx + 1). \(df.string(from: PickBankClock.date(fromMs: tx.createdAt))) | \(tx.type.zhLabel) | \(cat) | \(MoneyFormatter.formatYuan(cents: tx.amountCents)) | \(tx.note ?? tx.rawInput ?? "")"
        }.joined(separator: "\n")

        let prompt = String("\(header)\n\n命中明细：\n\(lines.isEmpty ? "无" : lines)".prefix(24_000))
        return AiLocalQueryResult(
            startMs: sMs,
            endMs: eMs,
            rangeLabel: rangeLabel,
            keywords: keywords,
            typeFilter: typeFilter,
            matchedTransactions: matched,
            totalExpenseCents: exp,
            totalIncomeCents: inc,
            contextPrompt: prompt
        )
    }
}
