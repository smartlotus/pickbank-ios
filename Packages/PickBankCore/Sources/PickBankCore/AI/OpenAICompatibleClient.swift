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
}
