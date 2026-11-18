import CommonCrypto
import Compression
import CryptoKit
import Foundation

public enum ArchiveCodecError: LocalizedError, Sendable {
    case invalidFormat(String)
    case checksumMismatch
    case wrongPasswordOrCorruptCiphertext
    case emptyPassword
    case zipError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return msg
        case .checksumMismatch: return "备份校验和不匹配，文件可能已损坏。"
        case .wrongPasswordOrCorruptCiphertext: return "密码错误或加密备份已损坏。"
        case .emptyPassword: return "请输入备份解密/加密密码。"
        case .zipError(let msg): return "压缩包读写失败：\(msg)"
        }
    }
}

public enum ArchiveCodec {
    public static func canonicalSHA256(for snapshot: PickBankLedgerSnapshot) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let payloadData = try enc.encode(snapshot)
        let digest = SHA256.hash(data: payloadData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func encodeLosslessJSON(
        snapshot: PickBankLedgerSnapshot,
        appVersion: String = "2.0.0",
        exportedAt: Int64 = PickBankClock.nowMs()
    ) throws -> Data {
        let hash = try canonicalSHA256(for: snapshot)
        let archive = PickBankArchiveV2(
            appVersion: appVersion,
            platform: "iOS",
            exportedAt: exportedAt,
            sha256: hash,
            payload: snapshot
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(archive)
    }

    public static func decodeLosslessJSON(_ data: Data) throws -> (archive: PickBankArchiveV2, checksumValid: Bool) {
        let dec = JSONDecoder()
        let archive = try dec.decode(PickBankArchiveV2.self, from: data)
        guard archive.format == PickBankArchiveV2.formatIdentifier else {
            throw ArchiveCodecError.invalidFormat("不是有效的 PickBank v2 备份格式")
        }
        let recomputed = try canonicalSHA256(for: archive.payload)
        return (archive, recomputed == archive.sha256)
    }

    // MARK: - Encrypted Backup (PBKDF2-SHA256 + AES-256-GCM)

    public static func encodeEncryptedBackup(
        snapshot: PickBankLedgerSnapshot,
        password: String,
        iterations: Int = 120_000
    ) throws -> Data {
        let cleanPwd = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPwd.isEmpty else { throw ArchiveCodecError.emptyPassword }

        let plaintext = try encodeLosslessJSON(snapshot: snapshot)
        var saltBytes = [UInt8](repeating: 0, count: 16)
        var ivBytes = [UInt8](repeating: 0, count: 12)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess,
              SecRandomCopyBytes(kSecRandomDefault, ivBytes.count, &ivBytes) == errSecSuccess else {
            throw ArchiveCodecError.invalidFormat("无法生成安全随机数")
        }
        let salt = Data(saltBytes)
        let key = try deriveKey(password: cleanPwd, salt: salt, iterations: iterations)
        let nonce = try AES.GCM.Nonce(data: Data(ivBytes))
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        var combinedCipher = Data()
        combinedCipher.append(sealed.ciphertext)
        combinedCipher.append(sealed.tag)

        let backup = PickBankEncryptedBackup(
            format: PickBankEncryptedBackup.formatIdentifier,
            version: 1,
            exportedAt: PickBankClock.nowMs(),
            meta: EncryptedBackupMeta(
                version: 1,
                kdf: "PBKDF2-SHA-256",
                iterations: iterations,
                salt: salt.base64EncodedString()
            ),
            envelope: EncryptedBackupEnvelope(
                version: 1,
                algorithm: "AES-GCM",
                iv: Data(ivBytes).base64EncodedString(),
                ciphertext: combinedCipher.base64EncodedString()
            )
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(backup)
    }

    public static func decodeEncryptedBackup(_ data: Data, password: String) throws -> (archive: PickBankArchiveV2, checksumValid: Bool) {
        let cleanPwd = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPwd.isEmpty else { throw ArchiveCodecError.emptyPassword }
        let backup = try JSONDecoder().decode(PickBankEncryptedBackup.self, from: data)
        guard backup.format == PickBankEncryptedBackup.formatIdentifier,
              let salt = Data(base64Encoded: backup.meta.salt),
              let iv = Data(base64Encoded: backup.envelope.iv),
              let combined = Data(base64Encoded: backup.envelope.ciphertext),
              combined.count > 16 else {
            throw ArchiveCodecError.invalidFormat("加密备份结构无效")
        }
        let key = try deriveKey(password: cleanPwd, salt: salt, iterations: max(10_000, backup.meta.iterations))
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        do {
            let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
            let decrypted = try AES.GCM.open(box, using: key)
            return try decodeLosslessJSON(decrypted)
        } catch {
            throw ArchiveCodecError.wrongPasswordOrCorruptCiphertext
        }
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let pwdData = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password,
                pwdData.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived,
                derived.count
            )
        }
        guard status == kCCSuccess else {
            throw ArchiveCodecError.invalidFormat("PBKDF2 密钥派生失败")
        }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: - CSV Export (UTF-8 BOM)

    public static func exportCSV(snapshot: PickBankLedgerSnapshot, language: AppLanguage = .zhHans) -> Data {
        let zh = (language == .zhHans)
        let catMap = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
        let walletMap = Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0.name) })
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]

        let header = zh
            ? ["编号", "日期", "类型", "分类", "金额(元)", "账户", "备注", "原始输入"]
            : ["ID", "Date", "Type", "Category", "Amount(Yuan)", "Wallet", "Note", "RawInput"]

        var lines: [String] = [header.map(csvEscape).joined(separator: ",")]
        for tx in snapshot.transactions.sorted(by: { $0.createdAt > $1.createdAt }) {
            let typeText = zh ? tx.type.zhLabel : tx.type.enLabel
            let catText = tx.resolvedCategoryName(categoriesById: catMap)
            let amtText = MoneyFormatter.formatPlainDecimal(cents: tx.amountCents)
            let walletText = tx.walletId.flatMap { walletMap[$0] } ?? ""
            let dateStr = df.string(from: PickBankClock.date(fromMs: tx.createdAt))
            let row = [
                tx.id,
                dateStr,
                typeText,
                catText,
                amtText,
                walletText,
                tx.note ?? "",
                tx.rawInput ?? ""
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        let body = "\u{FEFF}" + lines.joined(separator: "\r\n")
        return Data(body.utf8)
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - Native OpenXML XLSX Export

    public static func exportXLSX(snapshot: PickBankLedgerSnapshot, language: AppLanguage = .zhHans) throws -> Data {
        let zh = (language == .zhHans)
        let catMap = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
        let walletMap = Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0.name) })
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let totalExp = snapshot.transactions.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let totalInc = snapshot.transactions.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountCents }

        struct Cell { let value: String; let numeric: Bool; let style: Int }
        var rows: [[Cell]] = []
        rows.append([Cell(value: zh ? "PickBank 拾念记账账本导出" : "PickBank Ledger Export", numeric: false, style: 2)])
        rows.append([
            Cell(value: zh ? "生成时间" : "Generated", numeric: false, style: 2),
            Cell(value: df.string(from: Date()), numeric: false, style: 0)
        ])
        rows.append([
            Cell(value: zh ? "总支出" : "Total Expense", numeric: false, style: 2),
            Cell(value: MoneyFormatter.formatPlainDecimal(cents: totalExp), numeric: true, style: 0),
            Cell(value: zh ? "总收入" : "Total Income", numeric: false, style: 2),
            Cell(value: MoneyFormatter.formatPlainDecimal(cents: totalInc), numeric: true, style: 0)
        ])
        rows.append([])
        let headers = zh
            ? ["编号", "日期", "类型", "分类", "金额(元)", "账户", "备注", "原始输入"]
            : ["ID", "Date", "Type", "Category", "Amount(Yuan)", "Wallet", "Note", "Raw Input"]
        rows.append(headers.map { Cell(value: $0, numeric: false, style: 1) })

        for tx in snapshot.transactions.sorted(by: { $0.createdAt > $1.createdAt }) {
            let typeLabel = zh ? tx.type.zhLabel : tx.type.enLabel
            let catName = tx.resolvedCategoryName(categoriesById: catMap)
            let amtStr = MoneyFormatter.formatPlainDecimal(cents: tx.amountCents)
            let walletName = tx.walletId.flatMap { walletMap[$0] } ?? ""
            rows.append([
                Cell(value: tx.id, numeric: false, style: 0),
                Cell(value: df.string(from: PickBankClock.date(fromMs: tx.createdAt)), numeric: false, style: 0),
                Cell(value: typeLabel, numeric: false, style: 0),
                Cell(value: catName, numeric: false, style: 0),
                Cell(value: amtStr, numeric: true, style: 0),
                Cell(value: walletName, numeric: false, style: 0),
                Cell(value: tx.note ?? "", numeric: false, style: 0),
                Cell(value: tx.rawInput ?? "", numeric: false, style: 0)
            ])
        }

        var sheetRowsXml = ""
        for (rIdx, row) in rows.enumerated() {
            let rNum = rIdx + 1
            if row.isEmpty {
                sheetRowsXml += "<row r=\"\(rNum)\"/>"
                continue
            }
            sheetRowsXml += "<row r=\"\(rNum)\">"
            for (cIdx, cell) in row.enumerated() {
                let colLetter = xlsxColLetter(cIdx)
                let ref = "\(colLetter)\(rNum)"
                if cell.numeric {
                    sheetRowsXml += "<c r=\"\(ref)\" s=\"\(cell.style)\"><v>\(cell.value)</v></c>"
                } else {
                    let escaped = xmlEscape(cell.value)
                    sheetRowsXml += "<c r=\"\(ref)\" t=\"inlineStr\" s=\"\(cell.style)\"><is><t xml:space=\"preserve\">\(escaped)</t></is></c>"
                }
            }
            sheetRowsXml += "</row>"
        }

        let worksheetXml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(sheetRowsXml)</sheetData></worksheet>
        """

        let entries: [(String, Data)] = [
            ("[Content_Types].xml", Data(xlsxContentTypes.utf8)),
            ("_rels/.rels", Data(xlsxRootRels.utf8)),
            ("docProps/app.xml", Data(xlsxAppProps.utf8)),
            ("docProps/core.xml", Data(xlsxCoreProps.utf8)),
            ("xl/workbook.xml", Data(xlsxWorkbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(xlsxWorkbookRels.utf8)),
            ("xl/styles.xml", Data(xlsxStyles.utf8)),
            ("xl/worksheets/sheet1.xml", Data(worksheetXml.utf8))
        ]
        return try buildZipArchive(entries: entries)
    }

    private static func xlsxColLetter(_ idx: Int) -> String {
        var n = idx
        var s = ""
        repeat {
            s = String(UnicodeScalar(65 + (n % 26))!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Pure Swift ZIP Writer & Reader (RFC 1951 via Compression)

    public static func buildZipArchive(entries: [(String, Data)]) throws -> Data {
        var out = Data()
        var centralDirectory = Data()

        for (name, uncompressed) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(uncompressed)
            let compressed = deflateRaw(uncompressed)
            let useDeflate = compressed != nil && (compressed?.count ?? Int.max) < uncompressed.count
            let payload = useDeflate ? compressed! : uncompressed
            let method: UInt16 = useDeflate ? 8 : 0
            let localOffset = UInt32(out.count)

            // Local file header
            out.appendLE(UInt32(0x04034B50))
            out.appendLE(UInt16(20)) // version needed
            out.appendLE(UInt16(0x0800)) // UTF-8 flag
            out.appendLE(method)
            out.appendLE(UInt16(0)) // mod time
            out.appendLE(UInt16(0x5421)) // mod date
            out.appendLE(crc)
            out.appendLE(UInt32(payload.count))
            out.appendLE(UInt32(uncompressed.count))
            out.appendLE(UInt16(nameData.count))
            out.appendLE(UInt16(0)) // extra len
            out.append(nameData)
            out.append(payload)

            // Central directory header
            centralDirectory.appendLE(UInt32(0x02014B50))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0x0800))
            centralDirectory.appendLE(method)
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0x5421))
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(UInt32(payload.count))
            centralDirectory.appendLE(UInt32(uncompressed.count))
            centralDirectory.appendLE(UInt16(nameData.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt32(0))
            centralDirectory.appendLE(localOffset)
            centralDirectory.append(nameData)
        }

        let cdOffset = UInt32(out.count)
        out.append(centralDirectory)
        // End of central directory
        out.appendLE(UInt32(0x06054B50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(centralDirectory.count))
        out.appendLE(cdOffset)
        out.appendLE(UInt16(0))
        return out
    }

    public static func readZipEntries(_ data: Data) throws -> [String: Data] {
        // Locate End of Central Directory (0x06054B50)
        guard data.count >= 22 else { throw ArchiveCodecError.zipError("文件过小") }
        var eocdOffset: Int?
        let minScan = max(0, data.count - 65_557)
        for pos in stride(from: data.count - 22, through: minScan, by: -1) {
            if data.readUInt32LE(at: pos) == 0x06054B50 {
                eocdOffset = pos
                break
            }
        }
        guard let eocd = eocdOffset else { throw ArchiveCodecError.zipError("未找到 ZIP 目录") }
        let totalEntries = Int(data.readUInt16LE(at: eocd + 10))
        var cursor = Int(data.readUInt32LE(at: eocd + 16))
        var result: [String: Data] = [:]

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count, data.readUInt32LE(at: cursor) == 0x02014B50 else {
                throw ArchiveCodecError.zipError("Central directory 损坏")
            }
            let method = data.readUInt16LE(at: cursor + 10)
            let compSize = Int(data.readUInt32LE(at: cursor + 20))
            let uncompSize = Int(data.readUInt32LE(at: cursor + 24))
            let nameLen = Int(data.readUInt16LE(at: cursor + 28))
            let extraLen = Int(data.readUInt16LE(at: cursor + 30))
            let commentLen = Int(data.readUInt16LE(at: cursor + 32))
            let localOffset = Int(data.readUInt32LE(at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else { throw ArchiveCodecError.zipError("文件名越界") }
            let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""
            cursor = nameEnd + extraLen + commentLen

            guard localOffset + 30 <= data.count, data.readUInt32LE(at: localOffset) == 0x04034B50 else {
                continue
            }
            let lNameLen = Int(data.readUInt16LE(at: localOffset + 26))
            let lExtraLen = Int(data.readUInt16LE(at: localOffset + 28))
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            let dataEnd = dataStart + compSize
            guard dataEnd <= data.count else { continue }
            let rawSlice = data[dataStart..<dataEnd]

            if method == 0 {
                result[name] = Data(rawSlice)
            } else if method == 8 {
                if let inflated = inflateRaw(Data(rawSlice), expectedSize: max(uncompSize, compSize * 6)) {
                    result[name] = inflated
                }
            }
        }
        return result
    }

    private static func deflateRaw(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }
        let dstCapacity = max(64, input.count + 1024)
        var dst = Data(count: dstCapacity)
        let written: Int = input.withUnsafeBytes { srcPtr in
            dst.withUnsafeMutableBytes { dstPtr in
                guard let s = srcPtr.bindMemory(to: UInt8.self).baseAddress,
                      let d = dstPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(d, dstCapacity, s, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return dst.prefix(written)
    }

    private static func inflateRaw(_ input: Data, expectedSize: Int) -> Data? {
        guard !input.isEmpty else { return Data() }
        var dstCapacity = max(4096, expectedSize + 4096)
        for _ in 0..<4 {
            var dst = Data(count: dstCapacity)
            let written: Int = input.withUnsafeBytes { srcPtr in
                dst.withUnsafeMutableBytes { dstPtr in
                    guard let s = srcPtr.bindMemory(to: UInt8.self).baseAddress,
                          let d = dstPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(d, dstCapacity, s, input.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 && written < dstCapacity {
                return dst.prefix(written)
            }
            dstCapacity *= 4
        }
        return nil
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - OpenXML Static Metadata

    private static let xlsxContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    </Types>
    """

    private static let xlsxRootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let xlsxAppProps = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>PickBank iOS</Application></Properties>
    """

    private static let xlsxCoreProps = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>PickBank Export</dc:title><dc:creator>PickBank</dc:creator></cp:coreProperties>
    """

    private static let xlsxWorkbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="PickBank" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let xlsxWorkbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let xlsxStyles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2"><font><sz val="11"/><name val="Helvetica Neue"/></font><font><b/><sz val="11"/><name val="Helvetica Neue"/></font></fonts>
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEDEDED"/></patternFill></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
    </styleSheet>
    """
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
