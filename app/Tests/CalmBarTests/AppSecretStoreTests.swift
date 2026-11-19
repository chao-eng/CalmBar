import Foundation
import SQLite3
import Testing
@testable import CalmBar

@Suite("App Secret Store Tests")
struct AppSecretStoreTests {
    private func makeStore() throws -> (AppSecretStore, URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalmBarSecrets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("secrets.json")
        return (AppSecretStore(fileURL: fileURL), fileURL, directory)
    }

    @Test("密钥以 JSON 形式保存且权限为 0600")
    func storesJSONWithOwnerOnlyPermissions() throws {
        let (store, fileURL, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.set("sk-test", for: "channel.a")
        store.set("gateway-key", for: "server.accessKey")

        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: String])
        #expect(json["channel.a"] == "sk-test")
        #expect(json["server.accessKey"] == "gateway-key")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)
    }

    @Test("重新创建实例可以读取已保存的密钥")
    func reloadsPersistedValues() throws {
        let (store, fileURL, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.set("sk-test", for: "channel.b")

        let reloaded = AppSecretStore(fileURL: fileURL)
        #expect(reloaded.value(for: "channel.b") == "sk-test")
        #expect(reloaded.value(for: "missing") == "")
    }

    @Test("旧 SQLite secrets 表可读取并清理")
    func readsAndCleansLegacySQLiteSecrets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalmBarLegacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("aigateway.db")
        var db: OpaquePointer?
        #expect(sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        ) == SQLITE_OK)
        guard let db else { return }
        let sql = """
        CREATE TABLE secrets (account TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
        INSERT INTO secrets (account, value) VALUES ('channel.a', 'sk-test');
        INSERT INTO secrets (account, value) VALUES ('server.accessKey', 'gateway-key');
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let rows = AppSecretStore.readLegacyDatabaseRows(at: databaseURL.path)
        #expect(rows["channel.a"] == "sk-test")
        #expect(rows["server.accessKey"] == "gateway-key")

        AppSecretStore.cleanupLegacyDatabase(at: databaseURL.path)
        #expect(AppSecretStore.readLegacyDatabaseRows(at: databaseURL.path).isEmpty)

        let raw = try Data(contentsOf: databaseURL)
        #expect(!String(decoding: raw, as: UTF8.self).contains("sk-test"))
    }

    @Test("空值会从 JSON 中移除")
    func removesEmptyValues() throws {
        let (store, fileURL, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.set("sk-test", for: "channel.c")
        store.set("", for: "channel.c")

        let reloaded = AppSecretStore(fileURL: fileURL)
        #expect(reloaded.value(for: "channel.c") == "")

        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: String])
        #expect(json["channel.c"] == nil)
    }
}
