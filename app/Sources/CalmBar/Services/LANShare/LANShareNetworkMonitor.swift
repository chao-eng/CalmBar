import Darwin
import Foundation
import Network

// MARK: - 网卡地址与前缀

public struct LANShareNetworkAddress: Equatable, Sendable {
    public enum Family: String, Sendable {
        case ipv4
        case ipv6
    }

    public let interfaceName: String
    public let address: String
    public let prefixLength: Int
    public let family: Family
    public let isLinkLocal: Bool

    public init(interfaceName: String, address: String, prefixLength: Int, family: Family, isLinkLocal: Bool) {
        self.interfaceName = interfaceName
        self.address = address
        self.prefixLength = prefixLength
        self.family = family
        self.isLinkLocal = isLinkLocal
    }

    public var displayAddress: String {
        family == .ipv6 ? "[\(address)]" : address
    }

    public var prefixText: String {
        "\(address)/\(prefixLength)"
    }

    /// 是否为 VPN / 桥接 / 隧道等虚拟网卡。
    public var isVirtual: Bool {
        LANShareNetworkInterfaces.isVirtualInterface(interfaceName)
    }

    public var hostHeaderValue: String {
        family == .ipv6 ? "[\(address)]" : address
    }

    /// 判断来源 IP 是否落在本网卡前缀内。
    public func contains(_ ip: String) -> Bool {
        let normalized = LANShareIP.unmapIPv4(ip)
        switch family {
        case .ipv4:
            guard let lhs = LANShareIP.ipv4Bytes(address), let rhs = LANShareIP.ipv4Bytes(normalized) else {
                return false
            }
            return LANShareIP.matchesPrefix(lhs, rhs, bits: prefixLength)
        case .ipv6:
            guard let lhs = LANShareIP.ipv6Bytes(address), let rhs = LANShareIP.ipv6Bytes(normalized) else {
                return false
            }
            return LANShareIP.matchesPrefix(lhs, rhs, bits: prefixLength)
        }
    }

    public func matchesHost(_ host: String) -> Bool {
        let cleaned = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: "%").first.map(String.init) ?? host
        return cleaned.caseInsensitiveCompare(address) == .orderedSame
    }
}

enum LANShareIP {
    static func unmapIPv4(_ ip: String) -> String {
        let lower = ip.lowercased()
        if lower.hasPrefix("::ffff:"), lower.contains(".") {
            return String(lower.dropFirst("::ffff:".count))
        }
        return ip
    }

    static func ipv4Bytes(_ ip: String) -> [UInt8]? {
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0.prefix(4)) }
    }

    static func ipv6Bytes(_ ip: String) -> [UInt8]? {
        var addr = in6_addr()
        let normalized = ip.split(separator: "%").first.map(String.init) ?? ip
        guard inet_pton(AF_INET6, normalized, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0.prefix(16)) }
    }

    static func matchesPrefix(_ lhs: [UInt8], _ rhs: [UInt8], bits: Int) -> Bool {
        guard lhs.count == rhs.count, bits >= 0, bits <= lhs.count * 8 else { return false }
        let fullBytes = bits / 8
        let remainder = bits % 8
        for index in 0..<fullBytes where lhs[index] != rhs[index] {
            return false
        }
        if remainder > 0 {
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - remainder))
            if (lhs[fullBytes] & mask) != (rhs[fullBytes] & mask) { return false }
        }
        return true
    }
}

// MARK: - 网卡枚举

public enum LANShareNetworkInterfaces {
    public static func availableAddresses() -> [LANShareNetworkAddress] {
        var result: [LANShareNetworkAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(bitPattern: current.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0,
                  let addressPointer = current.pointee.ifa_addr else { continue }

            let family = addressPointer.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            guard let item = makeAddress(interface: current) else { continue }
            result.append(item)
        }
        return result
    }

    public static func bestAddress(preferredInterface: String? = nil) -> LANShareNetworkAddress? {
        let addresses = availableAddresses()
        // 虚拟网卡（VPN/隧道/桥接）不作为默认网卡；手选也忽略，避免持久化的旧选择带来错误地址。
        if let preferredInterface,
           !isVirtualInterface(preferredInterface),
           let matched = addresses.first(where: { $0.interfaceName == preferredInterface }) {
            return matched
        }
        let candidates = addresses.filter { !$0.isVirtual }
        let ipv4 = candidates.filter {
            $0.family == .ipv4 && !$0.address.hasPrefix("169.254.") && $0.prefixLength >= 8
        }
        if let en0 = ipv4.first(where: { $0.interfaceName == "en0" }) { return en0 }
        if let physical = ipv4.sorted(by: { rank($0.interfaceName) < rank($1.interfaceName) }).first {
            return physical
        }

        let ipv6 = candidates.filter { $0.family == .ipv6 && !$0.isLinkLocal }
        if let first = ipv6.first { return first }
        return nil
    }

    /// 物理网卡排序：Wi-Fi（en0）优先，其次其他 en 开头的内建/USB 网卡。
    private static func rank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        return 2
    }

