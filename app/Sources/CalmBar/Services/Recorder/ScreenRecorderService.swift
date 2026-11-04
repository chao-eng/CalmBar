import AVFoundation
import AppKit
import Combine
import CoreGraphics
import Foundation

// MARK: - 录制状态（PRD §4.3）

public enum RecorderState: String, CaseIterable, Sendable {
    case idle
    case preparing
    case countdown
    case recording
    case paused
    case finalizing
    case done
    case failed

    public var isActive: Bool {
        self == .countdown || self == .recording || self == .paused || self == .finalizing
    }
}

// MARK: - 录制历史

public struct RecorderRecording: Identifiable, Codable, Sendable {
    public let id: UUID
    public let fileName: String
    public let filePath: String
    public let duration: TimeInterval
    public let fileSize: Int64
    public let createdAt: Date

    public init(id: UUID = UUID(), fileName: String, filePath: String,
                duration: TimeInterval, fileSize: Int64, createdAt: Date) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.duration = duration
        self.fileSize = fileSize
        self.createdAt = createdAt
    }

    public var url: URL { URL(fileURLWithPath: filePath) }

    public var formattedDuration: String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - 录制服务

/// 屏幕录制状态机：准备 → 倒计时 → 录制/暂停 → 收尾 → 完成。
/// 采集与写入细节由 `RecorderCaptureEngine` 负责，这里只管磁盘、权限、历史与 UI 状态。
@MainActor
public final class ScreenRecorderService: ObservableObject {
    public static let shared = ScreenRecorderService()

    @Published public private(set) var state: RecorderState = .idle
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var countdownRemaining: Int = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var microphoneEnabled: Bool = false
    @Published public private(set) var recentRecordings: [RecorderRecording] = []
    @Published public private(set) var pendingPartials: [URL] = []
    @Published public private(set) var lastFinishedRecording: RecorderRecording?

    private let settings = AppSettings.shared
    private let defaults = UserDefaults.standard

    private var engine: RecorderCaptureEngine?
    private var countdownTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var accumulatedElapsed: TimeInterval = 0
    private var elapsedStart: Date?
    private var activeFinalURL: URL?
    private var activePartialURL: URL?
    private var sessionCreatedAt: Date?
    private var isStopping = false

    private static let historyKey = "recorder.recentRecordings"
    private static let ignoredPartialsKey = "recorder.ignoredPartials"

    public var isRecording: Bool {
        state == .recording || state == .paused
    }

    public var formattedElapsed: String {
        let total = max(0, Int(elapsed.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private init() {
        loadHistory()
        refreshPendingPartials()
    }

    // MARK: - 目录

    public var saveDirectory: URL {
        let custom = settings.recorderSaveDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CalmBar Recordings", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies/CalmBar Recordings")
    }

    @discardableResult
    private func ensureSaveDirectory() -> Bool {
        let directory = saveDirectory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            lastError = "无法创建录制目录：\(error.localizedDescription)"
            return false
        }
    }

    private func hasEnoughDiskSpace() -> Bool {
        let directory = saveDirectory
        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true
        }
        return available >= 500 * 1024 * 1024
    }

    // MARK: - 准备阶段

    public func prepare() {
        guard state == .idle || state == .done || state == .failed else { return }
        state = .preparing
        lastError = nil
        RecorderPreparationWindowController.shared.show()
    }

    public func cancelPreparation() {
        guard state == .preparing else { return }
        state = .idle
    }

    // MARK: - 开始录制

    func start(region: RecorderRegion,
               capturesSystemAudio: Bool,
               capturesMicrophone: Bool,
               countdown: Int) {
        guard state == .idle || state == .preparing || state == .done || state == .failed else { return }
        lastError = nil
        lastFinishedRecording = nil

        guard ensureScreenPermission() else {
            fail("未获得屏幕录制权限，请前往系统设置授权后重试", state: .failed)
            return
        }
        guard ensureSaveDirectory() else {
            fail(lastError ?? "录制目录不可写", state: .failed)
            return
        }
        guard hasEnoughDiskSpace() else {
            fail(RecorderCaptureFailure.diskFull.message, state: .failed)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var microphone = capturesMicrophone
            if microphone {
                let granted = await self.requestMicrophonePermission()
                if !granted {
                    microphone = false
                    self.lastError = "麦克风未授权，本次仅录制系统声音"
                }
            }
            self.microphoneEnabled = microphone

            if countdown > 0 {
                self.runCountdown(seconds: countdown,
                                  region: region,
                                  capturesSystemAudio: capturesSystemAudio,
                                  capturesMicrophone: microphone)
            } else {
                self.beginRecording(region: region,
                                    capturesSystemAudio: capturesSystemAudio,
                                    capturesMicrophone: microphone)
            }
        }
    }

