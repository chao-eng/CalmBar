import Accelerate
import AppKit
import CoreAudio
import Darwin
import Foundation

// MARK: - 数据模型

/// 输出设备（扬声器、耳机、显示器音频等）
struct AudioOutputDeviceInfo: Identifiable {
    let id: String          // 设备 UID，作为稳定标识
    let uid: String
    let name: String
    let isDefault: Bool
}

/// 一个按应用聚合后的音频行
struct AudioAppInfo: Identifiable {
    let id: String          // bundle id，缺失时退回 pid
    let bundleID: String?
    let pid: pid_t
    let name: String
    let audioObjectIDs: [AudioObjectID]
    let isPlaying: Bool
    let isProtected: Bool   // 系统声音/电话等受保护音频，不做接管
    var volume: Double      // 0...2
    var isMuted: Bool
    var outputDeviceUID: String?   // nil 表示跟随系统
    var icon: NSImage?
}

// MARK: - CoreAudio 基础读取

enum AudioCore {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    @discardableResult
    static func read<T>(_ object: AudioObjectID,
                        _ selector: AudioObjectPropertySelector,
                        _ value: inout T,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    static func objectList(_ object: AudioObjectID,
                           _ selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return [] }
        var objects = [AudioObjectID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).filter { $0 != 0 }
    }

    /// 当前存在的音频进程对象
    static func processObjects() -> [AudioObjectID] {
        guard #available(macOS 14.4, *) else { return [] }
        return objectList(systemObject, kAudioHardwarePropertyProcessObjectList)
    }

    static func pid(of object: AudioObjectID) -> pid_t? {
        var pid: pid_t = -1
        guard read(object, kAudioProcessPropertyPID, &pid), pid > 0 else { return nil }
        return pid
    }

