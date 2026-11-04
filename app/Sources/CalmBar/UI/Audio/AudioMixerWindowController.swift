import AppKit
import SwiftUI

// MARK: - 音频混音窗口（760×560，PRD §5.4）

@MainActor
final class AudioMixerWindowController: NSObject, NSWindowDelegate {
    static let shared = AudioMixerWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar 音频控制"
        win.minSize = NSSize(width: 680, height: 480)
        win.center()
        win.contentViewController = NSHostingController(rootView: AudioMixerWindowView())
        // SwiftUI 首帧未完成测量，contentViewController 会把窗口压到 minSize；此处强制回写尺寸
        win.setContentSize(NSSize(width: 760, height: 560))
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win

        // 音频总开关关闭时保持引擎停用，窗口内会显示 unavailableHint 引导用户去设置启用
        if AppSettings.shared.audioHubEnabled {
            AudioMixerService.shared.start()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let win = window, (notification.object as? NSWindow) === win {
            window = nil
        }
    }
}

struct AudioMixerWindowView: View {
    @ObservedObject private var service = AudioMixerService.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var searchText = ""
    @State private var showResetConfirm = false

    private var activeRows: [AudioAppInfo] {
        service.apps.filter { $0.isPlaying }.filter(matchesSearch)
    }

    private var inactiveRows: [AudioAppInfo] {
        guard service.showsInactiveApps else { return [] }
        return service.apps.filter { !$0.isPlaying }.filter(matchesSearch)
    }

    private func matchesSearch(_ app: AudioAppInfo) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return app.name.lowercased().contains(query)
            || (app.bundleID ?? "").lowercased().contains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { service.refresh() }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("音频控制")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("搜索应用", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .frame(width: 200)
            }

            HStack(spacing: 12) {
                Text("输出设备")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(service.outputDevices) { device in
                        Button {
                            service.setSystemOutputDevice(device.uid)
                        } label: {
                            if device.isDefault {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(service.systemOutputName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 220)

                Spacer()

                Toggle("显示非活动应用", isOn: $service.showsInactiveApps)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: 列表

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if !service.isRunning {
                    unavailableHint
                }

                groupHeader("正在播放", count: activeRows.count)
                if activeRows.isEmpty {
                    emptyState
                } else {
                    ForEach(activeRows) { app in
                        AudioMixerRow(app: app, service: service)
                    }
                }

                if service.showsInactiveApps {
                    groupHeader("其他应用", count: inactiveRows.count)
                    ForEach(inactiveRows) { app in
                        AudioMixerRow(app: app, service: service)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.automatic)
    }

    private var unavailableHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(service.lastError ?? "音频引擎未运行，请在偏好设置中启用音频路由与混音")
                .font(.system(size: 12))
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("暂无正在输出音频的应用")
                .font(.system(size: 13, weight: .medium))
            Text("播放任意声音后会自动出现在这里")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: 底栏

    private var footer: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(service.isRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(service.statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text("增强上限 \(settings.audioBoostEnabled ? "\(settings.audioBoostMaxPercent)%" : "关闭")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("恢复全部默认") {
                showResetConfirm = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .alert("恢复全部默认", isPresented: $showResetConfirm) {
            Button("恢复", role: .destructive) {
                service.resetAllApps()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除所有 App 的音量与输出路由设置，应用回到系统默认播放。")
        }
    }
}

// MARK: - 单行

private struct AudioMixerRow: View {
    let app: AudioAppInfo
    @ObservedObject var service: AudioMixerService

    private var upperBound: Double {
        service.boostUpperBoundGain
    }

    private var selectedDeviceName: String {
        guard let uid = app.outputDeviceUID,
              let device = service.outputDevices.first(where: { $0.uid == uid }) else {
            return "跟随系统"
        }
        return device.name
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(app.isPlaying ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            iconView
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(app.isProtected ? "受保护音频" : (app.bundleID ?? "未知来源"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            Slider(
                value: Binding(
                    get: { min(app.volume, upperBound) },
                    set: { service.setVolume($0, for: app.id) }
                ),
                in: 0...upperBound
            )
            .controlSize(.small)
            .disabled(app.isProtected)
            .frame(minWidth: 160)
            .opacity(app.isMuted ? 0.45 : 1)

            Text("\(Int((min(app.volume, upperBound) * 100).rounded()))%")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)

            Button {
                service.toggleMute(for: app.id)
            } label: {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(app.isMuted ? Color.red : Color.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.isProtected)
            .help(app.isMuted ? "取消静音" : "静音")

            if app.isProtected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("系统提示音与通话音频不参与音量接管")
                    .frame(width: 130)
            } else {
                Menu {
                    Button("跟随系统") {
                        service.setOutputDevice(nil, for: app.id)
                    }
                    Divider()
                    ForEach(service.outputDevices) { device in
                        Button(device.name) {
                            service.setOutputDevice(device.uid, for: app.id)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedDeviceName)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 140, height: 24, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 140)
                .disabled(!AppSettings.shared.audioRoutingEnabled)
                .help("选择该应用的输出设备")
            }
        }
        .frame(height: 46)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
