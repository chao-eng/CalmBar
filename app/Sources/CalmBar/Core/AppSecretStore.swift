import Foundation
import SQLite3

/// 统一保存应用内的密钥（翻译 API Key、网关渠道 Key、网关访问密钥、代理密码、
/// 局域网互传口令的 HMAC 密钥）。
///
/// 设计取舍：不依赖 Keychain，统一落盘为 `~/Library/Application Support/CalmBar/secrets.json`，
/// 文件权限固定 `0600`。JSON 便于备份、迁移和人工排查；安全性依赖当前用户账户与文件权限，
/// 因此不要在日志或 UI 中回显这里的内容。
final class AppSecretStore: @unchecked Sendable {
    static let shared = AppSecretStore()
    static let translationAPIKeyAccount = "translationAPIKey"
    static let lanSharePasscodeKeyAccount = "lanshare.passcode.hmacKey"

    private static let isTesting: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    private let lock = NSLock()
    private let fileURL: URL
    private let isMemoryOnly: Bool
    private let migratesLegacyData: Bool
    private var values: [String: String]?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            self.isMemoryOnly = false
            self.migratesLegacyData = false
        } else {
            self.fileURL = Self.defaultFileURL()
            self.isMemoryOnly = Self.isTesting
            self.migratesLegacyData = !Self.isTesting
        }

        if isMemoryOnly {
            values = [:]
        } else {
            ensureDirectory()
            loadLocked()
            if migratesLegacyData {
                migrateLegacyDataLocked()
            }
            enforcePermissions()
        }
    }

    /// 测试环境使用内存存储；迁移逻辑据此跳过真实 Keychain 访问。
    var isUsingMemoryStore: Bool { isMemoryOnly }

    // MARK: 读写

    func value(for account: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return currentValuesLocked()[account] ?? ""
    }

    @discardableResult
    func set(_ value: String, for account: String) -> Bool {
        lock.lock()
        var current = currentValuesLocked()
        if value.isEmpty {
            guard current.removeValue(forKey: account) != nil else {
                lock.unlock()
                return true
            }
        } else {
            guard current[account] != value else {
                lock.unlock()
                return true
            }
            current[account] = value
        }
        values = current
        // 持锁写盘，保证并发 set 时 JSON 的最终内容与内存快照顺序一致。
        let persisted = isMemoryOnly ? true : persist(current)
        lock.unlock()
        return persisted
    }

    // MARK: 加载与持久化

    private func currentValuesLocked() -> [String: String] {
        if let values { return values }
        let loaded = Self.readJSON(at: fileURL) ?? [:]
        values = loaded
        return loaded
    }

    private func loadLocked() {
        values = Self.readJSON(at: fileURL) ?? [:]
    }

    @discardableResult
    private func persist(_ snapshot: [String: String]) -> Bool {
        ensureDirectory()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            NSLog("AppSecretStore: 写入密钥文件失败 \(error.localizedDescription)")
            return false
        }
    }

    private func ensureDirectory() {
        let directory = fileURL.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func enforcePermissions() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func readJSON(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("CalmBar", isDirectory: true)
            .appendingPathComponent("secrets.json")
    }

    // MARK: 旧版本迁移

    /// 把旧位置的数据并入 JSON：翻译 Key 原先在 UserDefaults，网关密钥原先在
    /// `aigateway.db` 的 `secrets` 表。成功写入 JSON 后才删除旧副本。
    private func migrateLegacyDataLocked() {
        var merged = currentValuesLocked()
        var needsMigration = false

        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: Self.translationAPIKeyAccount), !legacy.isEmpty {
            if merged[Self.translationAPIKeyAccount] == nil {
                merged[Self.translationAPIKeyAccount] = legacy
            }
            needsMigration = true
        }

        let legacyRows = Self.readLegacyDatabaseRows()
        for (account, value) in legacyRows where merged[account] == nil {
            merged[account] = value
            needsMigration = true
        }

        guard needsMigration || !legacyRows.isEmpty else { return }

        values = merged
        guard persist(merged) else { return }

        defaults.removeObject(forKey: Self.translationAPIKeyAccount)
        if !legacyRows.isEmpty {
            Self.cleanupLegacyDatabase()
        }
    }

    // MARK: 旧 SQLite 密钥表

    private static func legacyDatabaseURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("CalmBar", isDirectory: true)
            .appendingPathComponent("aigateway.db")
    }

    static func readLegacyDatabaseRows(at path: String = legacyDatabaseURL().path) -> [String: String] {
        guard FileManager.default.fileExists(atPath: path) else { return [:] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        var check: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'secrets';",
            -1,
            &check,
            nil
        ) == SQLITE_OK, let check else { return [:] }
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW else { return [:] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT account, value FROM secrets;", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        var rows: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let accountPointer = sqlite3_column_text(statement, 0),
                  let valuePointer = sqlite3_column_text(statement, 1) else { continue }
            rows[String(cString: accountPointer)] = String(cString: valuePointer)
        }
        return rows
    }

    static func cleanupLegacyDatabase(at path: String = legacyDatabaseURL().path) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        // secure_delete 先覆盖删除内容；随后 drop + VACUUM 重建数据库，
        // 再截断 WAL，尽量不把旧密钥留在空闲页或日志文件里。
        sqlite3_exec(db, "PRAGMA secure_delete = ON;", nil, nil, nil)
        sqlite3_exec(db, "DROP TABLE IF EXISTS secrets;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }
}
