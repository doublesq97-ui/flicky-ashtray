import Foundation

protocol StoreFileAccess: Sendable {
    func createDirectory(at url: URL) throws
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func removeItem(at url: URL) throws
}

struct FoundationStoreFileAccess: StoreFileAccess {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

enum StoreLoadStatus: Equatable, Sendable {
    case missing
    case loaded
    case migrated(fromVersion: Int)
    case corrupt
    case unsupportedFutureVersion(foundVersion: Int)
}

enum StoreLoadSource: Equatable, Sendable {
    case primary
    case backup
}

struct StoreLoadResult: Equatable, Sendable {
    let status: StoreLoadStatus
    let store: SmokeStore?
    let source: StoreLoadSource?
    let isWritable: Bool
    let message: String?
}

enum StoreRepositoryError: LocalizedError, Sendable {
    case refusingToOverwriteCorruptPrimary(String)
    case refusingToDowngradeFutureVersion(Int)
    case refusingToOverwriteProtectedBackup(String)
    case cannotPreserveMigrationSnapshot(String)
    case cannotPrepareSave(String)
    case cannotWritePrimary(String)
    case cannotWriteBackup(String)
    case rollbackFailed(saveError: String, rollbackError: String)

    var errorDescription: String? {
        switch self {
        case let .refusingToOverwriteCorruptPrimary(reason):
            return "记录文件无法安全读取，已拒绝覆盖：\(reason)"
        case let .refusingToDowngradeFutureVersion(version):
            return "记录文件来自更新版本（v\(version)），已拒绝降级覆盖。"
        case let .refusingToOverwriteProtectedBackup(reason):
            return "主记录缺失时不会盲目覆盖现有备份：\(reason)"
        case let .cannotPreserveMigrationSnapshot(reason):
            return "无法保留迁移前原始记录，已取消迁移写回：\(reason)"
        case let .cannotPrepareSave(reason):
            return "无法准备安全保存：\(reason)"
        case let .cannotWritePrimary(reason):
            return "无法原子写入记录文件：\(reason)"
        case let .cannotWriteBackup(reason):
            return "记录文件已回滚，因为备份写入失败：\(reason)"
        case let .rollbackFailed(saveError, rollbackError):
            return "保存失败（\(saveError)），且回滚未完整完成（\(rollbackError)）。"
        }
    }
}

struct StoreRepository: Sendable {
    static let currentVersion = 8

    let fileURL: URL
    private let fileAccess: any StoreFileAccess

    var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        fileURL = applicationSupport
            .appendingPathComponent("Flicky Ashtray", isDirectory: true)
            .appendingPathComponent("store.json")
        fileAccess = FoundationStoreFileAccess()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        fileAccess = FoundationStoreFileAccess()
    }

    init(fileURL: URL, fileAccess: any StoreFileAccess) {
        self.fileURL = fileURL
        self.fileAccess = fileAccess
    }

    func preMigrationSnapshotURL(forVersion sourceVersion: Int) -> URL {
        fileURL.appendingPathExtension("v\(sourceVersion).pre-migration.bak")
    }

    func load() -> StoreLoadResult {
        switch inspect(fileURL) {
        case .missing:
            return loadWithoutPrimary()

        case let .readable(store, sourceVersion, sourceData):
            return finishReadableLoad(
                store: store,
                sourceVersion: sourceVersion,
                sourceData: sourceData,
                source: .primary
            )

        case let .corrupt(reason):
            return recoverReadOnlyFromBackup(primaryReason: reason)

        case let .unsupportedFutureVersion(version):
            return StoreLoadResult(
                status: .unsupportedFutureVersion(foundVersion: version),
                store: nil,
                source: .primary,
                isWritable: false,
                message: "记录文件来自更新版本（v\(version)）。当前版本不会降级或覆盖它。"
            )
        }
    }

    /// A save is committed only after both the primary and last-known-good
    /// backup contain the same normalized data. If backup maintenance fails,
    /// the primary is restored to its exact pre-save bytes before the error is
    /// returned to the model.
    func save(_ store: SmokeStore) throws {
        try save(store, intent: .ordinary)
    }