    /// utun/ipsec/ppp 等均为隧道或虚拟网卡，不能代表局域网。
    public static func isVirtualInterface(_ name: String) -> Bool {
        let prefixes = [
            "utun", "ipsec", "ppp", "tap", "tun", "awdl", "llw", "bridge",
            "gif", "stf", "anpi", "vmenet", "vmnet", "vnic", "dummy"
        ]
        let lower = name.lowercased()
        return prefixes.contains { lower.hasPrefix($0) }
    }

    private static func makeAddress(interface pointer: UnsafeMutablePointer<ifaddrs>) -> LANShareNetworkAddress? {
        guard let addressPointer = pointer.pointee.ifa_addr,
              let netmaskPointer = pointer.pointee.ifa_netmask else { return nil }
        let name = String(cString: pointer.pointee.ifa_name)
        return parseAddress(name: name, address: addressPointer, netmask: netmaskPointer)
    }

    /// 从 sockaddr 中解析地址与前缀长度。sockaddr 头部含 len/family/port，地址本体在偏移之后，必须按具体结构体读取。
    static func parseAddress(name: String, address: UnsafePointer<sockaddr>, netmask: UnsafePointer<sockaddr>) -> LANShareNetworkAddress? {
        let family = Int32(address.pointee.sa_family)

        if family == AF_INET {
            guard let ip = string(from: address, family: AF_INET),
                  let maskBytes = rawBytes(from: netmask, family: AF_INET) else { return nil }
            return LANShareNetworkAddress(
                interfaceName: name,
                address: ip,
                prefixLength: prefixLength(maskBytes),
                family: .ipv4,
                isLinkLocal: ip.hasPrefix("169.254.")
            )
        }

        if family == AF_INET6 {
            guard let ip = string(from: address, family: AF_INET6),
                  let maskBytes = rawBytes(from: netmask, family: AF_INET6) else { return nil }
            return LANShareNetworkAddress(
                interfaceName: name,
                address: ip,
                prefixLength: prefixLength(maskBytes),
                family: .ipv6,
                isLinkLocal: ip.lowercased().hasPrefix("fe80")
            )
        }
        return nil
    }

    private static func string(from pointer: UnsafePointer<sockaddr>, family: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result: UnsafePointer<CChar>?
        if family == AF_INET {
            let sin = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in.self)
            var ipv4 = sin.pointee.sin_addr
            result = inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(INET_ADDRSTRLEN))
        } else {
            let sin6 = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in6.self)
            var ipv6 = sin6.pointee.sin6_addr
            result = inet_ntop(AF_INET6, &ipv6, &buffer, socklen_t(INET6_ADDRSTRLEN))
        }
        guard result != nil else { return nil }
        return String(cString: buffer)
    }

    private static func rawBytes(from pointer: UnsafePointer<sockaddr>, family: Int32) -> [UInt8]? {
        if family == AF_INET {
            let sin = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in.self)
            return withUnsafeBytes(of: sin.pointee.sin_addr) { Array($0.prefix(4)) }
        }
        let sin6 = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in6.self)
        return withUnsafeBytes(of: sin6.pointee.sin6_addr) { Array($0.prefix(16)) }
    }

    private static func prefixLength(_ mask: [UInt8]) -> Int {
        var bits = 0
        for byte in mask {
            bits += byte.nonzeroBitCount
        }
        return bits
    }
}

// MARK: - 网络变化监听

public final class LANShareNetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.calmbar.lanshare.network")
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?
    private var isRunning = false

    public init() {}

    public func setChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }

    public func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let handler = self.onChange
            self.lock.unlock()
            handler?()
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        lock.unlock()
        monitor.cancel()
    }

    public func currentBestAddress(preferredInterface: String?) -> LANShareNetworkAddress? {
        LANShareNetworkInterfaces.bestAddress(preferredInterface: preferredInterface)
    }
}
