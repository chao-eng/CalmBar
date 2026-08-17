import Foundation
import CalmBarKit

final class CalmBarHelperService: NSObject, NSXPCListenerDelegate, CalmBarHelperProtocol, @unchecked Sendable {
    private let listener: NSXPCListener
    private var controller: FanController?
    private var connectionCount = 0
    private let lock = NSLock()

    init(machServiceName: String) {
        self.listener = NSXPCListener(machServiceName: machServiceName)
        super.init()
        self.listener.delegate = self
    }

    func start() {
        listener.resume()
        setupSignals()
        RunLoop.main.run()
    }

    private func setupSignals() {
        signal(SIGINT) { _ in
            exit(0)
        }
        signal(SIGTERM) { _ in
            exit(0)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: CalmBarHelperProtocol.self)
        newConnection.exportedObject = self
        lock.lock()
        connectionCount += 1
        lock.unlock()

        newConnection.invalidationHandler = { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.connectionCount = max(0, self.connectionCount - 1)
            let remaining = self.connectionCount
            self.lock.unlock()
            if remaining == 0 {
                try? self.getController().restoreSystemControl()
            }
        }
        newConnection.resume()
        return true
    }

    private func getController() throws -> FanController {
        if let c = controller { return c }
        let conn = try SMCConnection()
        let c = FanController(connection: conn)
        self.controller = c
        return c
    }

    private var battery: SMCBattery?

    private func getBattery() throws -> SMCBattery {
        if let b = battery { return b }
        let conn = try SMCConnection()
        let b = SMCBattery(connection: conn)
        self.battery = b
        return b
    }

    func ping(reply: @escaping (String) -> Void) {
        reply("pong:\(CalmBarConfig.helperVersion)")
    }

    func setLinkedFraction(_ fraction: Double, reply: @escaping (Bool, String?) -> Void) {
        do {
            let c = try getController()
            try c.setLinkedFraction(fraction)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func setFanRPM(_ fanIndex: UInt, rpm: Float, reply: @escaping (Bool, String?) -> Void) {
        do {
            let c = try getController()
            _ = try c.enableManualMode(fanIndex: Int(fanIndex))
            try c.setTargetRPM(fanIndex: Int(fanIndex), rpm: rpm)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func restoreAuto(reply: @escaping (Bool, String?) -> Void) {
        do {
            let c = try getController()
            try c.restoreSystemControl()
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func listFans(reply: @escaping ([Data]?, String?) -> Void) {
        do {
            let c = try getController()
            let fans = try c.allFans()
            let encoded = fans.compactMap { try? JSONEncoder().encode($0) }
            reply(encoded, nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func listTemperatures(reply: @escaping ([Data]?, String?) -> Void) {
        do {
            let c = try getController()
            let temps = c.readTemperatures(primaryOnly: false)
            let encoded = temps.compactMap { try? JSONEncoder().encode($0) }
            reply(encoded, nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func removeQuarantine(at path: String, deepSign: Bool, reply: @escaping (Bool, String?) -> Void) {
        guard FileManager.default.fileExists(atPath: path) else {
            reply(false, "目标文件或目录不存在: \(path)")
            return
        }

        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-rd", "com.apple.quarantine", path]

        let pipe = Pipe()
        xattrProcess.standardError = pipe
        xattrProcess.standardOutput = pipe

        do {
            try xattrProcess.run()
            xattrProcess.waitUntilExit()

            // If deepSign is requested, execute codesign --force --deep --sign -
            if deepSign {
                let signProcess = Process()
                signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                signProcess.arguments = ["--force", "--deep", "--sign", "-", path]
                let signPipe = Pipe()
                signProcess.standardError = signPipe
                signProcess.standardOutput = signPipe

                try signProcess.run()
                signProcess.waitUntilExit()

                if signProcess.terminationStatus != 0 {
                    let errData = signPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    reply(false, "去隔离已执行，但自签名失败: \(errMsg ?? "未知错误")")
                    return
                }
            }

            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    // MARK: - Battery & Charging Management

    func setBatteryChargingInhibited(_ inhibited: Bool, reply: @escaping (Bool, String?) -> Void) {
        do {
            let b = try getBattery()
            guard b.capabilities.inhibitChargeControl else {
                reply(false, "当前 Mac 硬件不支持 SMC 充电阻断控制")
                return
            }
            try b.setChargingInhibited(inhibited)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func setBatteryForceDischarge(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        do {
            let b = try getBattery()
            guard b.capabilities.forceDischargeControl else {
                reply(false, "当前 Mac 硬件不支持 SMC 强制放电控制")
                return
            }
            try b.setForceDischarging(enabled)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func getBatterySMCStatus(reply: @escaping (Bool, Bool, Bool, String?) -> Void) {
        do {
            let b = try getBattery()
            let hasSupport = b.capabilities.inhibitChargeControl
            let isInhibited = (try? b.getChargingInhibited()) ?? false
            let isForcedDischarge = (try? b.getForceDischarging()) ?? false
            reply(hasSupport, isInhibited, isForcedDischarge, nil)
        } catch {
            reply(false, false, false, error.localizedDescription)
        }
    }
}

@main
struct CalmBarHelperMain {
    static func main() {
        let service = CalmBarHelperService(machServiceName: CalmBarConfig.helperMachService)
        service.start()
    }
}