    static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        _ = read(object, kAudioProcessPropertyIsRunningOutput, &running)
        return running != 0
    }

    static func bundleIdentifier(of object: AudioObjectID) -> String? {
        var ref: CFString = "" as CFString
        guard read(object, kAudioProcessPropertyBundleID, &ref) else { return nil }
        let value = ref as String
        return value.isEmpty ? nil : value
    }

    static func defaultOutputDeviceID() -> AudioObjectID? {
        var device = AudioObjectID(0)
        guard read(systemObject, kAudioHardwarePropertyDefaultOutputDevice, &device),
              device != 0 else { return nil }
        return device
    }

    static func deviceUID(_ device: AudioObjectID) -> String? {
        var ref: CFString = "" as CFString
        guard read(device, kAudioDevicePropertyDeviceUID, &ref) else { return nil }
        let uid = ref as String
        return uid.isEmpty ? nil : uid
    }

    static func deviceName(_ device: AudioObjectID) -> String? {
        var ref: CFString = "" as CFString
        guard read(device, kAudioObjectPropertyName, &ref) else { return nil }
        let name = ref as String
        return name.isEmpty ? nil : name
    }

    static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var qualifier = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(systemObject, &address,
                                       UInt32(MemoryLayout<CFString>.size), pointer,
                                       &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func outputStreams(_ device: AudioObjectID) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioStreamID>.size else { return [] }
        var streams = [AudioStreamID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else {
            return []
        }
        return Array(streams.prefix(Int(size) / MemoryLayout<AudioStreamID>.size))
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        var rate: Float64 = 0
        guard read(device, kAudioDevicePropertyNominalSampleRate, &rate),
              rate.isFinite, rate > 0 else { return nil }
        return rate
    }

    // MARK: 系统音量与静音

    /// 兼容旧系统的主音量属性（'vmvc' 未在 Swift SDK 中导出）
    private static let virtualMainVolumeSelector = AudioObjectPropertySelector(0x766D7663)

    private static let volumeSelectors: [AudioObjectPropertySelector] = [
        virtualMainVolumeSelector,
        kAudioDevicePropertyVolumeScalar,
    ]

    private static func hasSettableVolume(_ device: AudioObjectID) -> Bool {
        for selector in volumeSelectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
               settable.boolValue { return true }
        }
        return false
    }

    static func outputVolume(_ device: AudioObjectID) -> Double? {
        for selector in volumeSelectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var volume: Float32 = 0
            if read(device, selector, &volume, scope: kAudioObjectPropertyScopeOutput) {
                return Double(volume)
            }
        }
        return nil
    }

    static func setOutputVolume(_ volume: Double, device: AudioObjectID) -> Bool {
        let clamped = Float32(min(max(volume, 0), 1))
        for selector in volumeSelectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var next = clamped
            if AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &next) == noErr {
                return true
            }
        }
        return false
    }

    static func isOutputMuted(_ device: AudioObjectID) -> Bool? {
        for element in muteElements(device) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: UInt32 = 0
            guard read(device, kAudioDevicePropertyMute, &value,
                       scope: kAudioObjectPropertyScopeOutput, element: element) else { continue }
            return value != 0
        }
        return nil
    }

    @discardableResult
    static func setOutputMuted(_ muted: Bool, device: AudioObjectID) -> Bool {
        var changed = false
        for element in muteElements(device) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value: UInt32 = muted ? 1 : 0
            if AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
                changed = true
            }
        }
        return changed
    }

    private static func muteElements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        [kAudioObjectPropertyElementMain, 1, 2]
    }

    // MARK: 输出设备列表

    static func outputDevices() -> [AudioOutputDeviceInfo] {
        let defaultID = defaultOutputDeviceID()
        let defaultUID = defaultID.flatMap(deviceUID)
        return objectList(systemObject, kAudioHardwarePropertyDevices).compactMap { device in
            guard !outputStreams(device).isEmpty else { return nil }
            var alive: UInt32 = 1
            if read(device, kAudioDevicePropertyDeviceIsAlive, &alive), alive == 0 { return nil }
            var hidden: UInt32 = 0
            if read(device, kAudioDevicePropertyIsHidden, &hidden), hidden != 0 { return nil }
            guard let uid = deviceUID(device) else { return nil }
            let name = deviceName(device) ?? uid
            return AudioOutputDeviceInfo(id: uid, uid: uid, name: name, isDefault: uid == defaultUID)
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func systemVolume() -> Double? {
        guard let device = defaultOutputDeviceID(), hasSettableVolume(device) else { return nil }
        return outputVolume(device)
    }

    static func systemMuted() -> Bool? {
        guard let device = defaultOutputDeviceID() else { return nil }
        return isOutputMuted(device)
    }

    @discardableResult
    static func setDefaultOutputDevice(_ uid: String) -> Bool {
        guard let device = deviceID(forUID: uid) else { return false }
        var next = device
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(systemObject, &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &next) == noErr
    }

    static func setSystemVolume(_ volume: Double) -> Bool {
        guard let device = defaultOutputDeviceID() else { return false }
        let applied = setOutputVolume(volume, device: device)
        setOutputMuted(volume <= 0.001, device: device)
        return applied
    }

    static func setSystemMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDeviceID() else { return false }
        return setOutputMuted(muted, device: device)
    }
}

// MARK: - 进程归属

enum AudioProcessResolver {
    /// `responsibility_get_pid_responsible_for_pid` 是系统用于把辅助进程
    /// 归并到主应用的同款接口，缺失时直接退回原 pid。
    private static let resolve: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func owner(of pid: pid_t) -> NSRunningApplication? {
        let responsible = resolve?(pid) ?? pid
        let candidates = responsible != pid ? [responsible, pid] : [pid]
        for candidate in candidates {
            if let app = NSRunningApplication(processIdentifier: candidate),
               app.activationPolicy == .regular {
                return app
            }
            var current: pid_t = candidate
            for _ in 0..<8 {
                let parent = parentPid(of: current)
                guard parent > 1 else { break }
                if let app = NSRunningApplication(processIdentifier: parent),
                   app.activationPolicy == .regular {
                    return app
                }
                current = parent
            }
        }
        return nil
    }

    private static func parentPid(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }
}

// MARK: - 实时渲染