    private func save(_ store: SmokeStore, intent: SaveIntent) throws {
        var normalized = store
        normalized.normalize()
        let data = try encode(normalized)

        do {
            try fileAccess.createDirectory(at: fileURL.deletingLastPathComponent())
        } catch {
            throw StoreRepositoryError.cannotPrepareSave(error.localizedDescription)
        }

        let (primaryBefore, backupBefore) = try validatedSnapshotsForSave(intent: intent)

        do {
            try fileAccess.write(data, to: fileURL, options: .atomic)
        } catch {
            throw StoreRepositoryError.cannotWritePrimary(error.localizedDescription)
        }

        do {
            try fileAccess.write(data, to: backupURL, options: .atomic)
        } catch {
            let saveError = error.localizedDescription
            do {
                try restore(primaryBefore, at: fileURL)
                try restore(backupBefore, at: backupURL)
            } catch {
                throw StoreRepositoryError.rollbackFailed(
                    saveError: saveError,
                    rollbackError: error.localizedDescription
                )
            }
            throw StoreRepositoryError.cannotWriteBackup(saveError)
        }
    }

    private func loadWithoutPrimary() -> StoreLoadResult {
        switch inspect(backupURL) {
        case .missing:
            return StoreLoadResult(
                status: .missing,
                store: SmokeStore(),
                source: nil,
                isWritable: true,
                message: nil
            )

        case let .readable(store, sourceVersion, sourceData):
            // A missing primary with a readable backup is an interrupted-file
            // recovery, not a new user. Restore it before allowing mutations.
            return finishReadableLoad(
                store: store,
                sourceVersion: sourceVersion,
                sourceData: sourceData,
                source: .backup
            )

        case let .corrupt(reason):
            return StoreLoadResult(
                status: .corrupt,
                store: nil,
                source: .backup,
                isWritable: false,
                message: "主记录文件缺失，且备份无法读取。已进入只读保护：\(reason)"
            )

        case let .unsupportedFutureVersion(version):
            return StoreLoadResult(
                status: .unsupportedFutureVersion(foundVersion: version),
                store: nil,
                source: .backup,
                isWritable: false,
                message: "主记录文件缺失，但备份来自更新版本（v\(version)）。当前版本不会降级或覆盖它。"
            )
        }
    }

    private func finishReadableLoad(
        store: SmokeStore,
        sourceVersion: Int,
        sourceData: Data,
        source: StoreLoadSource
    ) -> StoreLoadResult {
        let status: StoreLoadStatus = sourceVersion < Self.currentVersion
            ? .migrated(fromVersion: sourceVersion)
            : .loaded

        let needsWriteBack = sourceVersion < Self.currentVersion || source == .backup
        guard needsWriteBack else {
            return StoreLoadResult(
                status: status,
                store: store,
                source: source,
                isWritable: true,
                message: nil
            )
        }

        var migrationSnapshotPreserved = false
        do {
            if sourceVersion < Self.currentVersion {
                try preservePreMigrationSnapshot(sourceData, sourceVersion: sourceVersion)
                migrationSnapshotPreserved = true
            }
            let intent: SaveIntent = source == .backup
                ? .restoreVerifiedBackup(sourceData)
                : .ordinary
            try save(store, intent: intent)
            return StoreLoadResult(
                status: status,
                store: store,
                source: source,
                isWritable: true,
                message: nil
            )
        } catch {
            let action = source == .backup ? "恢复备份" : "写回迁移数据"
            let snapshotNote = migrationSnapshotPreserved
                ? "迁移前原始字节已独立留档；该留档不代表迁移成功。"
                : ""
            return StoreLoadResult(
                status: status,
                store: store,
                source: source,
                isWritable: false,
                message: "记录已安全读取，但\(action)失败。\(snapshotNote)当前只读，避免内存与磁盘分叉：\(error.localizedDescription)"
            )
        }
    }

