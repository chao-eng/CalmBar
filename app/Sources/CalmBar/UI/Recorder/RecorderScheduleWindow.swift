import AppKit
import CoreGraphics
import SwiftUI

// MARK: - 录制计划独立窗口（760×540）

@MainActor
public final class RecorderScheduleWindowController: NSObject, NSWindowDelegate {
    public static let shared = RecorderScheduleWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let size = NSSize(width: 760, height: 540)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "录制计划"
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        // 计划窗口不进入录制画面
        window.sharingType = .none
        window.contentViewController = NSHostingController(rootView: RecorderScheduleWindowView())
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func hideForSelection() {
        window?.orderOut(nil)
    }

    func restoreAfterSelection() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if let win = window, (notification.object as? NSWindow) === win {
            window = nil
        }
    }
}

// MARK: - 编辑器草稿

private enum RecorderScheduleSourceMode: String, CaseIterable, Identifiable {
    case display
    case window
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "全屏"
        case .window: return "窗口"
        case .area: return "区域"
        }
    }
}

private struct RecorderScheduleDraft {
    var id: UUID
    var name: String
    var isOnce: Bool
    var onceStart: Date
    var onceEnd: Date
    var dailyStartTime: Date
    var dailyEndTime: Date
    var sourceMode: RecorderScheduleSourceMode
    var displayID: CGDirectDisplayID
    var windowID: CGWindowID?
    var windowBundleIdentifier: String
    var windowTitle: String
    var areaDisplayID: CGDirectDisplayID
    var areaRect: CGRect
    var profile: RecorderCaptureProfile
    var isEnabled: Bool
    var createdAt: Date
    var lastOutcome: RecorderScheduleOutcome?

    @MainActor
    init(schedule: RecorderSchedule? = nil) {
        let calendar = Calendar.current
        let now = Date()
        let defaultStart = calendar.date(byAdding: .minute, value: 10, to: now) ?? now
        let defaultEnd = calendar.date(byAdding: .hour, value: 2, to: defaultStart) ?? defaultStart

        id = schedule?.id ?? UUID()
        name = schedule?.name ?? "计划录制"
        createdAt = schedule?.createdAt ?? now
        lastOutcome = schedule?.lastOutcome
        isEnabled = schedule?.isEnabled ?? true
        profile = schedule?.profile ?? RecorderCaptureProfile.fromSettings()

        switch schedule?.repeatRule {
        case .once(let start, let end):
            isOnce = true
            onceStart = start
            onceEnd = end
            dailyStartTime = Self.timeDate(minutes: 9 * 60)
            dailyEndTime = Self.timeDate(minutes: 11 * 60)
        case .daily(let startMinutes, let endMinutes):
            isOnce = false
            onceStart = defaultStart
            onceEnd = defaultEnd
            dailyStartTime = Self.timeDate(minutes: startMinutes)
            dailyEndTime = Self.timeDate(minutes: endMinutes)
        case nil:
            isOnce = true
            onceStart = defaultStart
            onceEnd = defaultEnd
            dailyStartTime = Self.timeDate(minutes: 9 * 60)
            dailyEndTime = Self.timeDate(minutes: 11 * 60)
        }

        switch schedule?.source {
        case .display(let displayID):
            sourceMode = .display
            self.displayID = displayID
            windowID = nil
            windowBundleIdentifier = ""
            windowTitle = ""
            areaDisplayID = CGMainDisplayID()
            areaRect = .zero
        case .window(let windowID, let bundleIdentifier, let title):
            sourceMode = .window
            displayID = CGMainDisplayID()
            self.windowID = windowID
            windowBundleIdentifier = bundleIdentifier
            windowTitle = title
            areaDisplayID = CGMainDisplayID()
            areaRect = .zero
        case .area(let displayID, let rect):
            sourceMode = .area
            self.displayID = displayID
            windowID = nil
            windowBundleIdentifier = ""
            windowTitle = ""
            areaDisplayID = displayID
            areaRect = rect
        case nil:
            sourceMode = .display
            displayID = CGMainDisplayID()
            windowID = nil
            windowBundleIdentifier = ""
            windowTitle = ""
            areaDisplayID = CGMainDisplayID()
            areaRect = .zero
        }
    }

