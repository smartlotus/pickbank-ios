import Foundation

public enum UniversalImportError: LocalizedError, Sendable {
    case unrecognizedFormat
    case requiresPassword
    case emptyRecords

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat: return "无法识别的文件格式。支持 PickBank 备份 (.pickbank.json / .enc.json)、Android Pickbank 迁移包、Excel (.xlsx) 以及 微信/支付宝/通用 CSV 账单。"
        case .requiresPassword: return "该文件为加密备份，请输入密码以预览并导入。"
        case .emptyRecords: return "文件中没有检测到可导入的记账数据。"
        }
    }
}

public enum UniversalImporter {
    public static func inspectAndPreview(
        data: Data,
        fileName: String,
        password: String? = nil,
        existingSnapshot: PickBankLedgerSnapshot
    ) throws -> ImportPreviewReport {
        let lowerName = fileName.lowercased()

        // 1. ZIP / XLSX check (magic bytes PK\x03\x04)
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || lowerName.hasSuffix(".xlsx") {
            return try parseXlsxPreview(data: data, fileName: fileName, existing: existingSnapshot)
        }

        // 2. JSON formats (Archive v2, Encrypted Backup, Android Migration JSON)
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.first == "{" || text.first == "[" {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let format = obj["format"] as? String {
                if format == PickBankEncryptedBackup.formatIdentifier {
                    guard let pwd = password, !pwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw UniversalImportError.requiresPassword
                    }
                    let (archive, valid) = try ArchiveCodec.decodeEncryptedBackup(data, password: pwd)
                    return buildPreview(
                        sourceName: fileName,
                        format: .pickbankEncrypted,
                        checksumValid: valid,
                        snapshot: archive.payload,
                        existing: existingSnapshot
                    )
                }
                if format == PickBankArchiveV2.formatIdentifier {
                    let (archive, valid) = try ArchiveCodec.decodeLosslessJSON(data)
                    return buildPreview(
                        sourceName: fileName,
                        format: .pickbankArchiveV2,
                        checksumValid: valid,
                        snapshot: archive.payload,
                        existing: existingSnapshot
                    )
                }
            }
            if let android = tryParseAndroidMigration(data: data) {
                return buildPreview(
                    sourceName: fileName,
                    format: .androidMigrationJson,
                    checksumValid: true,
                    snapshot: android,
                    existing: existingSnapshot
                )
            }
        }

        // 3. CSV / Tabular text (PickBank CSV, WeChat Pay CSV, Alipay CSV, Generic CSV)
        if let text = decodeTextAutoEncoding(data) {
            return try parseCsvPreview(text: text, fileName: fileName, existing: existingSnapshot)
        }

