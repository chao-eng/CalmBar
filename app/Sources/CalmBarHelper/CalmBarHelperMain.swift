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

    func ping(reply: @escaping (String) -> Void) {
        reply("pong:1")
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
}

@main
struct CalmBarHelperMain {
    static func main() {
        let service = CalmBarHelperService(machServiceName: CalmBarConfig.helperMachService)
        service.start()
    }
}
