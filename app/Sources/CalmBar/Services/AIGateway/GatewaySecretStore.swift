import Foundation
import SQLite3

// MARK: - 网关密钥存储（明文 SQLite）
//
// 早期实现放在登录钥匙串里：ad-hoc 签名每次重新打包都会改变 cdhash，
// 钥匙串 ACL 随之失效，重启或更新后必然弹一次授权，使用成本高于收益。
// 现在改为明文存放在网关数据库的 secrets 表：文件权限 0600，仅本机当前用户可读，
// 不再触发任何系统授权弹窗。首次升级会尝试把钥匙串里的旧密钥迁移过来，成功后删除钥匙串记录。

public enum GatewaySecretStore {
    /// 测试进程改用纯内存存储，避免污染真实密钥
    private static let isTesting: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    public static let serverKeyID = "server.accessKey"

    public static func apiKey(for channelID: String) -> String {
        value(for: channelID)
    }

    public static func setAPIKey(_ value: String, for channelID: String) {
        set(value, for: channelID)
    }

    public static func removeAPIKey(for channelID: String) {
        set("", for: channelID)
    }

    public static func serverKey() -> String {
        value(for: serverKeyID)
    }

    public static func setServerKey(_ value: String) {
        set(value, for: serverKeyID)
    }

    public static func proxyPassword(for keyID: String) -> String {
        value(for: keyID)
    }

    public static func setProxyPassword(_ value: String, for keyID: String) {
        set(value, for: keyID)
    }

    // MARK: 存储位置

    /// 与 GatewayDatabase 同库，避免再多一个需要备份或清理的文件
    static func databasePath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("CalmBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("aigateway.db").path
    }

    // MARK: 缓存与连接

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: [String: String]?
    nonisolated(unsafe) private static var testingValues: [String: String] = [:]
    nonisolated(unsafe) private static var db: OpaquePointer?
    nonisolated(unsafe) private static var migrationAttempted = false

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func value(for account: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if isTesting { return testingValues[account] ?? "" }
        return loadLocked()[account] ?? ""
    }

    private static func set(_ value: String, for account: String) {
        lock.lock()
        defer { lock.unlock() }
        if isTesting {
            if value.isEmpty {
                testingValues.removeValue(forKey: account)
            } else {
                testingValues[account] = value
            }
            return
        }
        var values = loadLocked()
        if value.isEmpty {
            guard values.removeValue(forKey: account) != nil else { return }
            deleteRow(account: account)
        } else {
            guard values[account] != value else { return }
            values[account] = value
            upsertRow(account: account, value: value)
        }
        cached = values
    }

    /// 调用方需持有 lock
    private static func loadLocked() -> [String: String] {
        if let cached { return cached }
        var values: [String: String] = [:]
        if openIfNeeded() {
            values = readAllRows()
        }
        if values.isEmpty, !migrationAttempted {
            migrationAttempted = true
            if let legacy = LegacyKeychain.readVault() {
                for (account, secret) in legacy where !secret.isEmpty {
                    values[account] = secret
                    upsertRow(account: account, value: secret)
                }
                // 迁移完成即清掉钥匙串记录，之后启动不再触发授权
                if !legacy.isEmpty {
                    LegacyKeychain.removeVault()
                }
            }
        }
        cached = values
        return values
    }

    // MARK: SQLite

    private static func openIfNeeded() -> Bool {
        if db != nil { return true }
        let path = databasePath()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            return false
        }
        sqlite3_busy_timeout(handle, 2000)
        // 密钥是明文，收紧到仅当前用户可读写
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        let sql = """
        CREATE TABLE IF NOT EXISTS secrets (
            account TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return false
        }
        db = handle
        return true
    }

    private static func readAllRows() -> [String: String] {
        guard let db else { return [:] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT account, value FROM secrets;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        var values: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let accountPtr = sqlite3_column_text(stmt, 0), let valuePtr = sqlite3_column_text(stmt, 1) else { continue }
            values[String(cString: accountPtr)] = String(cString: valuePtr)
        }
        return values
    }

    private static func upsertRow(account: String, value: String) {
        guard openIfNeeded(), let db else { return }
        let sql = """
        INSERT INTO secrets (account, value, updated_at) VALUES (?,?,?)
        ON CONFLICT(account) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, account, -1, transient)
        sqlite3_bind_text(stmt, 2, value, -1, transient)
        sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
        _ = sqlite3_step(stmt)
    }

    private static func deleteRow(account: String) {
        guard openIfNeeded(), let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM secrets WHERE account = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, account, -1, transient)
        _ = sqlite3_step(stmt)
    }

    // MARK: 旧钥匙串（仅用于一次性迁移）

    private enum LegacyKeychain {
        private static let service = "com.calmbar.aigateway"
        private static let account = "vault"

        private static func query() -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
        }

        static func readVault() -> [String: String]? {
            var query = query()
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return nil
            }
            return decoded
        }

        static func removeVault() {
            SecItemDelete(query() as CFDictionary)
        }
    }
}