    private func runCountdown(seconds: Int, region: RecorderRegion,
                              capturesSystemAudio: Bool, capturesMicrophone: Bool) {
        countdownRemaining = seconds
        state = .countdown
        RecorderControlBarController.shared.show()
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.countdownRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { return }
            self.countdownRemaining = 0
            self.countdownTask = nil
            self.beginRecording(region: region,
                                capturesSystemAudio: capturesSystemAudio,
                                capturesMicrophone: capturesMicrophone)
        }
    }

    public func cancelCountdown() {
        guard state == .countdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = 0
        state = .idle
        RecorderControlBarController.shared.hide()
    }

    private func beginRecording(region: RecorderRegion,
                                capturesSystemAudio: Bool,
                                capturesMicrophone: Bool) {
        let stamp = Self.fileStamp.string(from: Date())
        let directory = saveDirectory
        let partialURL = directory.appendingPathComponent("录制 \(stamp).partial.mp4")
        let finalURL = directory.appendingPathComponent("录制 \(stamp).mp4")

        let engine = RecorderCaptureEngine(partialURL: partialURL,
                                           finalURL: finalURL,
                                           codec: settings.recorderCodec)
        engine.onFailure = { [weak self] failure in
            Task { @MainActor in
                self?.handleRuntimeFailure(failure)
            }
        }

        self.engine = engine
        activePartialURL = partialURL
        activeFinalURL = finalURL
        sessionCreatedAt = Date()
        accumulatedElapsed = 0
        elapsed = 0
        elapsedStart = Date()
        isStopping = false
        state = .recording
        startElapsedTimer()
        RecorderControlBarController.shared.show()

        let frameRate = max(1, settings.recorderFPS)
        let includeCursor = settings.recorderIncludeCursor
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 启动期间用户已停止：此时服务已放弃该引擎，必须取消，否则采集会继续写盘且无法再被停止
            guard self.engine === engine else {
                engine.cancel()
                return
            }
            let failure = await engine.start(region: region,
                                             frameRate: frameRate,
                                             includeCursor: includeCursor,
                                             capturesSystemAudio: capturesSystemAudio,
                                             capturesMicrophone: capturesMicrophone)
            guard self.engine === engine else {
                engine.cancel()
                return
            }
            if let failure {
                engine.cancel()
                self.engine = nil
                self.stopElapsedTimer()
                self.activePartialURL = nil
                self.activeFinalURL = nil
                self.state = .failed
                self.lastError = failure.message
                RecorderControlBarController.shared.hide()
            }
        }
    }

    // MARK: - 暂停 / 继续 / 停止

    public func pause() {
        guard state == .recording else { return }
        engine?.pause()
        if let start = elapsedStart {
            accumulatedElapsed += Date().timeIntervalSince(start)
            elapsedStart = nil
        }
        elapsed = accumulatedElapsed
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        engine?.resume()
        elapsedStart = Date()
        state = .recording
    }

    public func togglePause() {
        if state == .recording {
            pause()
        } else if state == .paused {
            resume()
        }
    }

    public func stop() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        state = .finalizing
        if let start = elapsedStart {
            accumulatedElapsed += Date().timeIntervalSince(start)
            elapsedStart = nil
        }
        elapsed = accumulatedElapsed
        stopElapsedTimer()

        guard let engine else {
            isStopping = false
            state = .idle
            RecorderControlBarController.shared.hide()
            return
        }
        self.engine = nil
        let duration = elapsed
        let createdAt = sessionCreatedAt ?? Date()
        let finalURL = activeFinalURL

        Task { @MainActor [weak self] in
            guard let self else { return }
            let finishedURL = await engine.finish()
            if let finishedURL, let finalURL, FileManager.default.fileExists(atPath: finalURL.path) {
                self.registerRecording(at: finishedURL, duration: duration, createdAt: createdAt)
                self.state = .done
                self.lastError = nil
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // 只在仍停留在「完成」态时收尾，避免把 1 秒内新开录制的控制条一起隐藏
                if self.state == .done {
                    RecorderControlBarController.shared.hide()
                    self.state = .idle
                }
            } else {
                self.state = .failed
                self.lastError = "录制未能正常收尾，临时文件已保留，可在录制设置中尝试恢复"
                // 立刻把残留临时文件暴露给恢复入口，无需等到下次启动
                self.refreshPendingPartials()
                RecorderControlBarController.shared.hide()
            }
            self.isStopping = false
            self.activePartialURL = nil
            self.activeFinalURL = nil
        }
    }

    private func handleRuntimeFailure(_ failure: RecorderCaptureFailure) {
        guard isRecording else { return }
        lastError = failure.message
        stop()
    }

    // MARK: - 失败处理

    private func fail(_ message: String, state: RecorderState) {
        lastError = message
        self.state = state
    }

    // MARK: - 计时

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.elapsedStart else { return }
                self.elapsed = self.accumulatedElapsed + Date().timeIntervalSince(start)
            }
        }
        if let timer = elapsedTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - 权限

    private func ensureScreenPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        return CGPreflightScreenCaptureAccess()
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - 历史

    private func registerRecording(at url: URL, duration: TimeInterval, createdAt: Date) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        let recording = RecorderRecording(
            fileName: url.lastPathComponent,
            filePath: url.path,
            duration: duration,
            fileSize: size,
            createdAt: createdAt
        )
        recentRecordings.removeAll { $0.filePath == recording.filePath }
        recentRecordings.insert(recording, at: 0)
        if recentRecordings.count > 20 {
            recentRecordings.removeLast(recentRecordings.count - 20)
        }
        lastFinishedRecording = recording
        persistHistory()
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([RecorderRecording].self, from: data) else {
            return
        }
        recentRecordings = decoded
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(recentRecordings) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }

    public func openRecordingsFolder() {
        ensureSaveDirectory()
        NSWorkspace.shared.open(saveDirectory)
    }

    public func reveal(_ recording: RecorderRecording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    public func delete(_ recording: RecorderRecording) {
        do {
            try FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
        } catch {
            lastError = "删除失败：\(error.localizedDescription)"
        }
        recentRecordings.removeAll { $0.id == recording.id }
        persistHistory()
    }

    // MARK: - 残留 .partial 恢复

    public func refreshPendingPartials() {
        let directory = saveDirectory
        let ignored = Set(defaults.stringArray(forKey: Self.ignoredPartialsKey) ?? [])
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        pendingPartials = contents
            .filter { $0.lastPathComponent.contains(".partial.mp4") }
            .filter { !ignored.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func repairPartial(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            guard playable, duration > 0 else {
                self.lastError = "该临时文件不可恢复，可移入废纸篓"
                return
            }
            let finalURL = URL(fileURLWithPath: url.path.replacingOccurrences(of: ".partial.mp4",
                                                                             with: ".mp4"))
            do {
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: url, to: finalURL)
                self.registerRecording(at: finalURL, duration: duration,
                                       createdAt: (try? FileManager.default.attributesOfItem(
                                        atPath: finalURL.path)[.creationDate] as? Date) ?? Date())
                self.pendingPartials.removeAll { $0 == url }
            } catch {
                self.lastError = "恢复失败：\(error.localizedDescription)"
            }
        }
    }

    public func discardPartial(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        pendingPartials.removeAll { $0 == url }
    }

    public func ignorePartial(_ url: URL) {
        var ignored = defaults.stringArray(forKey: Self.ignoredPartialsKey) ?? []
        ignored.append(url.lastPathComponent)
        defaults.set(ignored, forKey: Self.ignoredPartialsKey)
        pendingPartials.removeAll { $0 == url }
    }

    // MARK: - 工具

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()
}
