import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit

// MARK: - 录制区域

enum RecorderRegion: Equatable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    case area(CGDirectDisplayID, CGRect)   // 屏幕坐标（左上原点，单位 pt）

    var isWindow: Bool {
        if case .window = self { return true }
        return false
    }
}

enum RecorderCaptureFailure: Error, Equatable {
    case permissionDenied
    case noContent
    case streamFailed
    case writerFailed
    case diskFull

    var message: String {
        switch self {
        case .permissionDenied: return "未获得屏幕录制权限，请前往系统设置授权"
        case .noContent: return "找不到可录制的屏幕或窗口"
        case .streamFailed: return "屏幕采集启动失败，请稍后重试"
        case .writerFailed: return "录制文件写入失败"
        case .diskFull: return "磁盘可用空间不足 500MB，无法开始录制"
        }
    }
}

// MARK: - 时间对齐

enum RecorderSampleTiming {
    static func converted(_ sample: CMSampleBuffer, from source: CMClock, to target: CMClock)
        -> CMSampleBuffer? {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard pts.isNumeric else { return nil }
        let mapped = CMSyncConvertTime(pts, from: source, to: target)
        guard mapped.isNumeric else { return nil }
        return retimed(sample, to: mapped)
    }

    /// 改写时间轴。音频 buffer 含多个采样点时 `CMSampleBufferGetDuration` 返回的是总时长，
    /// 而单条 timing 记录表示的是「每个采样点」的时长，必须先换算再写回。
    static func retimed(_ sample: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        let sampleCount = CMSampleBufferGetNumSamples(sample)
        var duration = CMSampleBufferGetDuration(sample)
        if sampleCount > 1, duration.isNumeric, duration.value > 0 {
            duration = CMTime(value: duration.value / Int64(sampleCount),
                              timescale: duration.timescale)
        }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                    sampleBuffer: sample,
                                                    sampleTimingEntryCount: 1,
                                                    sampleTimingArray: &timing,
                                                    sampleBufferOut: &result) == noErr else {
            return nil
        }
        return result
    }
}

// MARK: - 写入器

/// 单文件多轨写入：视频 + 可选系统声音 + 可选麦克风。
/// 所有方法都在采集串行队列上调用，因此内部无需额外加锁。
final class RecorderSessionWriter: @unchecked Sendable {
    enum Kind { case video, systemAudio, microphone }

    let partialURL: URL
    let finalURL: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?

    private var origin: CMTime?
    private var pausedTotal: CMTime = .zero
    private var pauseStart: CMTime?
    private var started = false
    private var failed = false
    private var frameCount = 0
    private var lastVideoSample: CMSampleBuffer?
    private var lastVideoTime: CMTime = .zero

    init?(partialURL: URL, finalURL: URL, pixelSize: CGSize, frameRate: Int, codec: RecorderCodec,
          capturesSystemAudio: Bool, capturesMicrophone: Bool) {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        guard let writer = try? AVAssetWriter(outputURL: partialURL, fileType: .mp4) else {
            return nil
        }
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(6_000_000, width * height * frameRate / 10),
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            return nil
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]

