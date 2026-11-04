import SwiftUI
import AppKit

/// 「更新设置」窗口：配置检查与下载更新时使用的网络代理，并可即时测试连通性。
struct UpdateSettingsView: View {
    @ObservedObject var updater: Updater

    private enum ConnectionTest: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    @State private var testState: ConnectionTest = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("更新网络代理")
                .font(.headline)

            Toggle("检查与下载更新时使用代理", isOn: $updater.proxyEnabled)

            HStack(spacing: 10) {
                Text("服务器")
                    .frame(width: 56, alignment: .leading)
                TextField("127.0.0.1", text: $updater.proxyHost)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!updater.proxyEnabled)
            }

            HStack(spacing: 10) {
                Text("端口")
                    .frame(width: 56, alignment: .leading)
                TextField("10808", text: $updater.proxyPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .disabled(!updater.proxyEnabled)
            }

            HStack(spacing: 12) {
                Button("测试连接") { testConnection() }
                    .disabled(testState == .running)
                testStatusView
            }

            Text("说明：代理仅用于 App 内检查更新与下载安装包，仅支持 HTTP/HTTPS 代理（暂不支持账号密码）。Sparkle 的下载器读不到 App 设置，因此下载会经由本机 127.0.0.1 的临时转发完成。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 320, alignment: .topLeading)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            Text("尚未测试")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在连接…").font(.caption)
            }
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func testConnection() {
        testState = .running
        Task { @MainActor in
            let result = await updater.testConnection()
            switch result {
            case .success(let status):
                testState = .success(status > 0 ? "连接成功（HTTP \(status)）" : "连接成功")
            case .failure(let error):
                testState = .failure("连接失败：\(error.localizedDescription)")
            }
        }
    }
}

/// 设置窗口宿主：通用设置「更新设置…」入口打开。
@MainActor
final class UpdateSettingsWindow {
    static let shared = UpdateSettingsWindow()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: UpdateSettingsView(updater: .shared))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "更新设置"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("UpdateSettings")
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