    var repeatRule: RecorderScheduleRepeat {
        if isOnce {
            return .once(start: onceStart, end: onceEnd)
        }
        return .daily(startMinutes: Self.minutes(from: dailyStartTime),
                      endMinutes: Self.minutes(from: dailyEndTime))
    }

    var source: RecorderScheduleSource {
        switch sourceMode {
        case .display:
            return .display(displayID: displayID)
        case .window:
            return .window(windowID: windowID ?? 0,
                           bundleIdentifier: windowBundleIdentifier,
                           title: windowTitle)
        case .area:
            return .area(displayID: areaDisplayID, rect: areaRect)
        }
    }

    func buildSchedule() -> RecorderSchedule {
        RecorderSchedule(id: id,
                         name: name,
                         repeatRule: repeatRule,
                         source: source,
                         profile: profile,
                         isEnabled: isEnabled,
                         createdAt: createdAt,
                         lastOutcome: lastOutcome)
    }

    var areaDescription: String {
        guard areaRect.width >= 1, areaRect.height >= 1 else { return "尚未选择区域" }
        return "\(Int(areaRect.width.rounded())) × \(Int(areaRect.height.rounded()))"
    }

    private static func timeDate(minutes: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: minutes / 60,
                             minute: minutes % 60,
                             second: 0,
                             of: day) ?? day
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

// MARK: - 窗口内容

struct RecorderScheduleWindowView: View {
    @ObservedObject private var coordinator = RecorderScheduleCoordinator.shared
    @ObservedObject private var notifier = RecorderScheduleNotifier.shared

    @State private var selection: UUID?
    @State private var draft: RecorderScheduleDraft?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var windows: [RecorderWindowInfo] = []
    @State private var isLoadingWindows = false
    @State private var windowLoadFailed = false
    @State private var isSaving = false

    private let engine = RecorderScheduleEngine()