        var systemAudioInput: AVAssetWriterInput?
        if capturesSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }

        var microphoneInput: AVAssetWriterInput?
        if capturesMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                microphoneInput = input
            }
        }

        guard writer.startWriting() else { return nil }

        self.writer = writer
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.microphoneInput = microphoneInput
        self.partialURL = partialURL
        self.finalURL = finalURL
    }

    var videoFrameCount: Int { frameCount }

    func beginSession(at hostTime: CMTime) {
        guard !started, hostTime.isNumeric else { return }
        origin = hostTime
        writer.startSession(atSourceTime: .zero)
        started = true
    }

    func pause(at hostTime: CMTime) {
        guard pauseStart == nil else { return }
        pauseStart = hostTime
    }

    func resume(at hostTime: CMTime) {
        guard let start = pauseStart else { return }
        pausedTotal = pausedTotal + (hostTime - start)
        pauseStart = nil
    }

    private func mappedTime(_ hostTime: CMTime) -> CMTime? {
        guard let origin, pauseStart == nil else { return nil }
        let mapped = hostTime - origin - pausedTotal
        guard mapped.isNumeric, mapped >= .zero else { return nil }
        return mapped
    }

    func append(_ sample: CMSampleBuffer, kind: Kind) {
        guard started, !failed else { return }
        let hostPTS = CMSampleBufferGetPresentationTimeStamp(sample)
        guard let mapped = mappedTime(hostPTS) else { return }
        let mappedTime = CMTime(seconds: mapped.seconds, preferredTimescale: 600_000_000)

        switch kind {
        case .video:
            guard CMSampleBufferGetImageBuffer(sample) != nil else { return }
            guard videoInput.isReadyForMoreMediaData else { return }
            let time: CMTime = frameCount == 0 ? .zero : mappedTime
            guard let retimed = RecorderSampleTiming.retimed(sample, to: time),
                  videoInput.append(retimed) else {
                failed = true
                return
            }
            frameCount += 1
            lastVideoSample = sample
            lastVideoTime = time

        case .systemAudio:
            guard let systemAudioInput, systemAudioInput.isReadyForMoreMediaData,
                  let retimed = RecorderSampleTiming.retimed(sample, to: mappedTime) else { return }
            if !systemAudioInput.append(retimed) { failed = true }

        case .microphone:
            guard let microphoneInput, microphoneInput.isReadyForMoreMediaData,
                  let retimed = RecorderSampleTiming.retimed(sample, to: mappedTime) else { return }
            if !microphoneInput.append(retimed) { failed = true }
        }
    }

    /// 停止后在采集队列上调用：收尾文件并原子改名为正式文件名。
    func finish(hostEnd: CMTime) async -> Bool {
        guard started else {
            cancel()
            return false
        }
        // 写入过程中已失败时不再追加数据，但保留已周期性落盘的 .partial 供恢复流程使用
        guard !failed, frameCount > 0 else {
            abandonWriting()
            return false
        }
        let end = mappedTime(hostEnd) ?? lastVideoTime
        if let lastVideoSample, end > lastVideoTime, videoInput.isReadyForMoreMediaData,
           let tail = RecorderSampleTiming.retimed(lastVideoSample, to: end) {
            videoInput.append(tail)
        }
        writer.endSession(atSourceTime: max(end, lastVideoTime))
        lastVideoSample = nil
        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()

        let activeWriter = writer
        let completed: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            activeWriter.finishWriting {
                continuation.resume(returning: activeWriter.status == .completed)
            }
        }
        guard completed else {
            // 收尾失败同样保留 partialURL，避免把用户已录内容直接删掉
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
            return true
        } catch {
            return false
        }
    }

    /// 放弃收尾但保留已落盘的临时文件。
    private func abandonWriting() {
        lastVideoSample = nil
        if writer.status == .writing {
            writer.cancelWriting()
        }
    }

    func cancel() {
        lastVideoSample = nil
        if writer.status == .writing {
            writer.cancelWriting()
        }
        try? FileManager.default.removeItem(at: partialURL)
    }
}

// MARK: - 采集引擎

