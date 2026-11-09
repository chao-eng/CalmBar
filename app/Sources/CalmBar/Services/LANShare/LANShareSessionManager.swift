import Foundation
import Security

// MARK: - 会话

public struct LANShareSession: Sendable {
    public let token: String
    public let peerIP: String
    public let userAgent: String
    public var expiresAt: Date
    public var lastSeenAt: Date
}

// MARK: - 会话与认证

public final class LANShareSessionManager: @unchecked Sendable {
    public static let cookieName = "calmbar_session"
    public static let linkTokenBytes = 32

    private struct FailureState {
        var count: Int
        var lockedUntil: Date?
    }

    private let lock = NSLock()
    private let passcodeStore: LANSharePasscodeStore
    private var sessions: [String: LANShareSession] = [:]
    private var failures: [String: FailureState] = [:]
    private var globalFailures: [Date] = []
    private var linkToken: String
    private var passcodeEnabled: Bool
    private var onChange: (@Sendable () -> Void)?

    public init(passcodeStore: LANSharePasscodeStore, passcodeEnabled: Bool) {
        self.passcodeStore = passcodeStore
        self.passcodeEnabled = passcodeEnabled
        self.linkToken = Self.randomToken()
    }

    public func setChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }

    private func notifyChange() {
        lock.lock()
        let handler = onChange
        lock.unlock()
        handler?()
    }

    // MARK: 配置

    public func configure(passcodeEnabled: Bool, rotateToken: Bool) {
        lock.lock()
        let changed = self.passcodeEnabled != passcodeEnabled
        self.passcodeEnabled = passcodeEnabled
        if rotateToken || changed {
            linkToken = Self.randomToken()
            sessions.removeAll()
        }
        lock.unlock()
        if changed || rotateToken { notifyChange() }
    }

    public var currentLinkToken: String {
        lock.lock()
        defer { lock.unlock() }
        return linkToken
    }

    public var isPasscodeEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return passcodeEnabled
    }

    public var activeSessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked()
        return sessions.count
    }

    /// 停止服务时清空令牌与全部会话。
    public func revokeAll(rotateToken: Bool = true) {
        lock.lock()
        sessions.removeAll()
        failures.removeAll()
        globalFailures.removeAll()
        if rotateToken { linkToken = Self.randomToken() }
        lock.unlock()
        notifyChange()
    }

    public func invalidate(cookieHeader: String?) {
        guard let token = cookieValue(in: cookieHeader) else { return }
        lock.lock()
        sessions.removeValue(forKey: token)
        lock.unlock()
        notifyChange()
    }

    // MARK: 登录

    /// 返回会话 token；失败时抛出 401/429。
    public func login(
        linkToken suppliedToken: String?,
        passcode: String?,
        peerIP: String,
        userAgent: String
    ) throws -> String {
        lock.lock()

        let now = Date()
        pruneLocked()

        if let failure = failures[peerIP], let lockedUntil = failure.lockedUntil, lockedUntil > now {
            lock.unlock()
            throw LANShareError.rateLimited
        }
        globalFailures = globalFailures.filter { now.timeIntervalSince($0) < 60 }
        if globalFailures.count >= 30 {
            lock.unlock()
            throw LANShareError.rateLimited
        }

        var success = false
        if passcodeEnabled {
            if let passcode, !passcode.isEmpty, passcode.count == 6, passcodeStore.verify(passcode) {
                success = true
            }
        } else {
            if let suppliedToken, LANShareConstantTime.equals(suppliedToken, linkToken) {
                success = true
            }
        }

        guard success else {
            recordFailure(peerIP: peerIP, now: now)
            lock.unlock()
            throw LANShareError.unauthorized
        }

        failures.removeValue(forKey: peerIP)
        globalFailures.removeAll()

        // 清理过期会话，并在超过上限时逐出最早活跃的会话
        sessions = sessions.filter { $0.value.expiresAt > now }
        if sessions.count >= LANShareLimits.maxSessions,
           let oldest = sessions.min(by: { $0.value.lastSeenAt < $1.value.lastSeenAt }) {
            sessions.removeValue(forKey: oldest.key)
        }

        let token = Self.randomToken()
        sessions[token] = LANShareSession(
            token: token,
            peerIP: peerIP,
            userAgent: userAgent,
            expiresAt: now.addingTimeInterval(LANShareLimits.sessionTTL),
            lastSeenAt: now
        )
        lock.unlock()
        notifyChange()
        return token
    }

    // MARK: 会话校验

    /// 校验 Cookie 并滑动续期；返回 nil 表示未认证或已过期。
    public func authenticate(cookieHeader: String?, peerIP: String) -> LANShareSession? {
        guard let token = cookieValue(in: cookieHeader) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard var session = sessions[token], session.expiresAt > now else {
            sessions.removeValue(forKey: token)
            return nil
        }
        session.lastSeenAt = now
        session.expiresAt = now.addingTimeInterval(LANShareLimits.sessionTTL)
        sessions[token] = session
        return session
    }

    public func cookieValue(in header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<equals]
            if name == Self.cookieName {
                return String(trimmed[trimmed.index(after: equals)...])
            }
        }
        return nil
    }

    public func setCookieHeader(token: String) -> String {
        "\(Self.cookieName)=\(token); HttpOnly; SameSite=Strict; Path=/; Max-Age=\(Int(LANShareLimits.sessionTTL))"
    }

    public func clearCookieHeader() -> String {
        "\(Self.cookieName)=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"
    }

    // MARK: 私有

    private func recordFailure(peerIP: String, now: Date) {
        globalFailures.append(now)
        var state = failures[peerIP] ?? FailureState(count: 0, lockedUntil: nil)
        state.count += 1
        if state.count >= 10 {
            state.count = 0
            state.lockedUntil = now.addingTimeInterval(60)
        }
        failures[peerIP] = state
    }

    private func pruneLocked() {
        let now = Date()
        failures = failures.filter { entry in
            if let lockedUntil = entry.value.lockedUntil {
                return lockedUntil > now
            }
            return true
        }
    }

    static func randomToken(byteCount: Int = linkTokenBytes) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
