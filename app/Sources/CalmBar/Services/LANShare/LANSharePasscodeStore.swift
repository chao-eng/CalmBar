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

// MARK: - Keychain 密钥

enum LANShareKeychain {
    static let service = "com.calmbar.lanshare"
    static let account = "passcode-hmac-key"

    static func loadOrCreateKey() -> Data {
        if let existing = loadKey(), existing.count >= 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        let data = Data(bytes)
        saveKey(data)
        return data
    }

    static func rotateKey() -> Data {
        deleteKey()
        return loadOrCreateKey()
    }

    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func saveKey(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

// MARK: - 口令存储（HMAC verifier 落盘，密钥在 Keychain）

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
        let key = LANShareKeychain.loadOrCreateKey()
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
        _ = LANShareKeychain.rotateKey()
    }

    public func verify(_ code: String) -> Bool {
        lock.lock()
        let current = verifier
        lock.unlock()
        guard let current else { return false }
        let key = LANShareKeychain.loadOrCreateKey()
        let digest = HMAC<SHA256>.authenticationCode(for: Data(code.utf8), using: SymmetricKey(data: key))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return LANShareConstantTime.equals(hex, current)
    }

    private func load() {
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
    }

    static func generatePasscode() -> String {
        var value: UInt32 = 0
        if SecRandomCopyBytes(kSecRandomDefault, 4, &value) != errSecSuccess {
            value = UInt32.random(in: 0..<1_000_000)
        }
        return String(format: "%06d", Int(value % 1_000_000))
    }
}
