import Darwin
import Foundation
import IOKit

// MARK: - 公开 API 采样器（PRD BR-18，只读整机计数器）

struct SystemSampler {
    private var previousCPUTicks: [UInt32]?
    private var previousNetwork: (rx: UInt64, tx: UInt64, at: Date)?

    mutating func sample(cpuTemp: Double?, batteryLevel: Int?) -> MonitorSample {
        let now = Date()
        let cpu = readCPUUsage()
        let memory = readMemory()
        let disk = readDisk()
        let network = readNetwork(now: now)
        let gpu = readGPUUsage()
        let ip = readLocalIPv4()

        return MonitorSample(
            timestamp: now,
            cpuUsage: cpu,
            gpuUsage: gpu,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            memoryPressure: memory.pressure,
            diskFree: disk.free,
            diskTotal: disk.total,
            networkIn: network.rx,
            networkOut: network.tx,
            localIP: ip,
            cpuTemp: cpuTemp,
            batteryLevel: batteryLevel
        )
    }

    // MARK: CPU（host_statistics 差值）

    private mutating func readCPUUsage() -> Double {
        var info = host_cpu_load_info()
        var count = UInt32(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousCPUTicks = ticks }
        guard let previous = previousCPUTicks, previous.count == ticks.count else { return 0 }

        let deltas = zip(ticks, previous).map { current, last in
            current >= last ? current - last : (UInt32.max - last) &+ current &+ 1
        }
        let total = deltas.reduce(0) { $0 &+ $1 }
        guard total > 0 else { return 0 }
        // ticks 顺序：0=user、1=system、2=idle、3=nice，忙时需累加 user/system/nice
        let busy = deltas[0] &+ deltas[1] &+ deltas[3]
        return min(1, max(0, Double(busy) / Double(total)))
    }

    // MARK: 内存（host_statistics64 + 系统压力源）

    private func readMemory() -> (used: UInt64, total: UInt64, pressure: MemoryPressureLevel) {
        let total = ProcessInfo.processInfo.physicalMemory
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout.size(ofValue: stats) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (0, total, .normal)
        }

        let pages = UInt64(stats.active_count)
            &+ UInt64(stats.wire_count)
            &+ UInt64(stats.compressor_page_count)
        let used = min(total, pages &* UInt64(pageSize))
        return (used, total, readMemoryPressure(used: used, total: total))
    }

    private func readMemoryPressure(used: UInt64, total: UInt64) -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        if result == 0 {
            // 1 = normal / 2 = warning / 4 = critical
            if level >= 4 { return .critical }
            if level >= 2 { return .warning }
            return .normal
        }
        guard total > 0 else { return .normal }
        let ratio = Double(used) / Double(total)
        if ratio >= 0.9 { return .critical }
        if ratio >= 0.75 { return .warning }
        return .normal
    }

    // MARK: 磁盘

    private func readDisk() -> (free: UInt64, total: UInt64) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        else { return (0, 0) }
        let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        let total = (attributes[.systemSize] as? NSNumber)?.uint64Value ?? 0
        return (free, total)
    }

    // MARK: 网络（getifaddrs，64 位累计值差值）

    private mutating func readNetwork(now: Date) -> (rx: Double, tx: Double) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
            return (0, 0)
        }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data
            else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(stats.ifi_ibytes)
            tx &+= UInt64(stats.ifi_obytes)
        }

        defer { previousNetwork = (rx, tx, now) }
        guard let previous = previousNetwork else { return (0, 0) }
        let elapsed = max(0.2, now.timeIntervalSince(previous.at))
        let inbound = rx >= previous.rx ? Double(rx - previous.rx) / elapsed : 0
        let outbound = tx >= previous.tx ? Double(tx - previous.tx) / elapsed : 0
        return (inbound, outbound)
    }

    // MARK: 本机 IPv4

    private func readLocalIPv4() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    // MARK: GPU（IOKit，不可读返回 nil）

    private func readGPUUsage() -> Double? {
        var iterator = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any],
               let statistics = dictionary["PerformanceStatistics"] as? [String: Any] {
                for key in ["Device Utilization %", "GPU Busy %", "Renderer Utilization %"] {
                    if let number = statistics[key] as? NSNumber {
                        let value = min(1, max(0, number.doubleValue / 100))
                        best = max(best ?? 0, value)
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }
}