    private func recoverReadOnlyFromBackup(primaryReason: String) -> StoreLoadResult {
        switch inspect(backupURL) {
        case let .readable(store, _, _):
            return StoreLoadResult(
                status: .corrupt,
                store: store,
                source: .backup,
                isWritable: false,
                message: "主记录文件无法读取，已从最后可读备份恢复查看。原文件保持不变，当前只读：\(primaryReason)"
            )

        case .missing:
            return StoreLoadResult(
                status: .corrupt,
                store: nil,
                source: .primary,
                isWritable: false,
                message: "主记录文件无法读取，且没有可用备份。原文件保持不变，当前只读：\(primaryReason)"
            )

        case let .corrupt(backupReason):
            return StoreLoadResult(
                status: .corrupt,
                store: nil,
                source: .primary,
                isWritable: false,
                message: "主记录文件与备份都无法读取，原文件均保持不变。主文件：\(primaryReason)；备份：\(backupReason)"
            )

        case let .unsupportedFutureVersion(version):
            return StoreLoadResult(
                status: .corrupt,
                store: nil,
                source: .primary,
                isWritable: false,
                message: "主记录文件无法读取，备份来自更新版本（v\(version)）。当前只读，且不会覆盖任一文件。"
            )
        }
    }

    private func validatedSnapshotsForSave(
        intent: SaveIntent
    ) throws -> (primary: FileSnapshot, backup: FileSnapshot) {
        switch intent {
        case .ordinary:
            let primary = try validatedPrimarySnapshotForSave()
            let backup: FileSnapshot
            do {
                backup = try rawSnapshot(at: backupURL)
            } catch {
                throw StoreRepositoryError.cannotPrepareSave(
                    "无法读取现有备份：\(error.localizedDescription)"
                )
            }

            if case .missing = primary, case .data = backup {
                throw StoreRepositoryError.refusingToOverwriteProtectedBackup(
                    "备份已存在；请先通过 load 验证并恢复它。"
                )
            }
            if case .data = primary,
               case let .unsupportedFutureVersion(version) = inspect(backupURL) {
                throw StoreRepositoryError.refusingToOverwriteProtectedBackup(
                    "备份来自更新版本 v\(version)，当前主记录不能证明它可被安全替换。"
                )
            }
            return (primary, backup)

        case let .restoreVerifiedBackup(expectedData):
            guard case .missing = inspect(fileURL) else {
                throw StoreRepositoryError.cannotPrepareSave(
                    "验证备份后主记录文件发生了变化，已取消恢复。"
                )
            }

            switch inspect(backupURL) {
            case let .readable(_, _, currentData) where currentData == expectedData:
                return (.missing, .data(currentData))
            case .missing:
                throw StoreRepositoryError.refusingToOverwriteProtectedBackup(
                    "已验证的备份在恢复前消失。"
                )
            case .readable:
                throw StoreRepositoryError.refusingToOverwriteProtectedBackup(
                    "备份在验证后发生了变化。"
                )
            case let .corrupt(reason):
                throw StoreRepositoryError.refusingToOverwriteProtectedBackup(reason)
            case let .unsupportedFutureVersion(version):
                throw StoreRepositoryError.refusingToOverwriteProtectedBackup(
                    "备份来自更新版本 v\(version)。"
                )
            }
        }
    }

    private func validatedPrimarySnapshotForSave() throws -> FileSnapshot {
        switch inspect(fileURL) {
        case .missing:
            return .missing
        case let .readable(_, _, data):
            return .data(data)
        case let .corrupt(reason):
            throw StoreRepositoryError.refusingToOverwriteCorruptPrimary(reason)
        case let .unsupportedFutureVersion(version):
            throw StoreRepositoryError.refusingToDowngradeFutureVersion(version)
        }
    }

