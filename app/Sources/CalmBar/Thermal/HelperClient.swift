import Foundation
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

    private init() {
        checkHelperStatus()
    }

    public func checkHelperStatus() {
        guard Self.isHelperInstalledOnDisk else {
            self.isHelperAvailable = false
            self.needsHelperUpdate = false
            return
        }

        let conn = NSXPCConnection(machServiceName: CalmBarConfig.helperMachService, options: [.privileged])
        conn.remoteObjectInterface = NSXPCInterface(with: CalmBarHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
            }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
            }
        }
        conn.resume()

        let proxy = XPCProxyHelper.proxy(for: conn) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
            }
        }

        guard let validProxy = proxy else {
            self.isHelperAvailable = false
            conn.invalidate()
            return
        }

        validProxy.ping { [weak self] reply in
            DispatchQueue.main.async {
                let isLatest = (reply == "pong:\(CalmBarConfig.helperVersion)")
                self?.isHelperAvailable = isLatest
                self?.needsHelperUpdate = !isLatest
                if !isLatest {
                    self?.lastError = "特权服务版本过旧（需更新以支持充电控制），请点击一键激活升级"
                }
            }
        }
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
            }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isHelperAvailable = false
                self?.connection = nil
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

    public static func installHelperScript(helperBinaryPath: String) -> String {
        let helperDst = "/usr/local/libexec/CalmBarHelper"
        let plistDst = "/Library/LaunchDaemons/com.chaoeng.CalmBar.helper.plist"

        return """
        mkdir -p /usr/local/libexec && \
        cp '\(helperBinaryPath)' '\(helperDst)' && \
        chmod 755 '\(helperDst)' && \
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

        let script = Self.installHelperScript(helperBinaryPath: helperPath)
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
                }
            }
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

