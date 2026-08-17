import Foundation
import IOKit

public enum SMCBatteryError: Error, LocalizedError, Sendable {
    case unsupportedCapability
    case smcError(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCapability: return "当前 Mac 硬件不支持通过 SMC 阻断电池充电"
        case .smcError(let msg): return "SMC 电池操作失败: \(msg)"
        }
    }
}

public struct BatteryCapabilities: Codable, Sendable {
    public let inhibitChargeControl: Bool
    public let forceDischargeControl: Bool

    public init(inhibitChargeControl: Bool, forceDischargeControl: Bool) {
        self.inhibitChargeControl = inhibitChargeControl
        self.forceDischargeControl = forceDischargeControl
    }
}

/// Low-level AppleSMC battery charging inhibition and adapter control
public final class SMCBattery: @unchecked Sendable {
    public let capabilities: BatteryCapabilities

    private let connection: SMCConnection
    private let hasCH0C: Bool
    private let hasCHTE: Bool
    private let hasCH0I: Bool
    private let hasCHIE: Bool
    private let lock = NSLock()

    public init(connection: SMCConnection) {
        self.connection = connection

        let hasCH0C = connection.keyExists("CH0C")
        let hasCHTE = connection.keyExists("CHTE")
        let hasCH0I = connection.keyExists("CH0I")
        let hasCHIE = connection.keyExists("CHIE")

        self.hasCH0C = hasCH0C
        self.hasCHTE = hasCHTE
        self.hasCH0I = hasCH0I
        self.hasCHIE = hasCHIE

        self.capabilities = BatteryCapabilities(
            inhibitChargeControl: hasCH0C || hasCHTE,
            forceDischargeControl: hasCH0I || hasCHIE
        )
    }

    /// Checks if charging is currently inhibited (blocked) by SMC
    public func getChargingInhibited() throws -> Bool {
        guard capabilities.inhibitChargeControl else { throw SMCBatteryError.unsupportedCapability }
        lock.lock()
        defer { lock.unlock() }

        // Match Aidente priority: read CHTE first, then CH0C
        if hasCHTE {
            let (bytes, _) = try connection.readKey("CHTE")
            let val = bytes.prefix(4).reduce(UInt32(0)) { acc, b in acc | UInt32(b) }
            return val != 0
        } else {
            let (bytes, _) = try connection.readKey("CH0C")
            return SMCDataFormat.uint8(from: bytes) != 0
        }
    }

    /// Sets charging inhibition state (true = stop charging, battery bypassed; false = allow normal charging)
    public func setChargingInhibited(_ inhibited: Bool) throws {
        guard capabilities.inhibitChargeControl else { throw SMCBatteryError.unsupportedCapability }
        lock.lock()
        defer { lock.unlock() }

        if !inhibited && hasCH0I {
            try? connection.writeKey("CH0I", bytes: [0])
        }

        // Match Aidente priority: write CHTE first (macOS monitors CHTE to update IsCharging), CH0C as fallback
        if hasCHTE {
            let val: UInt32 = inhibited ? 1 : 0
            let bytes = withUnsafeBytes(of: val) { Array($0) }
            try connection.writeKey("CHTE", bytes: bytes)
        } else {
            let val: UInt8 = inhibited ? 1 : 0
            try connection.writeKey("CH0C", bytes: [val])
        }
    }

    /// Checks if force discharging is currently active
    public func getForceDischarging() throws -> Bool {
        guard capabilities.forceDischargeControl else { throw SMCBatteryError.unsupportedCapability }
        lock.lock()
        defer { lock.unlock() }

        if hasCHIE {
            let (bytes, _) = try connection.readKey("CHIE")
            return bytes.first == 0x08
        } else {
            let (bytes, _) = try connection.readKey("CH0I")
            return (bytes.first ?? 0) != 0
        }
    }

    /// Sets force discharging state (true = force battery power even with adapter; false = normal)
    public func setForceDischarging(_ enabled: Bool) throws {
        guard capabilities.forceDischargeControl else { throw SMCBatteryError.unsupportedCapability }
        lock.lock()
        defer { lock.unlock() }

        if enabled {
            // Clear charging inhibit before force discharge
            if hasCHTE {
                let zero: UInt32 = 0
                try? connection.writeKey("CHTE", bytes: withUnsafeBytes(of: zero) { Array($0) })
            } else if hasCH0C {
                try? connection.writeKey("CH0C", bytes: [0])
            }

            if hasCHIE {
                try connection.writeKey("CHIE", bytes: [0x08])
            } else {
                try connection.writeKey("CH0I", bytes: [1])
            }
        } else {
            if hasCHIE {
                try connection.writeKey("CHIE", bytes: [0x00])
            } else {
                try connection.writeKey("CH0I", bytes: [0])
            }
        }
    }

    /// Resets all SMC battery control registers back to system defaults (charging enabled)
    public func resetToDefaults() {
        if capabilities.inhibitChargeControl {
            try? setChargingInhibited(false)
        }
        if capabilities.forceDischargeControl {
            try? setForceDischarging(false)
        }
    }
}