enum AudioMixerRender {
    static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    /// tap 在聚合设备里通常排在设备自身输入之后，从后往前找通道数匹配的 buffer。
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer,
                               tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels {
                return buffers[index].mData == nil ? nil : index
            }
            if buffers.count == 1, buffers[index].mData != nil { lone = index }
        }
        return lone
    }

    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            guard let data = buffer.mData else { continue }
            if frame == 0 {
                memset(data, 0, Int(buffer.mDataByteSize))
                continue
            }
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            let destination = data.assumingMemoryBound(to: Float.self)
            let unwritten = frames(bytes: buffer.mDataByteSize,
                                   channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    /// 把源 buffer 按增益写入输出，未覆盖的部分静音。
    @discardableResult
    static func render(source: AudioBuffer,
                       into output: UnsafeMutableAudioBufferListPointer,
                       gain: Float) -> Int {
        var written = 0
        defer { silence(output, from: written) }
        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0, let samples = source.mData?.assumingMemoryBound(to: Float.self)
        else { return 0 }

        var frames = self.frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        var hasWritable = false
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            hasWritable = true
            frames = min(frames, self.frames(bytes: buffer.mDataByteSize,
                                             channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0, hasWritable else { return 0 }
        var gain = gain

        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            vDSP_vsmul(samples, 1, &gain, destination, 1, vDSP_Length(frames * sourceChannels))
            written = frames
            return written
        }

        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            var scale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &scale,
                       destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &scale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            written = frames
            return written
        }

        var firstOutputChannel = 0
        var didWrite = false
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                let index = firstOutputChannel + channel
                let sourceChannel: Int?
                if index < sourceChannels {
                    sourceChannel = index
                } else if sourceChannels == 1, index == 1 {
                    sourceChannel = 0
                } else {
                    sourceChannel = nil
                }
                guard let sourceChannel else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                didWrite = true
                vDSP_vsmul(samples + sourceChannel, vDSP_Stride(sourceChannels), &gain,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        written = didWrite ? frames : 0
        return written
    }
}

// MARK: - 单应用 Tap 引擎

/// 一个被接管的应用音频路径：静音进程 tap + 私有聚合设备 + IOProc 实时缩放。
/// 参考 vorssaint 的 TapGainEngine，保留其关键顺序：
/// 先停止读取归还原始输出，再异步销毁聚合设备与 tap。
@available(macOS 14.4, *)
final class AudioTapEngine: @unchecked Sendable {
    let tapObjects: [AudioObjectID]
    let outputDeviceUID: String
    let gain = AtomicFloatBox(1)
    let muted = AtomicBoolBox(false)
    let objectKey: String
    /// 渲染回调次数，用于识别睡眠后聚合设备失灵的“假运行”引擎。
    var renderCycles: UInt64 { cycles.value }

    private let cycles = AtomicCycleBox()
    private let ramp = TapLevelRamp()

    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var tapChannels = 2
    private static let teardownQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.chaoeng.CalmBar.audio.teardown"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    init?(objects: [AudioObjectID], outputDeviceUID: String, gain: Float, muted: Bool) {
        guard !objects.isEmpty else { return nil }
        self.tapObjects = objects
        self.outputDeviceUID = outputDeviceUID
        self.objectKey = objects.sorted().map(String.init).joined(separator: ",")
        self.gain.value = min(max(gain, 0), 2)
        self.muted.value = muted

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            AudioDebug.log("tap create failed objects=\(objects)")
            return nil
        }

        var asbd = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd) == noErr,
              asbd.mChannelsPerFrame > 0 else {
            AudioDebug.log("tap format unavailable")
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
            return nil
        }
        tapChannels = Int(asbd.mChannelsPerFrame)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CalmBar Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else {
            AudioDebug.log("aggregate create failed uid=\(outputDeviceUID)")
            aggregateID = 0
            stop()
            return nil
        }

        let gainBox = self.gain
        let mutedBox = self.muted
        let ramp = self.ramp
        let cycles = self.cycles
        let tapChannels = tapChannels
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil,
            { now, input, _, output, _ in
                let inputBuffers = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: input))
                let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
                guard !mutedBox.value,
                      let tapIndex = AudioMixerRender.tapBufferIndex(in: inputBuffers,
                                                                     tapChannels: tapChannels) else {
                    AudioMixerRender.silence(outputBuffers)
                    return
                }
                let gain = ramp.next(toward: gainBox.value, hostTime: now.pointee.mHostTime)
                let frames = AudioMixerRender.render(source: inputBuffers[tapIndex],
                                                     into: outputBuffers,
                                                     gain: gain)
                if frames > 0 { cycles.increment() }
            }) == noErr else {
            ioProc = nil
            stop()
            return nil
        }

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            AudioDebug.log("device start failed aggregate=\(aggregateID)")
            stop()
            return nil
        }
        AudioDebug.log("engine started key=\(objectKey) gain=\(self.gain.value) channels=\(tapChannels)")
    }

    func update(gain newGain: Float, muted newMuted: Bool) {
        gain.value = min(max(newGain, 0), 2)
        muted.value = newMuted
    }

    func stop() {
        let cycles = renderCycles
        let tap = tapID
        let aggregate = aggregateID
        let proc = ioProc
        guard tap != 0 || aggregate != 0 || proc != nil else { return }
        tapID = 0
        aggregateID = 0
        ioProc = nil
        AudioDebug.log("engine stop cycles=\(cycles)")

        // 先停止读取，立刻归还应用的原始输出；销毁放到异步队列避免卡主线程。
        if let proc, aggregate != 0 {
            AudioDeviceStop(aggregate, proc)
        }
        Self.teardownQueue.addOperation {
            if let proc, aggregate != 0 {
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            if aggregate != 0 {
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            if tap != 0 {
                AudioHardwareDestroyProcessTap(tap)
            }
        }
    }

    deinit { stop() }
}

// MARK: - 原子标量

/// 仅在 CALMBAR_AUDIO_DEBUG=1 时向 stderr 输出音频路径诊断日志。
enum AudioDebug {
    static let enabled = ProcessInfo.processInfo.environment["CALMBAR_AUDIO_DEBUG"] == "1"

    static func log(_ message: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("audio: " + message + "\n").utf8))
    }
}

