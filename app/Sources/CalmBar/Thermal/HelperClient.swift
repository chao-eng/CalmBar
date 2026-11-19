import AppKit
import Foundation
import Security
import CalmBarKit

private enum XPCProxyHelper {
    static func proxy(for connection: NSXPCConnection, errorHandler: @escaping @Sendable (Error) -> Void) -> CalmBarHelperProtocol? {
        return connection.remoteObjectProxyWithErrorHandler(errorHandler) as? CalmBarHelperProtocol
    }
}

@MainActor
public final class HelperClient: ObservableObject {
    public static let shared = HelperClient()

    @Published public private(set) var isHelperAvailable: Bool = false
    @Published public private(set) var needsHelperUpdate: Bool = false
    @Published public private(set) var lastError: String? = nil

    private var connection: NSXPCConnection?

    public static var isHelperInstalledOnDisk: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.chaoeng.CalmBar.helper.plist") &&
        FileManager.default.fileExists(atPath: "/usr/local/libexec/CalmBarHelper")
    }

    /// Helper files exist on disk, but XPC communication is blocked (typically by macOS 13+ Background Items toggle)
    public var isHelperBlockedBySystem: Bool {
        Self.isHelperInstalledOnDisk && !isHelperAvailable && !needsHelperUpdate
    }

    /// Open macOS System Settings -> General -> Login Items & Extensions (Background Items)
    public static func openBackgroundItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.general?LoginItems") {
            NSWorkspace.shared.open(fallback)
        } else if let legacyFallback = URL(string: "x-apple.systempreferences:com.apple.preferences.users") {
            NSWorkspace.shared.open(legacyFallback)
        }
    }

    /// Shows an explanatory dialog before opening system background items settings
    public static func promptAndOpenBackgroundSettings() {
        let alert = NSAlert()
        alert.messageText = "需要开启「允许在后台」权限"
        alert.informativeText = "检测到 CalmBar 特权守护服务已安装，但当前被 macOS 系统「允许在后台」机制阻止。\n\n即将为您打开「系统设置 ➔ 通用 ➔ 登录项与扩展」，请在列表中找到【CalmBarHelper】并将开关开启为蓝色。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往开启")
        alert.addButton(withTitle: "取消")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openBackgroundItemsSettings()
        }
        
        // Auto-poll after user interacts with the prompt or goes to settings
        shared.pollHelperStatusUntilReady()
    }

    private init() {
        checkHelperStatus()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkHelperStatus()
            }
        }
    }

    /// Automatically poll for helper status after user goes to system settings
    public func pollHelperStatusUntilReady(maxAttempts: Int = 10, interval: TimeInterval = 1.0) {
        Task { @MainActor in
            for _ in 0..<maxAttempts {
                self.checkHelperStatus()
                if self.isHelperAvailable {
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func checkHelperStatus() {
        guard Self.isHelperInstalledOnDisk else {
            self.isHelperAvailable = false
            self.needsHelperUpdate = false
            return
        }

        guard let proxy = getProxy(errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
                self?.needsHelperUpdate = Self.helperHeartbeatIsFresh()
                self?.lastError = error.localizedDescription
            }
        }) else {
            self.isHelperAvailable = false
            return
        }

        proxy.ping { [weak self] reply in
            DispatchQueue.main.async {
                let isLatest = (reply == "pong:\(CalmBarConfig.helperVersion)")
                self?.isHelperAvailable = isLatest
                self?.needsHelperUpdate = !isLatest
                if !isLatest {
                    self?.lastError = "特权服务版本过旧（需更新安全校验与硬件控制），请点击一键激活升级"
                } else {
                    self?.lastError = nil
                }
            }
        }
    }

    /// Helper 存活时会每 30 秒刷新该文件；文件新鲜但 ping 失败，通常意味着
    /// Helper 在运行但拒绝了当前客户端（签名/配置），而不是被后台项目阻止。
    /// 旧版 Helper 在重装前仍以 root 运行且没有客户端签名校验。
    /// 新版本首次启动时弹一次窗口，避免用户只看到不显眼的设置页提示。
    public func promptForSecurityUpdateIfNeeded() {
        guard Self.isHelperInstalledOnDisk, !isHelperAvailable else { return }
        // 旧 Helper 没有心跳文件；v6 被后台阻止/签名校验失败时也不能只依赖 ping。
        guard needsHelperUpdate || !Self.helperHeartbeatIsFresh() else { return }
        let promptedKey = "helper.securityUpdatePrompted.\(CalmBarConfig.helperVersion)"
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedKey)

        let alert = NSAlert()
        alert.messageText = "需要更新特权助手"
        alert.informativeText = "特权助手未响应或版本过旧。旧版缺少客户端签名校验，请先完成一次管理员授权来更新；若更新后仍未响应，再检查系统「允许在后台」权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestInstallHelper { _, _ in }
        }
    }

    private static func helperHeartbeatIsFresh(maxAge: TimeInterval = 90) -> Bool {
        let path = CalmBarConfig.helperHeartbeatPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) <= maxAge
    }

    private func getProxy(errorHandler: @escaping @Sendable (Error) -> Void) -> CalmBarHelperProtocol? {
        guard Self.isHelperInstalledOnDisk else {
            errorHandler(NSError(domain: "CalmBar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper 未安装，请先点击一键激活"]))
            return nil
        }

        if let existing = connection {
            let proxy = XPCProxyHelper.proxy(for: existing) { [weak self] error in
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                    errorHandler(error)
                }
            }
            if let valid = proxy {
                return valid
            }
        }

        let conn = NSXPCConnection(machServiceName: CalmBarConfig.helperMachService, options: [.privileged])
        conn.remoteObjectInterface = NSXPCInterface(with: CalmBarHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
                self?.connection = nil
                RecoveryCoordinator.shared.performRecovery(reason: .helperDisconnected)
            }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
                self?.connection = nil
                RecoveryCoordinator.shared.performRecovery(reason: .helperDisconnected)
            }
        }
        conn.resume()
        self.connection = conn

        return XPCProxyHelper.proxy(for: conn) { [weak self] error in
            DispatchQueue.main.async {
                self?.lastError = error.localizedDescription
                errorHandler(error)
            }
        }
    }

    public func setLinkedFraction(_ fraction: Double, completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未安装或未运行")
            return
        }
        proxy.setLinkedFraction(fraction) { [weak self] success, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    /// 单风扇独立调速（双风扇分别控制）
    public func setFanFraction(_ fanIndex: UInt, fraction: Double, completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未安装或未运行")
            return
        }
        proxy.setFanFraction(fanIndex, fraction: fraction) { [weak self] success, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    public func restoreAuto(completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未安装或未运行")
            return
        }
        proxy.restoreAuto { [weak self] success, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    /// 生成特权 Helper 安装脚本。
    ///
    /// `clientRequirement` 是主程序自身的 designated requirement，会写入
    /// root-only 配置文件，供 Helper 校验后续 XPC 连接；helperBinaryPath 与
    /// requirement 均以 base64 传入，避免路径中的引号/特殊字符破坏脚本。
    public static func installHelperScript(helperBinaryPath: String,
                                           clientRequirement: String,
                                           clientExecutablePath: String) -> String {
        let helperDst = "/usr/local/libexec/CalmBarHelper"
        let plistDst = "/Library/LaunchDaemons/com.chaoeng.CalmBar.helper.plist"
        let configDir = CalmBarConfig.helperConfigDirectory
        let requirementPath = CalmBarConfig.helperClientRequirementPath
        let clientPathFile = CalmBarConfig.helperClientPathFile
        let requirementBase64 = Data(clientRequirement.utf8).base64EncodedString()
        let helperPathBase64 = Data(helperBinaryPath.utf8).base64EncodedString()
        let clientPathBase64 = Data(clientExecutablePath.utf8).base64EncodedString()

        return """
        HELPER_SRC_B64='\(helperPathBase64)'
        HELPER_SRC=$(printf '%s' "$HELPER_SRC_B64" | /usr/bin/base64 -D)
        mkdir -p /usr/local/libexec '\(configDir)' && \
        chown root:wheel '\(configDir)' && \
        chmod 755 '\(configDir)' && \
        cp "$HELPER_SRC" '\(helperDst)' && \
        chmod 755 '\(helperDst)' && \
        printf '%s' '\(requirementBase64)' | /usr/bin/base64 -D > '\(requirementPath)' && \
        printf '%s' '\(clientPathBase64)' | /usr/bin/base64 -D > '\(clientPathFile)' && \
        chmod 600 '\(requirementPath)' '\(clientPathFile)' && \
        chown root:wheel '\(requirementPath)' '\(clientPathFile)' && \
        cat << 'EOF' > '\(plistDst)'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.chaoeng.CalmBar.helper</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperDst)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>com.chaoeng.CalmBar.helper</key>
                <true/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        EOF
        chmod 644 '\(plistDst)' && \
        launchctl bootout system/com.chaoeng.CalmBar.helper 2>/dev/null || true
        killall CalmBarHelper 2>/dev/null || true
        sleep 0.3 && \
        launchctl bootstrap system '\(plistDst)' && \
        launchctl enable system/com.chaoeng.CalmBar.helper && \
        launchctl kickstart -k system/com.chaoeng.CalmBar.helper
        """
    }

    /// 读取当前主程序的 designated requirement。生产包使用固定自签名证书时，
    /// 该 requirement 在应用升级后保持稳定；ad-hoc 构建会退化为 cdhash。
    private static func clientDesignatedRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var requirement: SecRequirement?
        if SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
           let requirement {
            var text: CFString?
            if SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
               let text {
                let value = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }

        // 极少数未生成 designated requirement 的构建，退化为 cdhash 绑定。
        var information: CFDictionary?
        if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
           let dictionary = information as? [String: Any],
           let unique = dictionary[kSecCodeInfoUnique as String] as? Data,
           !unique.isEmpty {
            let hex = unique.map { String(format: "%02x", $0) }.joined()
            return "cdhash H\"\(hex)\""
        }
        return nil
    }

    public func requestInstallHelper(completion: @escaping @MainActor (Bool, String?) -> Void) {
        self.connection?.invalidate()
        self.connection = nil

        let bundleURL = Bundle.main.bundleURL
        var helperPath = bundleURL.appendingPathComponent("Contents/MacOS/CalmBarHelper").path
        if !FileManager.default.fileExists(atPath: helperPath) {
            let localDebug = bundleURL.deletingLastPathComponent().appendingPathComponent("CalmBarHelper").path
            if FileManager.default.fileExists(atPath: localDebug) {
                helperPath = localDebug
            }
        }

        guard let clientRequirement = Self.clientDesignatedRequirement() else {
            completion(false, "无法读取应用签名，已停止安装特权助手")
            return
        }
        let clientExecutablePath = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? ""
        guard !clientExecutablePath.isEmpty else {
            completion(false, "无法读取应用可执行文件路径，已停止安装特权助手")
            return
        }
        let script = Self.installHelperScript(
            helperBinaryPath: helperPath,
            clientRequirement: clientRequirement,
            clientExecutablePath: clientExecutablePath
        )
        let appleScript = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            let scriptObj = NSAppleScript(source: appleScript)
            _ = scriptObj?.executeAndReturnError(&errorInfo)

            DispatchQueue.main.async {
                if let err = errorInfo {
                    let msg = err[NSAppleScript.errorMessage] as? String ?? "安装取消或失败"
                    completion(false, msg)
                } else {
                    self.checkHelperStatus()
                    completion(true, nil)
                    Self.showPostInstallGuidanceAlert()
                }
            }
        }
    }

    /// Shows a native guidance modal dialog after successful helper installation
    public static func showPostInstallGuidanceAlert() {
        let alert = NSAlert()
        alert.messageText = "特权助手已成功激活"
        alert.informativeText = "底层硬件控制驱动已就绪！\n\n在 macOS 13+ (Ventura / Sonoma / Sequoia) 中，若系统弹出「已添加后台项目」通知，请务必保持【CalmBarHelper 允许在后台】开关开启，以确保电脑休眠唤醒后风扇温控与充电保护持续生效。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "我知道了")
        alert.addButton(withTitle: "查看后台设置...")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            openBackgroundItemsSettings()
        }
    }

    public func removeQuarantine(at path: String, deepSign: Bool, completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未就绪")
            return
        }

        proxy.removeQuarantine(at: path, deepSign: deepSign) { [weak self] success, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    // MARK: - Battery & Charging Management

    public func setBatteryChargingInhibited(_ inhibited: Bool, completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未就绪")
            return
        }

        proxy.setBatteryChargingInhibited(inhibited) { [weak self] success, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    public func setBatteryForceDischarge(_ enabled: Bool, completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未就绪")
            return
        }

        proxy.setBatteryForceDischarge(enabled) { [weak self] success, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    public func getBatterySMCStatus(completion: @escaping @MainActor (Bool, Bool, Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            DispatchQueue.main.async { completion(false, false, false, err.localizedDescription) }
        }) else {
            completion(false, false, false, "Helper 未就绪")
            return
        }

        proxy.getBatterySMCStatus { [weak self] hasSupport, isInhibited, isForcedDischarge, err in
            DispatchQueue.main.async {
                self?.isHelperAvailable = hasSupport || (err == nil)
                completion(hasSupport, isInhibited, isForcedDischarge, err)
            }
        }
    }
}

