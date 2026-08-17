import Foundation
import IOKit.ps
import Combine

/// Real-time monitor for macOS battery state, power sources, health, and cycle count
@MainActor
public final class BatteryMonitor: ObservableObject {
    public static let shared = BatteryMonitor()

    @Published public private(set) var hasBattery: Bool = false
    @Published public private(set) var currentPercentage: Int = 100
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var isACPowered: Bool = true
    @Published public private(set) var isAdapterPhysicallyConnected: Bool = true
    @Published public private(set) var isCharged: Bool = false
    @Published public private(set) var timeToFullMinutes: Int?
    @Published public private(set) var timeToEmptyMinutes: Int?
    @Published public private(set) var cycleCount: Int = 0
    @Published public private(set) var healthPercentage: Int = 100
    @Published public private(set) var batteryCondition: String = "正常"
    @Published public private(set) var temperatureCelsius: Double = 0

    private var pollTimer: Timer?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        refreshBatteryInfo()
        setupPowerSourceNotification()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBatteryInfo()
            }
        }
    }

    public func refreshBatteryInfo() {
        var adapterWatts = 0.0
        if let unmanagedDetails = IOPSCopyExternalPowerAdapterDetails() {
            let details = unmanagedDetails.takeRetainedValue() as NSDictionary
            if let watts = details["Watts"] as? NSNumber {
                adapterWatts = watts.doubleValue
            }
        }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            guard let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType else {
                continue
            }

            self.hasBattery = true

            let curCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            self.currentPercentage = maxCap > 0 ? (curCap * 100 / maxCap) : curCap

            self.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false

            let powerState = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            self.isACPowered = (powerState == kIOPSACPowerValue)
            self.isAdapterPhysicallyConnected = self.isACPowered || (adapterWatts > 0)

            self.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? (currentPercentage >= 100)

            let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            self.timeToFullMinutes = timeToFull > 0 ? timeToFull : nil

            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            self.timeToEmptyMinutes = timeToEmpty > 0 ? timeToEmpty : nil

            break
        }

        readSmartBatteryDetails()
    }

    private func readSmartBatteryDetails() {
        var service: io_service_t = 0
        let matching = IOServiceMatching("AppleSmartBattery")
        service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }

        if let isCharging = dict["IsCharging"] as? Bool {
            self.isCharging = isCharging
        }

        if let amperage = dict["InstantAmperage"] as? Int, amperage <= 0 {
            self.isCharging = false
        } else if let rawAmp = dict["Amperage"] as? Int, rawAmp <= 0 {
            self.isCharging = false
        }

        if let cycles = dict["CycleCount"] as? Int {
            self.cycleCount = cycles
        }

        let maxCapacity = dict["MaxCapacity"] as? Double ?? dict["AppleRawMaxCapacity"] as? Double ?? 0
        let designCapacity = dict["DesignCapacity"] as? Double ?? 0
        if maxCapacity > 0 && designCapacity > 0 {
            self.healthPercentage = min(100, max(0, Int((maxCapacity / designCapacity) * 100)))
        }

        if let tempRaw = dict["Temperature"] as? Double {
            // Temperature is in 1/100 of Celsius (e.g. 2950 = 29.50°C)
            self.temperatureCelsius = tempRaw / 100.0
        }

        if let condition = dict["Condition"] as? String {
            self.batteryCondition = condition
        }

        // Match Aidente: Extract adapter wattage from IORegistry AdapterDetails / AppleRawAdapterDetails.
        // During SMC force discharge, IOPSCopyExternalPowerAdapterDetails() is nil and ExternalConnected is 0,
        // but AppleSmartBattery retains AdapterDetails with Watts > 0 if physically plugged in.
        var registryWatts: Double = 0
        if let details = dict["AdapterDetails"] as? [String: Any],
           let watts = details["Watts"] as? NSNumber {
            registryWatts = watts.doubleValue
        } else if let rawDetails = dict["AppleRawAdapterDetails"] as? [[String: Any]] {
            for item in rawDetails {
                if let watts = item["Watts"] as? NSNumber, watts.doubleValue > registryWatts {
                    registryWatts = watts.doubleValue
                }
            }
        }

        if registryWatts > 0 {
            self.isAdapterPhysicallyConnected = true
        }
    }

    private func setupPowerSourceNotification() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in
                monitor.refreshBatteryInfo()
            }
        }, context)?.takeRetainedValue()

        if let source = source {
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}