/// 持有 SCStream、麦克风会话与写入器。回调统一落到同一个串行队列，
/// 保证写入顺序与暂停时间轴一致。
final class RecorderCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate,
                                   AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.chaoeng.CalmBar.recorder.capture", qos: .userInitiated)
    private var stream: SCStream?
    /// 写入器在解析出实际像素尺寸后才创建，因此这里先保存文件与编码参数。
    private let partialURL: URL
    private let finalURL: URL
    private let codec: RecorderCodec
    private var writer: RecorderSessionWriter?
    private var microphoneSession: AVCaptureSession?
    private var targetClock: CMClock?
    private let hostClock = CMClockGetHostTimeClock()
    private var started = false

    var onFailure: (@Sendable (RecorderCaptureFailure) -> Void)?

    init(partialURL: URL, finalURL: URL, codec: RecorderCodec) {
        self.partialURL = partialURL
        self.finalURL = finalURL
        self.codec = codec
        super.init()
    }

    var isRunning: Bool { stream != nil }

    func start(region: RecorderRegion, frameRate: Int, includeCursor: Bool,
               capturesSystemAudio: Bool, capturesMicrophone: Bool) async -> RecorderCaptureFailure? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        } catch {
            return Self.failure(error)
        }

        let filter: SCContentFilter
        let pixelSize: CGSize
        let areaRect: CGRect?

        switch region {
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return .noContent
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            // 按窗口所在屏幕的真实像素倍率取值，避免非 Retina 外接屏被硬编码 2x 放大
            let scale = CGFloat(filter.pointPixelScale)
            pixelSize = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
            areaRect = nil
        case .display(let displayID), .area(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return .noContent
            }
            let ownPID = NSRunningApplication.current.processIdentifier
            let ownApp = content.applications.first(where: { $0.processID == ownPID })
            filter = SCContentFilter(display: display,
                                     excludingApplications: ownApp.map { [$0] } ?? [],
                                     exceptingWindows: [])
            if case .area(_, let rect) = region {
                let bounds = CGDisplayBounds(displayID)
                let displayScale = bounds.width > 0 ? CGFloat(display.width) / bounds.width : 2
                pixelSize = CGSize(width: rect.width * displayScale, height: rect.height * displayScale)
                areaRect = rect
            } else {
                pixelSize = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
                areaRect = nil
            }
        }

        let configuration = SCStreamConfiguration()
        let shortEdge = min(pixelSize.width, pixelSize.height)
        let quality = await AppSettings.shared.recorderQuality
        let scale = shortEdge > 0 ? min(1, quality.shortEdge / shortEdge) : 1
        let width = Self.even(max(2, Int((pixelSize.width * scale).rounded())))
        let height = Self.even(max(2, Int((pixelSize.height * scale).rounded())))
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = includeCursor
        configuration.scalesToFit = region.isWindow
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true
        if let areaRect {
            configuration.sourceRect = areaRect
        }
        if capturesSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        guard let newWriter = RecorderSessionWriter(
            partialURL: partialURL,
            finalURL: finalURL,
            pixelSize: CGSize(width: width, height: height),
            frameRate: frameRate,
            codec: codec,
            capturesSystemAudio: capturesSystemAudio,
            capturesMicrophone: capturesMicrophone
        ) else {
            return .writerFailed
        }

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if capturesSystemAudio {
                try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            }
            try await newStream.startCapture()
        } catch {
            newWriter.cancel()
            await stopAndDrain(newStream)
            return Self.failure(error)
        }

        queue.sync {
            guard !started else { return }
            stream = newStream
            writer = newWriter
            started = true
            targetClock = newStream.synchronizationClock ?? hostClock
            newWriter.beginSession(at: CMClockGetTime(hostClock))
        }

        if capturesMicrophone {
            _ = await startMicrophone()
        }
        return nil
    }

    func pause() {
        queue.async { [weak self] in
            self?.writer?.pause(at: CMClockGetTime(CMClockGetHostTimeClock()))
        }
    }

    func resume() {
        queue.async { [weak self] in
            self?.writer?.resume(at: CMClockGetTime(CMClockGetHostTimeClock()))
        }
    }

    /// 停止采集、排空队列并收尾文件。
    func finish() async -> URL? {
        let current = queue.sync { () -> SCStream? in
            let value = stream
            stream = nil
            started = false
            return value
        }
        if let current { try? await current.stopCapture() }
        await stopMicrophone()
        queue.sync {}
        let hostEnd = CMClockGetTime(CMClockGetHostTimeClock())
        let activeWriter = queue.sync { writer }
        guard let activeWriter, await activeWriter.finish(hostEnd: hostEnd) else { return nil }
        return activeWriter.finalURL
    }

    func cancel() {
        let current = queue.sync { () -> SCStream? in
            let value = stream
            stream = nil
            started = false
            writer?.cancel()
            writer = nil
            return value
        }
        if let current { Task { try? await current.stopCapture() } }
        Task { await stopMicrophone() }
    }

    private func stopAndDrain(_ value: SCStream) async {
        try? await value.stopCapture()
        queue.sync {}
    }

    // MARK: 麦克风

    private func startMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.resume(returning: false); return }
                if self.microphoneSession != nil {
                    self.microphoneSession?.startRunning()
                    continuation.resume(returning: self.microphoneSession?.isRunning ?? false)
                    return
                }
                let session = AVCaptureSession()
                guard let device = AVCaptureDevice.default(for: .audio),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }
                let output = AVCaptureAudioDataOutput()
                output.audioSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                    AVSampleRateKey: 48_000,
                ]
                session.beginConfiguration()
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.queue)
                session.commitConfiguration()
                self.microphoneSession = session
                session.startRunning()
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    private func stopMicrophone() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                if self.microphoneSession?.isRunning == true {
                    self.microphoneSession?.stopRunning()
                }
                self.microphoneSession = nil
                continuation.resume()
            }
        }
    }

    // MARK: 回调

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard started, let writer, CMSampleBufferIsValid(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard Self.carriesPixels(sampleBuffer) else { return }
            guard let sourceClock = stream.synchronizationClock ?? targetClock else { return }
            guard let synchronized = RecorderSampleTiming.converted(sampleBuffer, from: sourceClock,
                                                                     to: hostClock) else { return }
            writer.append(synchronized, kind: .video)
        case .audio:
            guard let sourceClock = stream.synchronizationClock ?? targetClock else { return }
            guard let synchronized = RecorderSampleTiming.converted(sampleBuffer, from: sourceClock,
                                                                     to: hostClock) else { return }
            writer.append(synchronized, kind: .systemAudio)
        default:
            break
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard started, let writer,
              let sourceClock = microphoneSession?.synchronizationClock,
              let synchronized = RecorderSampleTiming.converted(sampleBuffer, from: sourceClock,
                                                                 to: hostClock) else { return }
        writer.append(synchronized, kind: .microphone)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in
            guard let self, self.started else { return }
            self.stream = nil
            self.started = false
            let failure = Self.failure(error)
            self.onFailure?(failure)
        }
    }

    private static func carriesPixels(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                    createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete || status == .started
    }

    private static func failure(_ error: Error) -> RecorderCaptureFailure {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain,
              let code = SCStreamError.Code(rawValue: nsError.code) else { return .streamFailed }
        switch code {
        case .userDeclined: return .permissionDenied
        case .noWindowList, .noDisplayList, .noCaptureSource: return .noContent
        default: return .streamFailed
        }
    }

    private static func even(_ value: Int) -> Int {
        value % 2 == 0 ? value : value + 1
    }
}
