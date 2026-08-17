import Foundation
import CalmBarKit

@MainActor
public final class HelperClient: ObservableObject {
    public static let shared = HelperClient()

    @Published public private(set) var isHelperAvailable: Bool = false
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
            return
        }

        let conn = NSXPCConnection(machServiceName: CalmBarConfig.helperMachService, options: [.privileged])
        conn.remoteObjectInterface = NSXPCInterface(with: CalmBarHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isHelperAvailable = false
            }
        }
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isHelperAvailable = false
            }
        }
        conn.resume()

        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                self?.isHelperAvailable = false
                conn.invalidate()
            }
        } as? CalmBarHelperProtocol

        guard let validProxy = proxy else {
            self.isHelperAvailable = false
            conn.invalidate()
            return
        }

        validProxy.ping { [weak self] reply in
            Task { @MainActor in
                self?.isHelperAvailable = reply.starts(with: "pong")
                conn.invalidate()
            }
        }
    }

    private func getProxy(errorHandler: @escaping @Sendable (Error) -> Void) -> CalmBarHelperProtocol? {
        guard Self.isHelperInstalledOnDisk else {
            errorHandler(NSError(domain: "CalmBar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Helper 未安装，请先点击一键激活"]))
            return nil
        }

        if let existing = connection {
            if let proxy = existing.remoteObjectProxyWithErrorHandler({ [weak self] error in
                Task { @MainActor in
                    self?.isHelperAvailable = false
                    self?.lastError = error.localizedDescription
                    errorHandler(error)
                }
            }) as? CalmBarHelperProtocol {
                return proxy
            }
        }

        let conn = NSXPCConnection(machServiceName: CalmBarConfig.helperMachService, options: [.privileged])
        conn.remoteObjectInterface = NSXPCInterface(with: CalmBarHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isHelperAvailable = false
                self?.connection = nil
            }
        }
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isHelperAvailable = false
                self?.connection = nil
            }
        }
        conn.resume()
        self.connection = conn

        return conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.isHelperAvailable = false
                self?.lastError = error.localizedDescription
                errorHandler(error)
            }
        } as? CalmBarHelperProtocol
    }

    public func setLinkedFraction(_ fraction: Double, completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            Task { @MainActor in completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未安装或未运行")
            return
        }
        proxy.setLinkedFraction(fraction) { [weak self] success, err in
            Task { @MainActor in
                self?.isHelperAvailable = success || (err == nil)
                completion(success, err)
            }
        }
    }

    public func restoreAuto(completion: @escaping @MainActor (Bool, String?) -> Void) {
        guard let proxy = getProxy(errorHandler: { err in
            Task { @MainActor in completion(false, err.localizedDescription) }
        }) else {
            completion(false, "Helper 未安装或未运行")
            return
        }
        proxy.restoreAuto { [weak self] success, err in
            Task { @MainActor in
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
        launchctl bootstrap system '\(plistDst)' && \
        launchctl enable system/com.chaoeng.CalmBar.helper
        """
    }

    public func requestInstallHelper(completion: @escaping @MainActor (Bool, String?) -> Void) {
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
}
