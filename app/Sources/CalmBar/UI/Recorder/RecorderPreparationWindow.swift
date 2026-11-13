import AppKit
import ScreenCaptureKit
import SwiftUI

// MARK: - 准备面板（320×260，居中浮动，PRD §5.8）

@MainActor
public final class RecorderPreparationWindowController: NSObject, NSWindowDelegate {
    public static let shared = RecorderPreparationWindowController()

    private var panel: NSPanel?

    private override init() { super.init() }

    public func show() {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let size = NSSize(width: 320, height: 260)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "屏幕录制"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // BR-33：准备面板不进入录制画面
        panel.sharingType = .none
        panel.contentViewController = NSHostingController(
            rootView: RecorderPreparationView()
        )
        // SwiftUI 首帧未完成测量时会被压扁，强制回写固定尺寸
        panel.setContentSize(size)
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    /// 区域选择期间先收起面板但不重置状态
    func hideForSelection() {
        panel?.orderOut(nil)
    }

    public func cancelAndClose() {
        panel?.close()
        panel = nil
        ScreenRecorderService.shared.cancelPreparation()
    }

    public func windowWillClose(_ notification: Notification) {
        if let win = panel, (notification.object as? NSWindow) === win {
            panel = nil
            ScreenRecorderService.shared.cancelPreparation()
        }
    }
}

// MARK: - 可选窗口

struct RecorderWindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleIdentifier: String

    var displayName: String {
        title.isEmpty ? appName : "\(appName) · \(title)"
    }
}

// MARK: - 窗口列表加载（准备面板与计划编辑器共用）

@MainActor
enum RecorderShareableContentLoader {
    static func loadWindows() async throws -> [RecorderWindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        let ownPID = NSRunningApplication.current.processIdentifier
        let items: [RecorderWindowInfo] = content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.frame.width > 80, window.frame.height > 60,
                  window.owningApplication?.processID != ownPID else { return nil }
            let title = window.title ?? ""
            let app = window.owningApplication?.applicationName ?? "未知应用"
            let bundleIdentifier = window.owningApplication?.bundleIdentifier ?? ""
            return RecorderWindowInfo(id: window.windowID,
                                      title: title,
                                      appName: app,
                                      bundleIdentifier: bundleIdentifier)
        }
        return items.sorted { lhs, rhs in
            lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }
}

// MARK: - 准备面板内容

private enum RecorderPrepareMode: String, CaseIterable, Identifiable {
    case area
    case window
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "区域"
        case .window: "窗口"
        case .display: "全屏"
        }
    }
}

struct RecorderPreparationView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared

    @State private var mode: RecorderPrepareMode = .display
    @State private var windows: [RecorderWindowInfo] = []
    @State private var selectedWindowID: CGWindowID?
    @State private var isLoadingWindows = false
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            modePicker
            if mode == .window {
                windowPicker
            }
            audioToggles
            summary
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            startButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: 320, height: 260)
        .background(.regularMaterial)
        // 窗口列表依赖模式：切到「窗口」时再加载，之前放在 .task 里会因默认是「全屏」而永远跳过
        .task(id: mode) { await loadWindows() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PopoverPalette.accentRed)
            Text("屏幕录制")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(RecorderPrepareMode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var windowPicker: some View {
        HStack(spacing: 6) {
            if isLoadingWindows {
                ProgressView().controlSize(.small)
                Text("正在读取窗口…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if windows.isEmpty {
                Text("没有可录制的窗口")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(windows) { window in
                        Button {
                            selectedWindowID = window.id
                        } label: {
                            if selectedWindowID == window.id {
                                Label(window.displayName, systemImage: "checkmark")
                            } else {
                                Text(window.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedWindow?.displayName ?? "选择窗口")
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(PopoverPalette.surfaceWell)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 26)
    }

    private var selectedWindow: RecorderWindowInfo? {
        windows.first { $0.id == selectedWindowID }
    }

    private var audioToggles: some View {
        HStack(spacing: 14) {
            Toggle("系统声音", isOn: $settings.recorderCaptureSystemAudio)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
            Toggle("麦克风", isOn: $settings.recorderCaptureMicrophone)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
            Spacer()
        }
    }

    private var summary: some View {
        Text("\(settings.recorderQuality.title) · \(settings.recorderFPS)fps · \(settings.recorderCodec.title)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private var startButton: some View {
        HStack(spacing: 8) {
            Button {
                ScreenRecorderService.shared.openRecordingsFolder()
            } label: {
                Label("录制文件夹", systemImage: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("在访达中打开录制文件夹")

            Button(action: start) {
                HStack(spacing: 5) {
                    Image(systemName: "record.circle")
                    Text("开始录制")
                    Text("⌥⌘R")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(PopoverPalette.accentRed)
            .disabled(mode == .window && selectedWindowID == nil)
        }
    }

    // MARK: - 开始

    private func start() {
        hint = nil
        switch mode {
        case .display:
            begin(with: .display(CGMainDisplayID()))
        case .window:
            guard let selectedWindowID else {
                hint = "请先选择一个窗口"
                return
            }
            begin(with: .window(selectedWindowID))
        case .area:
            RecorderPreparationWindowController.shared.hideForSelection()
            RecorderAreaSelector.shared.show { region in
                if let region {
                    self.begin(with: region)
                } else {
                    RecorderPreparationWindowController.shared.show()
                }
            }
        }
    }

    private func begin(with region: RecorderRegion) {
        RecorderPreparationWindowController.shared.cancelAndClose()
        ScreenRecorderService.shared.start(
            region: region,
            capturesSystemAudio: settings.recorderCaptureSystemAudio,
            capturesMicrophone: settings.recorderCaptureMicrophone,
            countdown: settings.recorderCountdown
        )
    }

    // MARK: - 窗口列表

    private func loadWindows() async {
        guard mode == .window, windows.isEmpty else { return }
        isLoadingWindows = true
        hint = nil
        defer { isLoadingWindows = false }
        do {
            windows = try await RecorderShareableContentLoader.loadWindows()
            if selectedWindowID == nil {
                selectedWindowID = windows.first?.id
            }
            if windows.isEmpty {
                hint = "没有可录制的窗口，请确认目标窗口未最小化"
            }
        } catch {
            hint = "无法读取窗口列表，请在系统设置中允许 CalmBar 屏幕录制"
        }
    }
}