    private func preservePreMigrationSnapshot(
        _ sourceData: Data,
        sourceVersion: Int
    ) throws {
        let snapshotURL = preMigrationSnapshotURL(forVersion: sourceVersion)
        do {
            try fileAccess.createDirectory(at: snapshotURL.deletingLastPathComponent())
            switch try rawSnapshot(at: snapshotURL) {
            case .missing:
                do {
                    try fileAccess.write(
                        sourceData,
                        to: snapshotURL,
                        options: .withoutOverwriting
                    )
                } catch {
                    // A second process may have won the create race. Accept only
                    // the exact same immutable source bytes; never replace them.
                    if case let .data(existing) = try rawSnapshot(at: snapshotURL),
                       existing == sourceData {
                        return
                    }
                    throw error
                }
            case let .data(existing):
                guard existing == sourceData else {
                    throw StoreRepositoryError.cannotPreserveMigrationSnapshot(
                        "v\(sourceVersion) 留档已存在且内容不同。"
                    )
                }
            }
        } catch let error as StoreRepositoryError {
            throw error
        } catch {
            throw StoreRepositoryError.cannotPreserveMigrationSnapshot(
                error.localizedDescription
            )
        }
    }

    private func inspect(_ url: URL) -> FileInspection {
        let data: Data
        do {
            data = try fileAccess.read(from: url)
        } catch {
            if isMissingFileError(error) { return .missing }
            return .corrupt("无法读取文件：\(error.localizedDescription)")
        }

        let sourceVersion: Int
        do {
            sourceVersion = try decodeVersion(from: data)
        } catch {
            return .corrupt("JSON 头部无效：\(error.localizedDescription)")
        }

        guard sourceVersion >= 1 else {
            return .corrupt("版本号 \(sourceVersion) 无效。")
        }
        guard sourceVersion <= Self.currentVersion else {
            return .unsupportedFutureVersion(sourceVersion)
        }

        do {
            var store = try decoder(sourceVersion: sourceVersion).decode(SmokeStore.self, from: data)
            store.normalize()
            return .readable(store: store, sourceVersion: sourceVersion, data: data)
        } catch {
            return .corrupt("记录结构无法解码：\(error.localizedDescription)")
        }
    }

    private func decodeVersion(from data: Data) throws -> Int {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        return probe.version ?? 1
    }

    private func encode(_ store: SmokeStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let dateCodec = StoreDateCodec()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateCodec.string(from: date))
        }
        return try encoder.encode(store)
    }

    private func decoder(sourceVersion: Int) -> JSONDecoder {
        let decoder = JSONDecoder()
        let dateCodec = StoreDateCodec()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = dateCodec.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无效的 ISO 8601 日期：\(value)"
            )
        }
        decoder.userInfo[.flickyStoreSourceVersion] = sourceVersion
        return decoder
    }

    private func rawSnapshot(at url: URL) throws -> FileSnapshot {
        do {
            return .data(try fileAccess.read(from: url))
        } catch {
            if isMissingFileError(error) { return .missing }
            throw error
        }
    }

    private func restore(_ snapshot: FileSnapshot, at url: URL) throws {
        switch snapshot {
        case .missing:
            do {
                try fileAccess.removeItem(at: url)
            } catch {
                if !isMissingFileError(error) { throw error }
            }
        case let .data(data):
            try fileAccess.write(data, to: url, options: .atomic)
        }
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .fileReadNoSuchFile
            || (error as NSError).domain == NSPOSIXErrorDomain
                && (error as NSError).code == ENOENT
    }
}

private struct VersionProbe: Decodable {
    let version: Int?
}

private enum FileInspection {
    case missing
    case readable(store: SmokeStore, sourceVersion: Int, data: Data)
    case corrupt(String)
    case unsupportedFutureVersion(Int)
}

private enum FileSnapshot {
    case missing
    case data(Data)
}

private enum SaveIntent {
    case ordinary
    case restoreVerifiedBackup(Data)
}

private final class StoreDateCodec: @unchecked Sendable {
    private let fractionalFormatter: ISO8601DateFormatter
    private let wholeSecondFormatter: ISO8601DateFormatter

    init() {
        fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        wholeSecondFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    func date(from value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
    }
}
