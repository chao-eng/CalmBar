import Foundation
import IOKit

public enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

public enum SMCResultCode: UInt8, CustomStringConvertible, Sendable {
    case success = 0x00
    case error = 0x01
    case commCollision = 0x80
    case spuriousData = 0x81
    case badCommand = 0x82
    case badParameter = 0x83
    case notFound = 0x84
    case notReadable = 0x85
    case notWritable = 0x86
    case keySizeMismatch = 0x87
    case framingError = 0x88
    case badArgumentError = 0x89

    public var description: String {
        let name: String
        switch self {
        case .success: name = "success"
        case .error: name = "error"
        case .commCollision: name = "commCollision"
        case .spuriousData: name = "spuriousData"
        case .badCommand: name = "badCommand"
        case .badParameter: name = "badParameter"
        case .notFound: name = "notFound"
        case .notReadable: name = "notReadable"
        case .notWritable: name = "notWritable"
        case .keySizeMismatch: name = "keySizeMismatch"
        case .framingError: name = "framingError"
        case .badArgumentError: name = "badArgumentError"
        }
        return "\(name) (0x\(String(rawValue, radix: 16)))"
    }
}

public enum SMCError: LocalizedError, Sendable {
    case connectionFailed
    case firmware(SMCResultCode)
    case ioKit(kern_return_t)
    case timeout
    case invalidKey

    public var errorDescription: String? {
        switch self {
        case .connectionFailed: return "无法连接 AppleSMC 硬件驱动（请检查权限或系统兼容性）"
        case .firmware(let code): return "SMC 固件错误: \(code)"
        case .ioKit(let code): return "IOKit 错误: 0x\(String(code, radix: 16))"
        case .timeout: return "SMC 操作超时"
        case .invalidKey: return "无效的 SMC 寄存器键"
        }
    }
}

public struct SMCParamStruct {
    public typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    public struct Version {
        public var major: UInt8 = 0
        public var minor: UInt8 = 0
        public var build: UInt8 = 0
        public var reserved: UInt8 = 0
        public var release: UInt16 = 0
        public init() {}
    }

    public struct PLimitData {
        public var version: UInt16 = 0
        public var length: UInt16 = 0
        public var cpuPLimit: UInt32 = 0
        public var gpuPLimit: UInt32 = 0
        public var memPLimit: UInt32 = 0
        public init() {}
    }

    public struct KeyInfo {
        public var dataSize: UInt32 = 0
        public var dataType: UInt32 = 0
        public var dataAttributes: UInt8 = 0
        public init() {}
    }

    public var key: UInt32 = 0
    public var vers = Version()
    public var pLimitData = PLimitData()
    public var keyInfo = KeyInfo()
    public var padding: UInt16 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    public init() {}
}

public enum SMCDataFormat: Sendable {
    public static func float(from bytes: [UInt8], size: UInt32) -> Float {
        if size == 4, bytes.count >= 4 {
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        }
        if size == 2, bytes.count >= 2 {
            let raw = Int16(bigEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
            return Float(raw) / 256.0
        }
        if bytes.count >= 2 {
            let raw = UInt16(bigEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
            return Float(raw) / 4.0
        }
        if let first = bytes.first { return Float(first) }
        return 0
    }

    public static func bytes(from value: Float, size: UInt32) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: Int(size))
        if size == 4 {
            withUnsafeBytes(of: value) { buf in
                for i in 0..<4 { result[i] = buf[i] }
            }
        } else if size == 2 {
            let raw = UInt16(max(0, value) * 4.0)
            result[0] = UInt8(raw >> 8)
            result[1] = UInt8(raw & 0xFF)
        } else if size == 1 {
            result[0] = UInt8(clamping: Int(value))
        }
        return result
    }

    public static func uint8(from bytes: [UInt8]) -> UInt8 {
        bytes.first ?? 0
    }

