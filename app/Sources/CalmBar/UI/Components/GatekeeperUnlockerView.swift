import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct GatekeeperUnlockerView: View {
    @ObservedObject private var manager = GatekeeperManager.shared
    @State private var isTargeted = false
    @State private var deepSign = false
    @State private var showApplicationsPicker = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 功能介绍与说明卡片
                headerInfoCard

                // 拖拽投递区域
                dropZoneView

                // 功能控制栏与手动选择
                actionControlsView

                // 状态结果与操作历史
                resultsAndHistorySection
            }
            .padding(16)
        }
    }

    // MARK: - Header Info Card
    private var headerInfoCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))

                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS 软件签名与 Gatekeeper 隔离修复")
                        .font(.system(size: 13, weight: .bold))
                    Text("从外部下载的未公证或修改版应用，系统会拦截并提示「已损坏，无法打开」或「无法验证开发者」。将应用拖拽到此处，即可一键执行递归解除隔离与重新自签名。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
        }
    }

    // MARK: - Drop Zone View
    private var dropZoneView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [8, 4] : [6, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .animation(.easeInOut(duration: 0.2), value: isTargeted)
                .frame(minHeight: 140)

            VStack(spacing: 10) {
                if manager.isProcessing {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在解除隔离与修复签名...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: isTargeted ? "arrow.down.app.fill" : "lock.open.badge.checkmark")
                        .font(.system(size: 34))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                    Text(isTargeted ? "松开鼠标立即执行授权" : "拖拽 App 或文件夹到此处")
                        .font(.system(size: 14, weight: .semibold))

                    Text("支持 .app 应用、安装包目录或 .dmg 挂载卷")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Action Controls View
    private var actionControlsView: some View {
        VStack(spacing: 10) {
            HStack {
                Toggle(isOn: $deepSign) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("深度修复 (Ad-hoc 强制重新签名)")
                            .font(.system(size: 12, weight: .medium))
                        Text("若解除隔离后仍闪退或提示损坏，开启此项自动执行 codesign 重签")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button {
                    selectFileWithOpenPanel()
                } label: {
                    Label("浏览选择应用...", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 12, weight: .medium))
                }
                .disabled(manager.isProcessing)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Results and History Section
    @ViewBuilder
    private var resultsAndHistorySection: some View {
        if !manager.history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("授权记录")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("清空记录") {
                        manager.clearHistory()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }

                VStack(spacing: 8) {
                    ForEach(manager.history) { item in
                        historyRow(item: item)
                    }
                }
            }
        }
    }

    private func historyRow(item: GatekeeperManager.UnlockResult) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(item.success ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.appName)
                        .font(.system(size: 12, weight: .semibold))

                    if item.isDeepSigned {
                        Text("已重签")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }

                Text(item.message)
                    .font(.system(size: 11))
                    .foregroundColor(item.success ? .secondary : .red)

                Text(item.path)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if item.success && FileManager.default.fileExists(atPath: item.path) {
                Button {
                    NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("在访达中显示")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        )
    }

    // MARK: - Drop & OpenPanel Handlers
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data else { return }
                let url: URL?
                if let u = URL(dataRepresentation: data, relativeTo: nil) {
                    url = u
                } else if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let u = URL(string: str) {
                    url = u
                } else {
                    url = nil
                }
                guard let validURL = url else { return }
                Task { @MainActor in
                    _ = await self.manager.unlockPath(validURL, deepSign: self.deepSign)
                }
            }
        }
        return true
    }

    private func selectFileWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择需要解除隔离或授权的应用/目录"
        panel.prompt = "一键授权"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application, UTType.folder, UTType.package]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task {
                _ = await manager.unlockPaths(urls, deepSign: deepSign)
            }
        }
    }
}