final class AtomicFloatBox: @unchecked Sendable {
    private var bits: Int32

    init(_ value: Float) {
        bits = Int32(bitPattern: value.bitPattern)
    }

    /// 无锁读写：该值在实时音频回调里读取，不能使用 NSLock 造成优先级反转。
    var value: Float {
        get { Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &bits))) }
        set {
            let replacement = Int32(bitPattern: newValue.bitPattern)
            while true {
                let current = OSAtomicAdd32Barrier(0, &bits)
                if OSAtomicCompareAndSwap32Barrier(current, replacement, &bits) { return }
            }
        }
    }
}

final class AtomicBoolBox: @unchecked Sendable {
    private var bits: Int32

    init(_ value: Bool) {
        bits = value ? 1 : 0
    }

    var value: Bool {
        get { OSAtomicAdd32Barrier(0, &bits) != 0 }
        set {
            let replacement = Int32(newValue ? 1 : 0)
            while true {
                let current = OSAtomicAdd32Barrier(0, &bits)
                if OSAtomicCompareAndSwap32Barrier(current, replacement, &bits) { return }
            }
        }
    }
}

final class AtomicCycleBox: @unchecked Sendable {
    private var bits: Int64 = 0

    var value: UInt64 { UInt64(bitPattern: OSAtomicAdd64Barrier(0, &bits)) }

    func increment() { _ = OSAtomicIncrement64Barrier(&bits) }
}

/// 音量按时间平滑过渡：快速回落、缓慢抬升，避免拖动滑块或换路由时爆音。
final class TapLevelRamp {
    private var applied: Float?
    private var lastHostTime: UInt64?
    private static let dropDuration: Double = 0.005
    private static let rampDuration: Double = 0.03
    private static let maximumStep: Double = 4

    func next(toward target: Float, hostTime: UInt64) -> Float {
        let elapsed = lastHostTime.map { hostTime > $0 ? hostTime - $0 : 0 } ?? 0
        lastHostTime = hostTime
        guard let applied, applied > 0 else {
            self.applied = target
            return target
        }
        let seconds = Double(AudioConvertHostTimeToNanos(elapsed)) / 1_000_000_000
        let duration = target < applied ? Self.dropDuration : Self.rampDuration
        let limit = Float(pow(Self.maximumStep, min(max(seconds, 0) / duration, 1)))
        let value = min(max(target, applied / limit), applied * limit)
        self.applied = value
        return value
    }
}
