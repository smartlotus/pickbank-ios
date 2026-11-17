import CryptoKit
import Foundation

public struct ExternalFolderWriter: Sendable {
    public var writeFile: @Sendable (_ fileName: String, _ data: Data) async throws -> Bool

    public init(writeFile: @escaping @Sendable (_ fileName: String, _ data: Data) async throws -> Bool) {
        self.writeFile = writeFile
    }
}

public actor AutoBackupScheduler {
    private let store: PickBankStore
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(store: PickBankStore) {
        self.store = store
        self.indexURL = store.backupsDirectory.appendingPathComponent("backups_index.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        self.decoder = JSONDecoder()
    }

    public func listSnapshots() throws -> [BackupSnapshotMetadata] {
        try reconcileDiskIndex()
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func createSnapshot(
        trigger: BackupTriggerKind,
        password: String? = nil,
        pin: Bool = false,
        externalWriter: ExternalFolderWriter? = nil
    ) async throws -> BackupSnapshotMetadata {
        try await store.checkpointWAL()
        let snapshot = try await store.loadSnapshot()
        let nowMs = PickBankClock.nowMs()

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = df.string(from: PickBankClock.date(fromMs: nowMs))

        let snapshotId = UUID().uuidString
        let shortId = String(snapshotId.prefix(6)).lowercased()
        let cleanPwd = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEncrypted = (cleanPwd?.isEmpty == false)
        let ext = isEncrypted ? "pickbank.enc.json" : "pickbank.json"
        let tag = trigger.rawValue.lowercased()
        let fileName = "pickbank_\(tag)_\(stamp)_\(shortId).\(ext)"
        let targetURL = store.backupsDirectory.appendingPathComponent(fileName)

        let bytes: Data
        if let cleanPwd, !cleanPwd.isEmpty {
            bytes = try ArchiveCodec.encodeEncryptedBackup(snapshot: snapshot, password: cleanPwd)
        } else {
            bytes = try ArchiveCodec.encodeLosslessJSON(snapshot: snapshot, exportedAt: nowMs)
        }

        try bytes.write(to: targetURL, options: .atomic)

        var externalSynced = false
        if let externalWriter {
            externalSynced = (try? await externalWriter.writeFile(fileName, bytes)) ?? false
        }

        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let meta = BackupSnapshotMetadata(
            id: snapshotId,
            fileName: fileName,
            createdAt: nowMs,
            trigger: trigger,
            isEncrypted: isEncrypted,
            isPinned: pin || trigger == .preImport || trigger == .preDestructive,
            transactionCount: snapshot.transactions.count,
            categoryCount: snapshot.categories.count,
            petCount: snapshot.petState.profiles.count,
            byteSize: Int64(bytes.count),
            sha256: sha,
            externalSynced: externalSynced
        )

        var list = try reconcileDiskIndex()
        list.append(meta)
        try saveIndex(list)

        var config = try await store.loadBackupSchedule()
        config.lastBackupAt = nowMs
        config.lastBackupStatus = externalSynced ? "已同步本地与外部目录" : "已保存至本地备份库"
        try await store.saveBackupSchedule(config)

        try await enforceRetentionPolicy(maxAutoBackups: config.maxRetainedAutoBackups)
        return meta
    }

    public func readSnapshotBytes(id: String) throws -> (metadata: BackupSnapshotMetadata, data: Data, url: URL) {
        let list = try reconcileDiskIndex()
        guard let meta = list.first(where: { $0.id == id }) else {
            throw PickBankStoreError.notFound("找不到该备份快照")
        }
        let url = store.backupsDirectory.appendingPathComponent(meta.fileName)
        let data = try Data(contentsOf: url)
        return (meta, data, url)
    }

    public func togglePin(id: String) throws -> BackupSnapshotMetadata {
        var list = try reconcileDiskIndex()
        guard let idx = list.firstIndex(where: { $0.id == id }) else {
            throw PickBankStoreError.notFound("找不到该备份快照")
        }
        list[idx].isPinned.toggle()
        try saveIndex(list)
        return list[idx]
    }

    public func deleteSnapshot(id: String) throws {
        var list = try reconcileDiskIndex()
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let fileURL = store.backupsDirectory.appendingPathComponent(list[idx].fileName)
        try? FileManager.default.removeItem(at: fileURL)
        list.remove(at: idx)
        try saveIndex(list)
    }

    public func restoreSnapshot(
        id: String,
        password: String? = nil,
        createSafetySnapshotFirst: Bool = true
    ) async throws -> ImportExecutionResult {
        let (meta, data, _) = try readSnapshotBytes(id: id)
        if createSafetySnapshotFirst {
            _ = try? await createSnapshot(trigger: .preImport, password: nil, pin: true)
        }
        let current = try await store.loadSnapshot()
        let preview = try UniversalImporter.inspectAndPreview(
            data: data,
            fileName: meta.fileName,
            password: password,
            existingSnapshot: current
        )
        // Restoring a snapshot intentionally restores the exact point in time via cleanReplace.
        return try await UniversalImporter.applyImport(
            report: preview,
            mode: .cleanReplace,
            store: store,
            backupScheduler: nil
        )
    }

    public func isBackupDue(
        config: BackupScheduleConfig,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let nowMs = PickBankClock.ms(from: now)
        switch config.frequency {
        case .off:
            return false
        case .onBackgroundIfDirty:
            guard let dirty = config.lastDirtyMutationAt else { return false }
            let last = config.lastBackupAt ?? 0
            return dirty > last
        case .every6Hours:
            let last = config.lastBackupAt ?? 0
            return (nowMs - last) >= Int64(6 * 3600 * 1000)
        case .daily:
            guard let lastMs = config.lastBackupAt else { return true }
            let lastDate = PickBankClock.date(fromMs: lastMs)
            if calendar.isDate(lastDate, inSameDayAs: now) { return false }
            let hour = calendar.component(.hour, from: now)
            // Trigger if we've passed today's preferred hour OR if >= 36 hours elapsed since last backup
            return hour >= config.preferredHour || (nowMs - lastMs) >= Int64(36 * 3600 * 1000)
        case .weekly:
            guard let lastMs = config.lastBackupAt else { return true }
            return (nowMs - lastMs) >= Int64(7 * 24 * 3600 * 1000)
        }
    }

    @discardableResult
    public func runScheduledCheckIfDue(
        forceOnDirtyBackground: Bool = false,
        password: String? = nil,
        externalWriter: ExternalFolderWriter? = nil,
        now: Date = Date()
    ) async throws -> BackupSnapshotMetadata? {
        let config = try await store.loadBackupSchedule()
        if forceOnDirtyBackground && config.frequency == .onBackgroundIfDirty {
            guard isBackupDue(config: config, now: now) else { return nil }
        } else {
            guard isBackupDue(config: config, now: now) else { return nil }
        }
        let pwd = config.encryptAutoBackups ? password : nil
        return try await createSnapshot(trigger: .auto, password: pwd, pin: false, externalWriter: externalWriter)
    }

    public func enforceRetentionPolicy(maxAutoBackups: Int) async throws {
        var list = try reconcileDiskIndex()
        let autoCandidates = list
            .filter { $0.trigger == .auto && !$0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }
        guard autoCandidates.count > maxAutoBackups else { return }
        let toEvict = autoCandidates.dropFirst(max(1, maxAutoBackups))
        let evictIds = Set(toEvict.map(\.id))
        for victim in toEvict {
            let fileURL = store.backupsDirectory.appendingPathComponent(victim.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        list.removeAll { evictIds.contains($0.id) }
        try saveIndex(list)
    }

    private func reconcileDiskIndex() throws -> [BackupSnapshotMetadata] {
        let fm = FileManager.default
        var indexed: [BackupSnapshotMetadata] = []
        if fm.fileExists(atPath: indexURL.path),
           let data = try? Data(contentsOf: indexURL),
           let decoded = try? decoder.decode([BackupSnapshotMetadata].self, from: data) {
            indexed = decoded.filter { fm.fileExists(atPath: store.backupsDirectory.appendingPathComponent($0.fileName).path) }
        }
        return indexed
    }

    private func saveIndex(_ list: [BackupSnapshotMetadata]) throws {
        let data = try encoder.encode(list.sorted { $0.createdAt > $1.createdAt })
        try data.write(to: indexURL, options: .atomic)
    }
}