    var body: some View {
        VStack(spacing: 0) {
            banner
            HStack(spacing: 0) {
                listPane
                    .frame(width: 280)
                Divider()
                editorPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selection == nil, let first = coordinator.schedules.first {
                selection = first.id
                draft = RecorderScheduleDraft(schedule: first)
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let schedule = newValue.flatMap({ coordinator.schedule(id: $0) }) else { return }
            draft = RecorderScheduleDraft(schedule: schedule)
            errorMessage = nil
            statusMessage = nil
        }
        .task(id: draft?.sourceMode) {
            guard draft?.sourceMode == .window else { return }
            await loadWindowsIfNeeded()
        }
    }

    // MARK: 顶部提示

    @ViewBuilder
    private var banner: some View {
        if notifier.isDegraded || !coordinator.hasScreenPermission {
            VStack(alignment: .leading, spacing: 4) {
                if notifier.isDegraded {
                    bannerRow(icon: "bell.slash",
                              text: "通知权限未开启，计划仍会执行，但不会提醒。",
                              actionTitle: "打开系统设置") {
                        openNotificationSettings()
                    }
                }
                if !coordinator.hasScreenPermission {
                    bannerRow(icon: "rectangle.dashed.badge.record",
                              text: "屏幕录制权限未开启，计划到点会被跳过。",
                              actionTitle: "打开系统设置") {
                        openScreenRecordingSettings()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
        }
    }

    private func bannerRow(icon: String,
                           text: String,
                           actionTitle: String,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11.5))
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    // MARK: 左侧列表

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("录制计划")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    createNew()
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(isSaving)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if coordinator.schedules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("还没有录制计划")
                        .font(.system(size: 12, weight: .medium))
                    Text("到点自动开始与结束，创建时固定录制源与参数。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(coordinator.schedules) { schedule in
                        scheduleRow(schedule)
                            .tag(schedule.id)
                    }
                }
                .listStyle(.sidebar)
                .disabled(isSaving)
            }

            Divider()
            HStack(spacing: 6) {
                Image(systemName: notifier.isDegraded ? "bell.slash" : "bell")
                    .font(.system(size: 10))
                    .foregroundStyle(notifier.isDegraded ? .orange : .secondary)
                Text(notifier.isDegraded
                     ? "通知权限未开启，仅窗口内提示"
                     : "通知提醒已就绪")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    ScreenRecorderService.shared.openRecordingsFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("打开录制文件夹")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func scheduleRow(_ schedule: RecorderSchedule) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.trimmedName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(schedule.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(nextText(for: schedule))
                    .font(.system(size: 10))
                    .foregroundStyle(nextColor(for: schedule))
                    .lineLimit(1)
                if let outcome = schedule.lastOutcome {
                    Text("\(outcome.statusText)：\(outcome.message)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if notifier.isDegraded {
                Image(systemName: "bell.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("通知权限未开启")
            }
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { enabled in
                    if let error = coordinator.setEnabled(enabled, for: schedule.id) {
                        errorMessage = error
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(isRunning(schedule.id))
        }
        .padding(.vertical, 3)
    }

    // MARK: 右侧编辑器

    @ViewBuilder
    private var editorPane: some View {
        if draft != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editorHeader
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        nameSection
                        repeatSection
                        sourceSection
                        audioSection
                        qualitySection
                    }
                    .disabled(isCurrentScheduleRunning || isSaving)
                    Text("单个计划最长 12 小时。计划执行期间系统保持唤醒，锁屏或会话非活跃时暂停，解锁后继续。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                    footerActions
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("选择左侧计划，或新建一个计划")
                    .font(.system(size: 12.5, weight: .medium))
                Text("录制源与画质参数会随计划保存，到点后不再读取设置页。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorHeader: some View {
        HStack {
            Text(isCurrentScheduleRunning ? "执行中的计划" : "编辑计划")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if isCurrentScheduleRunning {
                Button("停止本次") {
                    coordinator.stopCurrentRun()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
    }

    private var nameSection: some View {
        GroupBox(label: Label("名称", systemImage: "textformat")) {
            TextField("例如：周会录制", text: bind(\.name))
                .textFieldStyle(.roundedBorder)
                .padding(6)
        }
    }

    private var repeatSection: some View {
        GroupBox(label: Label("重复与时间", systemImage: "calendar")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("重复方式", selection: bind(\.isOnce)) {
                    Text("一次性").tag(true)
                    Text("每天").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                if draft?.isOnce == true {
                    DatePicker("开始", selection: bind(\.onceStart),
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: bind(\.onceEnd),
                               displayedComponents: [.date, .hourAndMinute])
                } else {
                    HStack(spacing: 16) {
                        DatePicker("开始", selection: bind(\.dailyStartTime),
                                   displayedComponents: [.hourAndMinute])
                        DatePicker("结束", selection: bind(\.dailyEndTime),
                                   displayedComponents: [.hourAndMinute])
                    }
                    Text("结束时间不晚于开始时间表示跨天，例如 23:00–01:00。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var sourceSection: some View {
        GroupBox(label: Label("录制源", systemImage: "rectangle.on.rectangle")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("录制源", selection: bind(\.sourceMode)) {
                    ForEach(RecorderScheduleSourceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                switch draft?.sourceMode {
                case .display:
                    Picker("显示器", selection: bind(\.displayID)) {
                        ForEach(RecorderShareableContentLoader.availableDisplays(), id: \.id) { display in
                            Text(display.name).tag(display.id)
                        }
                    }
                    .frame(maxWidth: 320)
                case .window:
                    windowSourcePicker
                case .area:
                    HStack(spacing: 10) {
                        Text(draft?.areaDescription ?? "尚未选择区域")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Button("选择区域…") {
                            beginAreaSelection()
                        }
                        .controlSize(.small)
                    }
                case nil:
                    EmptyView()
                }
            }
            .padding(8)
        }
    }

    private var windowSourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoadingWindows {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在读取窗口…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if windowLoadFailed {
                Text("无法读取窗口列表，请确认屏幕录制权限。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else if windows.isEmpty {
                Text("没有可录制的窗口，请确认目标窗口未最小化。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(windows) { window in
                        Button {
                            selectWindow(window)
                        } label: {
                            if draft?.windowID == window.id {
                                Label(window.displayName, systemImage: "checkmark")
                            } else {
                                Text(window.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedWindowTitle)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 360)
            }
            Text("窗口按 ID + 应用 Bundle ID + 标题校验；窗口关闭后本次计划会跳过。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private var audioSection: some View {
        GroupBox(label: Label("声音采集", systemImage: "waveform.badge.mic")) {
            HStack(spacing: 18) {
                Toggle("系统声音", isOn: bind(\.profile.capturesSystemAudio))
                    .toggleStyle(.checkbox)
                Toggle("麦克风", isOn: bind(\.profile.capturesMicrophone))
                    .toggleStyle(.checkbox)
            }
            .font(.system(size: 12))
            .padding(8)
        }
    }

    private var qualitySection: some View {
        GroupBox(label: Label("画质与编码", systemImage: "film")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("画质").frame(width: 48, alignment: .leading)
                    Picker("画质", selection: bind(\.profile.quality)) {
                        ForEach(RecorderQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                HStack {
                    Text("帧率").frame(width: 48, alignment: .leading)
                    Picker("帧率", selection: bind(\.profile.fps)) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                HStack {
                    Text("编码").frame(width: 48, alignment: .leading)
                    Picker("编码", selection: bind(\.profile.codec)) {
                        ForEach(RecorderCodec.allCases) { codec in
                            Text(codec.title).tag(codec)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                Toggle("包含鼠标指针", isOn: bind(\.profile.includeCursor))
                    .toggleStyle(.checkbox)
            }
            .font(.system(size: 12))
            .padding(8)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            if let draft, coordinator.schedules.contains(where: { $0.id == draft.id }) {
                Button("删除计划", role: .destructive) {
                    if let error = coordinator.delete(id: draft.id) {
                        errorMessage = error
                    } else {
                        selection = nil
                        self.draft = nil
                        statusMessage = "计划已删除"
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCurrentScheduleRunning || isSaving)
            }
            Spacer()
            if !isCurrentScheduleRunning {
                Button(isSaving ? "保存中…" : "保存计划") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    // MARK: 操作

    private func createNew() {
        selection = nil
        draft = RecorderScheduleDraft()
        errorMessage = nil
        statusMessage = nil
    }

    private func selectWindow(_ window: RecorderWindowInfo) {
        draft?.windowID = window.id
        draft?.windowBundleIdentifier = window.bundleIdentifier
        draft?.windowTitle = window.title
        draft?.sourceMode = .window
    }

    private var selectedWindowTitle: String {
        guard let draft else { return "选择窗口" }
        if let window = windows.first(where: { $0.id == draft.windowID }) {
            return window.displayName
        }
        if !draft.windowTitle.isEmpty || !draft.windowBundleIdentifier.isEmpty {
            return "\(draft.windowTitle.isEmpty ? draft.windowBundleIdentifier : draft.windowTitle)（当前不可用）"
        }
        return "选择窗口"
    }

    private func beginAreaSelection() {
        RecorderScheduleWindowController.shared.hideForSelection()
        RecorderAreaSelector.shared.show { region in
            Task { @MainActor in
                RecorderScheduleWindowController.shared.restoreAfterSelection()
                guard let region else { return }
                switch region {
                case .area(let displayID, let rect):
                    draft?.sourceMode = .area
                    draft?.areaDisplayID = displayID
                    draft?.areaRect = rect
                case .display(let displayID):
                    draft?.sourceMode = .display
                    draft?.displayID = displayID
                case .window:
                    break
                }
            }
        }
    }

    private func loadWindowsIfNeeded() async {
        guard windows.isEmpty, !isLoadingWindows else { return }
        isLoadingWindows = true
        windowLoadFailed = false
        defer { isLoadingWindows = false }
        do {
            windows = try await RecorderShareableContentLoader.loadWindows()
        } catch {
            windowLoadFailed = true
        }
    }

    private func save() {
        guard let draft else { return }
        isSaving = true
        errorMessage = nil
        statusMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            if let sourceError = await validateSource(draft) {
                errorMessage = sourceError
                return
            }
            var candidate = draft.buildSchedule()
            // 列表开关、自动停用与执行结果由协调器维护，保存时以协调器当前值覆盖草稿快照
            if let current = coordinator.schedule(id: candidate.id) {
                candidate.isEnabled = current.isEnabled
                candidate.lastOutcome = current.lastOutcome
            }
            if let error = coordinator.save(candidate) {
                errorMessage = error
                return
            }
            selection = candidate.id
            self.draft = RecorderScheduleDraft(schedule: coordinator.schedule(id: candidate.id) ?? candidate)
            statusMessage = "计划已保存"
        }
    }

    private func validateSource(_ draft: RecorderScheduleDraft) async -> String? {
        switch draft.sourceMode {
        case .display:
            guard CGDisplayIsOnline(draft.displayID) != 0 else {
                return "所选显示器当前不可用，请重新选择"
            }
        case .area:
            guard CGDisplayIsOnline(draft.areaDisplayID) != 0 else {
                return "所选显示器当前不可用，请重新选择区域"
            }
            let bounds = CGDisplayBounds(draft.areaDisplayID)
            guard draft.areaRect.width >= 16, draft.areaRect.height >= 16,
                  CGRect(origin: .zero, size: bounds.size).contains(draft.areaRect) else {
                return "所选区域已超出显示器范围，请重新选择"
            }
        case .window:
            guard let windowID = draft.windowID else {
                return "请选择要录制的窗口"
            }
            do {
                let current = try await RecorderShareableContentLoader.loadWindows()
                guard let window = current.first(where: { $0.id == windowID }),
                      window.bundleIdentifier == draft.windowBundleIdentifier,
                      window.title == draft.windowTitle else {
                    return "所选窗口已关闭或已变化，请重新选择"
                }
            } catch {
                return "无法校验窗口状态，请确认屏幕录制权限"
            }
        }
        return nil
    }

    // MARK: 状态

    private func isRunning(_ id: UUID) -> Bool {
        coordinator.activeRun?.scheduleID == id
    }

    private var isCurrentScheduleRunning: Bool {
        guard let draft else { return false }
        return isRunning(draft.id)
    }

    private func nextText(for schedule: RecorderSchedule) -> String {
        if isRunning(schedule.id), let run = coordinator.activeRun {
            return "录制中，至 \(timeText(run.windowEnd))"
        }
        guard schedule.isEnabled else { return "已停用" }

        let now = Date()
        if let window = engine.occurrence(containing: now, for: schedule) {
            if let outcome = schedule.lastOutcome,
               outcome.date >= window.start.addingTimeInterval(-RecorderScheduleLimits.preStartReminder),
               outcome.date < window.end {
                switch outcome.kind {
                case .skipped: return "本次已跳过"
                case .failed: return "本次失败"
                case .completed, .stopped: return "本次已结束"
                }
            }
            return "本次待执行"
        }

        guard let window = engine.upcomingOccurrence(after: now, for: schedule) else {
            return "没有后续执行"
        }
        return "下次 \(dateText(window.start))"
    }

    private func nextColor(for schedule: RecorderSchedule) -> Color {
        isRunning(schedule.id) ? .red : .secondary
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func bind<Value>(_ keyPath: WritableKeyPath<RecorderScheduleDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { draft?[keyPath: keyPath] = $0 }
        )
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 显示器列表

extension RecorderShareableContentLoader {
    static func availableDisplays() -> [(id: CGDirectDisplayID, name: String)] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = displayID(of: screen)
            let name = screen.localizedName.isEmpty ? "显示器 \(index + 1)" : screen.localizedName
            return (id, name)
        }
    }
}
