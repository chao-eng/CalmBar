import CryptoKit
import Foundation
import Security

// MARK: - 恒定时间比较

enum LANShareConstantTime {
    static func equals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = left.count ^ right.count
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            difference |= Int(a ^ b)
        }
        return difference == 0
    }

    static func equals(_ lhs: Data, _ rhs: Data) -> Bool {
        var difference = lhs.count ^ rhs.count
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            difference |= Int(a ^ b)
        }
        return difference == 0
    }
}

// MARK: - 口令 HMAC 密钥

/// 口令 HMAC 密钥统一保存在 `AppSecretStore`（JSON + 0600）。
/// 旧版本存在 Keychain 中，首次读取时迁移一次并删除旧条目。
enum LANSharePasscodeKey {
    static let legacyService = "com.calmbar.lanshare"
    static let legacyAccount = "passcode-hmac-key"

    /// 只读取已有密钥并执行一次 Keychain 迁移；找不到时返回 nil，不生成新密钥。
    static func loadExistingKey() -> Data? {
        if let existing = loadManagedKey(), existing.count >= 32 {
            // JSON 已有密钥时顺手清理可能残留的旧 Keychain 条目。
            deleteLegacyKey()
            return existing
        }

        // 测试环境使用内存存储，禁止触碰用户真实的 Keychain 条目。
        guard !AppSecretStore.shared.isUsingMemoryStore,
              let legacy = loadLegacyKey(), legacy.count >= 32 else {
            return nil
        }
        // JSON 写入成功后才删除 Keychain 旧条目，失败时保留旧数据继续可用。
        if saveManagedKey(legacy) {
            deleteLegacyKey()
        }
        return legacy
    }

    /// 设置新口令时使用：没有密钥才生成。
    static func loadOrCreateKey() -> Data {
        if let existing = loadExistingKey() {
            return existing
        }
        let data = generateKey()
        saveManagedKey(data)
        return data
    }

    static func rotateKey() -> Data {
        let data = generateKey()
        // 新密钥成功落盘后再删除旧 Keychain 条目，避免迁移失败丢密钥。
        if saveManagedKey(data) {
            deleteLegacyKey()
        }
        return data
    }

    private static func loadManagedKey() -> Data? {
        let raw = AppSecretStore.shared.value(for: AppSecretStore.lanSharePasscodeKeyAccount)
        guard !raw.isEmpty, let data = Data(base64Encoded: raw) else { return nil }
        return data
    }

    @discardableResult
    private static func saveManagedKey(_ data: Data) -> Bool {
        AppSecretStore.shared.set(
            data.base64EncodedString(),
            for: AppSecretStore.lanSharePasscodeKeyAccount
        )
    }

    private static func generateKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }

    private static func loadLegacyKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func deleteLegacyKey() {
        guard !AppSecretStore.shared.isUsingMemoryStore else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 口令存储（HMAC verifier 落盘，密钥在 secrets.json）

public final class LANSharePasscodeStore: @unchecked Sendable {
    private struct State: Codable {
        var verifier: String
    }

    private let stateURL: URL
    private let lock = NSLock()
    private var verifier: String?

    public init(stateDirectory: URL) {
        stateURL = stateDirectory.appendingPathComponent("passcode.json")
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        load()
        // 已有口令的用户在启动时就把旧 Keychain 密钥迁移到 JSON；
        // 如果密钥确实缺失，不要静默生成新密钥覆盖旧 passcode，交给 verify 返回失败。
        if verifier != nil {
            _ = LANSharePasscodeKey.loadExistingKey()
        }
    }

    public var hasPasscode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return verifier != nil
    }

    /// 设置口令；传入 nil 时自动生成 6 位数字并返回，便于 UI 展示一次。
    @discardableResult
    public func setPasscode(_ code: String?) throws -> String {
        let passcode: String
        if let code {
            guard code.count == 6, code.allSatisfy(\.isNumber) else {
                throw LANShareError.invalidRequest
            }
            passcode = code
        } else {
            passcode = Self.generatePasscode()
        }
        let key = LANSharePasscodeKey.loadOrCreateKey()
        let digest = HMAC<SHA256>.authenticationCode(for: Data(passcode.utf8), using: SymmetricKey(data: key))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        verifier = hex
        lock.unlock()
        persist()
        return passcode
    }

    public func clear() {
        lock.lock()
        verifier = nil
        lock.unlock()
        try? FileManager.default.removeItem(at: stateURL)
        _ = LANSharePasscodeKey.rotateKey()
    }

    public func verify(_ code: String) -> Bool {
        lock.lock()
        let current = verifier
        lock.unlock()
        guard let current,
              let key = LANSharePasscodeKey.loadExistingKey() else { return false }
        let digest = HMAC<SHA256>.authenticationCode(for: Data(code.utf8), using: SymmetricKey(data: key))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return LANShareConstantTime.equals(hex, current)
    }

    private func load() {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateURL.path
            )
        }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data),
              !state.verifier.isEmpty else { return }
        verifier = state.verifier
    }

    private func persist() {
        lock.lock()
        let current = verifier
        lock.unlock()
        guard let current else { return }
        let state = State(verifier: current)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateURL.path
        )
    }

    static func generatePasscode() -> String {
        var value: UInt32 = 0
        if SecRandomCopyBytes(kSecRandomDefault, 4, &value) != errSecSuccess {
            value = UInt32.random(in: 0..<1_000_000)
        }
        return String(format: "%06d", Int(value % 1_000_000))
    }
}