        throw UniversalImportError.unrecognizedFormat
    }

    public static func applyImport(
        report: ImportPreviewReport,
        mode: ImportExecutionMode,
        store: PickBankStore,
        backupScheduler: AutoBackupScheduler? = nil
    ) async throws -> ImportExecutionResult {
        var safetyMeta: BackupSnapshotMetadata?
        if let scheduler = backupScheduler {
            safetyMeta = try? await scheduler.createSnapshot(trigger: .preImport, password: nil)
        }

        let current = try await store.loadSnapshot()

        switch mode {
        case .cleanReplace:
            var categories = report.incomingCategories
            if categories.isEmpty {
                categories = current.categories
            }
            var catByName = Dictionary(categories.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            var preparedTxs: [TransactionRecord] = []
            for var tx in report.incomingTransactions {
                if tx.categoryId == nil || !categories.contains(where: { $0.id == tx.categoryId }) {
                    if let matched = catByName[tx.categoryNameSnapshot] {
                        tx.categoryId = matched.id
                    } else if !tx.categoryNameSnapshot.isEmpty, tx.categoryNameSnapshot != "未分类" {
                        let newCat = CategoryRecord(
                            name: tx.categoryNameSnapshot,
                            icon: "bookmark.fill",
                            type: tx.type == .income ? .income : .expense,
                            sortOrder: categories.count
                        )
                        categories.append(newCat)
                        catByName[newCat.name] = newCat
                        tx.categoryId = newCat.id
                    }
                }
                preparedTxs.append(tx)
            }
            let replaced = PickBankLedgerSnapshot(
                categories: categories,
                wallets: report.incomingWallets.isEmpty ? current.wallets : report.incomingWallets,
                tags: report.incomingTags,
                transactions: preparedTxs,
                budgets: report.incomingBudgets,
                categoryLimits: report.incomingCategoryLimits,
                recurringRules: report.incomingRecurringRules,
                petState: report.incomingPetState ?? current.petState,
                preferences: report.incomingPreferences ?? current.preferences
            )
            try await store.replaceAll(with: replaced)
            return ImportExecutionResult(
                importedTransactions: preparedTxs.count,
                skippedDuplicates: 0,
                importedCategories: categories.count,
                restoredPetModule: report.incomingPetState != nil,
                safetySnapshotMetadata: safetyMeta
            )

        case .smartMerge:
            let existingById = Set(current.transactions.map(\.id))
            let existingFingerprints = Set(current.transactions.map { fingerprint(for: $0) })

            var existingCatsByName = Dictionary(
                current.categories.map { ("\($0.type.rawValue):\($0.name)", $0) },
                uniquingKeysWith: { a, _ in a }
            )
            var addedCatCount = 0
            for cat in report.incomingCategories {
                let key = "\(cat.type.rawValue):\(cat.name)"
                if existingCatsByName[key] == nil {
                    let saved = try await store.addCategory(name: cat.name, icon: cat.icon, type: cat.type, colorHex: cat.colorHex)
                    existingCatsByName[key] = saved
                    addedCatCount += 1
                }
            }

            let incomingCatById = Dictionary(uniqueKeysWithValues: report.incomingCategories.map { ($0.id, $0) })
            var toInsert: [TransactionRecord] = []
            var skipped = 0

            for var tx in report.incomingTransactions {
                if existingById.contains(tx.id) || existingFingerprints.contains(fingerprint(for: tx)) {
                    skipped += 1
                    continue
                }
                let kindRaw = (tx.type == .income ? CategoryKind.income : CategoryKind.expense).rawValue
                let targetName = tx.categoryId.flatMap { incomingCatById[$0]?.name } ?? tx.categoryNameSnapshot
                let resolvedName = targetName.isEmpty ? "其他" : targetName
                if let matchedCat = existingCatsByName["\(kindRaw):\(resolvedName)"] {
                    tx.categoryId = matchedCat.id
                    tx.categoryNameSnapshot = matchedCat.name
                } else {
                    let created = try await store.addCategory(
                        name: resolvedName,
                        icon: "bookmark.fill",
                        type: tx.type == .income ? .income : .expense
                    )
                    existingCatsByName["\(kindRaw):\(resolvedName)"] = created
                    tx.categoryId = created.id
                    tx.categoryNameSnapshot = created.name
                    addedCatCount += 1
                }
                toInsert.append(tx)
            }

            if !toInsert.isEmpty {
                _ = try await store.insertTransactions(toInsert)
            }
            for rule in report.incomingRecurringRules where !current.recurringRules.contains(where: { $0.id == rule.id }) {
                try await store.upsertRecurringRule(rule)
            }
            return ImportExecutionResult(
                importedTransactions: toInsert.count,
                skippedDuplicates: skipped,
                importedCategories: addedCatCount,
                restoredPetModule: false,
                safetySnapshotMetadata: safetyMeta
            )
        }
    }

    // MARK: - Helpers

    public static func fingerprint(for tx: TransactionRecord) -> String {
        // Group timestamps to minute resolution so CSV / XLSX round-trips match cleanly
        let minuteBucket = tx.createdAt / 60_000
        let cleanNote = (tx.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(tx.type.rawValue)|\(tx.amountCents)|\(minuteBucket)|\(tx.categoryNameSnapshot)|\(cleanNote)"
    }

    private static func buildPreview(
        sourceName: String,
        format: ImportSourceFormat,
        checksumValid: Bool,
        snapshot: PickBankLedgerSnapshot,
        existing: PickBankLedgerSnapshot
    ) -> ImportPreviewReport {
        let existingIds = Set(existing.transactions.map(\.id))
        let existingFingerprints = Set(existing.transactions.map { fingerprint(for: $0) })
        var dupCount = 0
        for tx in snapshot.transactions {
            if existingIds.contains(tx.id) || existingFingerprints.contains(fingerprint(for: tx)) {
                dupCount += 1
            }
        }
        var warnings: [String] = []
        if !checksumValid {
            warnings.append("文件 SHA-256 校验与载荷不一致（可能经过手动编辑），请仔细核对预览数量后再导入。")
        }
        return ImportPreviewReport(
            sourceName: sourceName,
            detectedFormat: format,
            checksumVerified: checksumValid,
            incomingTransactions: snapshot.transactions,
            incomingCategories: snapshot.categories,
            incomingBudgets: snapshot.budgets,
            incomingCategoryLimits: snapshot.categoryLimits,
            incomingRecurringRules: snapshot.recurringRules,
            incomingWallets: snapshot.wallets,
            incomingTags: snapshot.tags,
            incomingPetState: snapshot.petState.profiles.isEmpty && !snapshot.petState.settings.isEnabled ? nil : snapshot.petState,
            incomingPreferences: snapshot.preferences,
            duplicateCount: dupCount,
            netNewCount: max(0, snapshot.transactions.count - dupCount),
            warnings: warnings
        )
    }

    private static func tryParseAndroidMigration(data: Data) -> PickBankLedgerSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let container = (root["data"] as? [String: Any]) ?? root
        let rawCats = (container["categories"] as? [[String: Any]]) ?? []
        let rawTxs = (container["transactions"] as? [[String: Any]]) ?? []
        guard !rawCats.isEmpty || !rawTxs.isEmpty else { return nil }

        var catIdMap: [String: CategoryRecord] = [:]
        var categories: [CategoryRecord] = []
        for (idx, c) in rawCats.enumerated() {
            guard let name = c["name"] as? String else { continue }
            let srcId = String(describing: c["id"] ?? idx)
            let kindInt = (c["type"] as? Int) ?? 0
            let kind: CategoryKind = (kindInt == 1) ? .income : .expense
            let rec = CategoryRecord(
                id: "android-cat-\(srcId)",
                name: name,
                icon: "bookmark.fill",
                type: kind,
                sortOrder: (c["sortOrder"] as? Int) ?? idx,
                isDefault: false,
                isArchived: (c["isArchived"] as? Bool) ?? false
            )
            categories.append(rec)
            catIdMap[srcId] = rec
        }

        var txs: [TransactionRecord] = []
        for (idx, t) in rawTxs.enumerated() {
            let srcId = String(describing: t["id"] ?? idx)
            let cents: Int64
            if let v = t["amountCents"] as? Int64 {
                cents = abs(v)
            } else if let v = t["amount"] as? Int64 {
                cents = abs(v)
            } else if let v = t["amount"] as? Double {
                cents = abs(Int64((v * 100.0).rounded()))
            } else {
                continue
            }
            let typeInt = (t["type"] as? Int) ?? 0
            let txType = TransactionType(rawValue: typeInt) ?? .expense
            let catSrcId = t["categoryId"].map { String(describing: $0) }
            let boundCat = catSrcId.flatMap { catIdMap[$0] }
            let snapName = (t["categoryName"] as? String) ?? boundCat?.name ?? "未分类"
            let createdAt = (t["createdAt"] as? Int64) ?? PickBankClock.nowMs()
            let updatedAt = (t["updatedAt"] as? Int64) ?? createdAt
            txs.append(TransactionRecord(
                id: "android-tx-\(srcId)",
                amountCents: cents,
                type: txType,
                categoryId: boundCat?.id,
                categoryNameSnapshot: snapName,
                note: t["note"] as? String,
                rawInput: t["rawInput"] as? String,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return PickBankLedgerSnapshot(categories: categories, transactions: txs)
    }

    private static func parseXlsxPreview(data: Data, fileName: String, existing: PickBankLedgerSnapshot) throws -> ImportPreviewReport {
        let entries = try ArchiveCodec.readZipEntries(data)
        guard let sheetData = entries["xl/worksheets/sheet1.xml"] ?? entries.first(where: { $0.key.hasSuffix(".xml") && $0.key.contains("sheet") })?.value,
              let sheetXml = String(data: sheetData, encoding: .utf8) else {
            throw UniversalImportError.unrecognizedFormat
        }
        let sharedStrings = parseSharedStrings(entries["xl/sharedStrings.xml"])
        let rows = parseWorksheetRows(xml: sheetXml, sharedStrings: sharedStrings)
        guard let headerIdx = rows.firstIndex(where: { row in
            let joined = row.joined(separator: "|")
            return joined.contains("金额") || joined.lowercased().contains("amount")
        }) else {
            throw UniversalImportError.emptyRecords
        }
        let headers = rows[headerIdx]
        let txs = mapTabularRows(headers: headers, dataRows: Array(rows.dropFirst(headerIdx + 1)))
        guard !txs.isEmpty else { throw UniversalImportError.emptyRecords }
        return buildPreview(
            sourceName: fileName,
            format: .pickbankXlsx,
            checksumValid: true,
            snapshot: PickBankLedgerSnapshot(transactions: txs),
            existing: existing
        )
    }

    private static func parseCsvPreview(text: String, fileName: String, existing: PickBankLedgerSnapshot) throws -> ImportPreviewReport {
        let lines = splitCsvLines(text)
        guard let headerIdx = lines.firstIndex(where: { row in
            let joined = row.joined(separator: ",")
            return (joined.contains("金额") || joined.lowercased().contains("amount")) && row.count >= 3
        }) else {
            throw UniversalImportError.emptyRecords
        }
        let headerAndPreamble = lines[0...headerIdx].map { $0.joined(separator: ",") }.joined(separator: "\n")
        let format: ImportSourceFormat
        if headerAndPreamble.contains("微信支付账单") || headerAndPreamble.contains("交易时间,交易类型,交易对方") {
            format = .wechatPayCsv
        } else if headerAndPreamble.contains("支付宝") || headerAndPreamble.contains("交易创建时间") || headerAndPreamble.contains("收/支") {
            format = .alipayCsv
        } else {
            format = .genericCsv
        }
        let headers = lines[headerIdx].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let txs = mapTabularRows(headers: headers, dataRows: Array(lines.dropFirst(headerIdx + 1)))
        guard !txs.isEmpty else { throw UniversalImportError.emptyRecords }
        return buildPreview(
            sourceName: fileName,
            format: format,
            checksumValid: true,
            snapshot: PickBankLedgerSnapshot(transactions: txs),
            existing: existing
        )
    }

    private static func mapTabularRows(headers: [String], dataRows: [[String]]) -> [TransactionRecord] {
        func col(_ candidates: [String]) -> Int? {
            // Exact match first, then substring match, so "收/支" or "类型" beats "交易类型"
            for c in candidates {
                if let idx = headers.firstIndex(where: { $0.compare(c, options: .caseInsensitive) == .orderedSame }) {
                    return idx
                }
            }
            for c in candidates {
                if let idx = headers.firstIndex(where: { $0.localizedCaseInsensitiveContains(c) }) {
                    return idx
                }
            }
            return nil
        }
        let idCol = col(["编号", "ID", "交易单号"])
        let dateCol = col(["日期", "交易时间", "创建时间", "Date", "Time"])
        let typeCol = col(["收/支", "类型", "Type"])
        let catCol = col(["分类", "交易类型", "商品", "Category"])
        let amtCol = col(["金额(元)", "金额", "Amount(Yuan)", "Amount"])
        let noteCol = col(["备注", "交易对方", "Note", "Memo"])
        let rawCol = col(["原始输入", "RawInput", "Raw Input", "Raw"])

        guard let amtCol else { return [] }
        let nlp = NlpParseEngine()
        var out: [TransactionRecord] = []

        for row in dataRows {
            guard amtCol < row.count else { continue }
            let amtStr = row[amtCol].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cents = MoneyFormatter.parseToCents(amtStr), cents > 0 else { continue }

            let typeRaw = typeCol.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if typeRaw.contains("不计收支") { continue }
            let txType: TransactionType
            if typeRaw.contains("收入") || typeRaw.localizedCaseInsensitiveContains("income") {
                txType = .income
            } else if typeRaw.contains("转账") || typeRaw.localizedCaseInsensitiveContains("transfer") {
                txType = .transfer
            } else {
                txType = .expense
            }

            let dateRaw = dateCol.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let timestamp = parseFlexibleTimestamp(dateRaw) ?? PickBankClock.nowMs()
            let noteRaw = noteCol.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let catRaw = catCol.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawInput = rawCol.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)

            var categoryName = (catRaw?.isEmpty == false) ? catRaw! : "其他"
            if (catRaw == nil || catRaw == "/" || catRaw == "商户消费") && noteRaw != nil {
                if let inferred = nlp.parse("\(noteRaw!) \(MoneyFormatter.formatPlainDecimal(cents: cents))") {
                    categoryName = inferred.categoryName
                }
            }

            let txId = idCol.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil }
            let resolvedId = (txId?.isEmpty == false && txId!.count >= 6) ? txId! : UUID().uuidString

            out.append(TransactionRecord(
                id: resolvedId,
                amountCents: cents,
                type: txType,
                categoryId: nil,
                categoryNameSnapshot: categoryName,
                note: noteRaw?.isEmpty == false ? noteRaw : nil,
                rawInput: rawInput?.isEmpty == false ? rawInput : nil,
                createdAt: timestamp,
                updatedAt: timestamp
            ))
        }
        return out
    }

    private static func parseFlexibleTimestamp(_ raw: String) -> Int64? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return PickBankClock.ms(from: d) }
        let isoSimple = ISO8601DateFormatter()
        if let d = isoSimple.date(from: s) { return PickBankClock.ms(from: d) }

        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return PickBankClock.ms(from: d) }
        }
        return nil
    }

    private static func decodeTextAutoEncoding(_ data: Data) -> String? {
        var clean = data
        if clean.starts(with: [0xEF, 0xBB, 0xBF]) {
            clean = clean.dropFirst(3)
        }
        if let utf8 = String(data: clean, encoding: .utf8) { return utf8 }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: clean, encoding: String.Encoding(rawValue: gb18030))
    }

    private static func splitCsvLines(_ text: String) -> [[String]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    row.append(field)
                    field = ""
                } else if ch == "\n" {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                } else {
                    field.append(ch)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: - Native Foundation XMLParser for XLSX Import

    private static func parseSharedStrings(_ data: Data?) -> [String] {
        guard let data else { return [] }
        let delegate = SharedStringsXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    private static func parseWorksheetRows(xml: String, sharedStrings: [String]) -> [[String]] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = WorksheetXMLDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    private final class SharedStringsXMLDelegate: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var inSi = false
        private var inT = false
        private var current = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "si" {
                inSi = true
                current = ""
            } else if elementName == "t" && inSi {
                inT = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inT { current += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "t" {
                inT = false
            } else if elementName == "si" {
                inSi = false
                strings.append(current)
            }
        }
    }

    private final class WorksheetXMLDelegate: NSObject, XMLParserDelegate {
        let sharedStrings: [String]
        var rows: [[String]] = []

        private var currentRow: [String] = []
        private var inRow = false
        private var inCell = false
        private var cellType = ""
        private var cellColIdx = 0
        private var captureText = false
        private var buffer = ""

        init(sharedStrings: [String]) {
            self.sharedStrings = sharedStrings
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "row" {
                inRow = true
                currentRow = []
            } else if elementName == "c" && inRow {
                inCell = true
                cellType = attributeDict["t"] ?? ""
                buffer = ""
                if let ref = attributeDict["r"] {
                    let letters = String(ref.prefix(while: { $0.isLetter }))
                    cellColIdx = letters.isEmpty ? currentRow.count : colIndexFromLetters(letters)
                } else {
                    cellColIdx = currentRow.count
                }
                while currentRow.count <= cellColIdx { currentRow.append("") }
            } else if inCell && (elementName == "v" || elementName == "t") {
                captureText = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if captureText { buffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "v" || elementName == "t" {
                captureText = false
            } else if elementName == "c" && inCell {
                let value: String
                if cellType == "s", let idx = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)), idx >= 0, idx < sharedStrings.count {
                    value = sharedStrings[idx]
                } else {
                    value = buffer
                }
                if cellColIdx < currentRow.count {
                    currentRow[cellColIdx] = value
                }
                inCell = false
            } else if elementName == "row" && inRow {
                inRow = false
                rows.append(currentRow)
            }
        }
    }

    private static func colIndexFromLetters(_ letters: String) -> Int {
        var result = 0
        for scalar in letters.unicodeScalars {
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(0, result - 1)
    }
}
