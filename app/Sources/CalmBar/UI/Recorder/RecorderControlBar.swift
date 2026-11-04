import AppKit
import SwiftUI

// MARK: - 录制控制条（280×44，屏幕顶部居中，PRD §5.8）

@MainActor
final class RecorderControlBarController {
    static let shared = RecorderControlBarController()

    private var panel: NSPanel?

    private init() {}

    func show() {
        let bar = panel ?? makePanel()
        panel = bar
        position(bar)
        bar.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 280, height: 44)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // BR-33：控制条不进入录制画面
        panel.sharingType = .none
        panel.contentViewController = NSHostingController(rootView: RecorderControlBarView())
        // SwiftUI 首帧未完成测量时会被压扁，强制回写固定尺寸
        panel.setContentSize(size)
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height - 8
        )
        panel.setFrameOrigin(origin)
    }
}

struct RecorderControlBarView: View {
    @ObservedObject private var recorder = ScreenRecorderService.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PopoverPalette.accentRed)
                .frame(width: 7, height: 7)

            if recorder.state == .countdown {
                Text("\(recorder.countdownRemaining) 秒后开始")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button {
                    recorder.cancelCountdown()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("取消录制")
            } else if recorder.state == .finalizing {
                ProgressView()
                    .controlSize(.small)
                Text("正在保存…")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
            } else {
                Text(recorder.formattedElapsed)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 48, alignment: .leading)

                Button {
                    recorder.togglePause()
                } label: {
                    Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(recorder.state == .paused ? "继续录制" : "暂停录制")
                .disabled(!recorder.isRecording)

                Button {
                    recorder.stop()
                } label: {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PopoverPalette.accentRed)
                        .frame(width: 11, height: 11)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("停止并保存")

                Spacer(minLength: 2)

                microphoneIndicator
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 280, height: 44)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(PopoverPalette.separatorEmphasized, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var microphoneIndicator: some View {
        Image(systemName: recorder.microphoneEnabled ? "mic.fill" : "mic.slash")
            .font(.system(size: 10))
            .foregroundStyle(recorder.microphoneEnabled ? Color.primary : Color.secondary)
            .frame(width: 14, height: 14)
            .help(recorder.microphoneEnabled ? "麦克风已开启" : "麦克风已关闭")
    }
}