    public static func uint32(from bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else { return 0 }
        return bytes.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
}

public final class SMCConnection: @unchecked Sendable {
    private let connection: io_connect_t

    public init() throws {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        let mainPort = kIOMainPortDefault
        guard IOServiceGetMatchingServices(mainPort, IOServiceMatching("AppleSMC"), &iterator)
            == kIOReturnSuccess
        else {
            throw SMCError.connectionFailed
        }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { throw SMCError.connectionFailed }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            throw SMCError.connectionFailed
        }
        self.connection = conn
    }

    deinit {
        IOServiceClose(connection)
    }

    public static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(bytes: model.prefix { $0 != 0 }.map { UInt8($0) }, encoding: .utf8) ?? ""
    }

    public func fourCharCode(from string: String) throws -> UInt32 {
        guard string.utf8.count == 4 else { throw SMCError.invalidKey }
        return string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public func bytesToTuple(_ array: [UInt8]) -> SMCParamStruct.Bytes32 {
        var padded = array + Array(repeating: 0, count: max(0, 32 - array.count))
        if padded.count > 32 { padded = Array(padded.prefix(32)) }
        return (
            padded[0], padded[1], padded[2], padded[3],
            padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11],
            padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19],
            padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27],
            padded[28], padded[29], padded[30], padded[31]
        )
    }

    public func callSMC(input: SMCParamStruct) throws -> SMCParamStruct {
        var inp = input
        var out = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &inp,
            MemoryLayout<SMCParamStruct>.stride,
            &out,
            &outSize
        )
        guard result == kIOReturnSuccess else { throw SMCError.ioKit(result) }
        return out
    }

    public func fetchKeyInfo(_ key: String) throws -> (SMCParamStruct, SMCParamStruct) {
        var param = SMCParamStruct()
        param.key = try fourCharCode(from: key)
        param.data8 = SMCCommand.readKeyInfo.rawValue
        let output = try callSMC(input: param)
        if output.result != SMCResultCode.success.rawValue {
            throw SMCError.firmware(SMCResultCode(rawValue: output.result) ?? .error)
        }
        return (param, output)
    }

    public func readKey(_ key: String) throws -> (bytes: [UInt8], size: UInt32) {
        let (param, output) = try fetchKeyInfo(key)
        let dataSize = output.keyInfo.dataSize
        guard dataSize > 0 && dataSize <= 32 else { throw SMCError.invalidKey }
        var readParam = param
        readParam.keyInfo = output.keyInfo
        readParam.data8 = SMCCommand.readBytes.rawValue
        let readOutput = try callSMC(input: readParam)
        if readOutput.result != SMCResultCode.success.rawValue {
            throw SMCError.firmware(SMCResultCode(rawValue: readOutput.result) ?? .error)
        }
        let bytes = withUnsafeBytes(of: readOutput.bytes) { Array($0.prefix(Int(dataSize))) }
        return (bytes, dataSize)
    }

    public func writeKey(_ key: String, bytes: [UInt8]) throws {
        let (param, output) = try fetchKeyInfo(key)
        var writeParam = param
        writeParam.data8 = SMCCommand.writeBytes.rawValue
        // Match Aidente's smc.c SMCWriteKey: only set dataSize, NOT dataType/dataAttributes
        // in the write command struct. The AppleSMC kernel driver behaves differently
        // when dataType is included vs omitted.
        writeParam.keyInfo.dataSize = output.keyInfo.dataSize
        writeParam.keyInfo.dataType = 0
        writeParam.keyInfo.dataAttributes = 0
        writeParam.bytes = bytesToTuple(bytes)
        let writeOutput = try callSMC(input: writeParam)
        if writeOutput.result != SMCResultCode.success.rawValue {
            throw SMCError.firmware(SMCResultCode(rawValue: writeOutput.result) ?? .error)
        }
    }

    public func keyExists(_ key: String) -> Bool {
        (try? fetchKeyInfo(key)) != nil
    }
}
