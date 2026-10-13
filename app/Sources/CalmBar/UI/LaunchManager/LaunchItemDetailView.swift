import SwiftUI
import AppKit

public struct LaunchItemDetailView: View {
    public let item: LaunchItem
    public let onClose: () -> Void

    @State private var selectedTab: DetailTab = .overview
    @State private var stdoutLogs: String = ""
    @State private var stderrLogs: String = ""
    @State private var systemLogs: String = ""
    @State private var isFetchingSystemLogs: Bool = false
    @State private var systemLogErrorMessage: String? = nil
    @State private var xmlContent: String = ""

    private enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "配置详情"
        case logs = "输出日志"
        case xml = "Plist 源码"

        var id: String { rawValue }
    }

    public init(item: LaunchItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.appName ?? item.label)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(item.label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                }

                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(.ultraThinMaterial)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview:
                        overviewSection
                    case .logs:
                        logsSection
                    case .xml:
                        xmlSection
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            loadLogs()
            loadXml()
        }
    }

    // MARK: - Overview Section

    @ViewBuilder
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 操作工具栏
            if !item.scope.isReadOnly {
                HStack(spacing: 10) {
                    Button {
                        Task { await LaunchManager.shared.refreshAll() }
                    } label: {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task { await LaunchManager.shared.reloadItem(item) }
                    } label: {
                        Label(
                            item.scope.requiresPrivilegeForService ? "重启服务 (需管理员权限)" : "重启服务 (Kickstart)",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
            }

            // 基本属性卡片
            GroupBox("基本信息") {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow(title: "管理域 (Scope)", value: item.scope.displayName)
                    detailRow(title: "配置文件路径", value: item.plistURL.path, showRevealButton: true)
                    if let pid = item.pid {
                        detailRow(title: "当前进程 PID", value: "\(pid)")
                    }
                    if let exitCode = item.lastExitCode {
                        detailRow(title: "上次退出状态码", value: "\(exitCode)")
                    }
                }
                .padding(6)
            }

            // 执行参数卡片
            GroupBox("启动与环境") {
                VStack(alignment: .leading, spacing: 8) {
                    if let prog = item.program {
                        detailRow(title: "执行程序 (Program)", value: prog)
                    }
                    if !item.programArguments.isEmpty {
                        detailRow(title: "完整参数 (Arguments)", value: item.programArguments.joined(separator: " "))
                    }
                    if let cwd = item.workingDirectory {
                        detailRow(title: "工作目录 (WorkingDirectory)", value: cwd)
                    }
                    if !item.environmentVariables.isEmpty {
                        detailRow(title: "环境变量", value: item.environmentVariables.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
                    }
                }
                .padding(6)
            }

            // 调度策略
            GroupBox("触发与守护策略") {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow(title: "开机载入 (RunAtLoad)", value: item.runAtLoad ? "是 (开机自动装载运行)" : "否")
                    detailRow(title: "进程守护 (KeepAlive)", value: item.keepAlive.displayDescription)
                    if let interval = item.startInterval {
                        detailRow(title: "定时周期 (StartInterval)", value: "每 \(interval) 秒触发一次")
                    }
                    if !item.watchPaths.isEmpty {
                        detailRow(title: "目录监听 (WatchPaths)", value: item.watchPaths.joined(separator: ", "))
                    }
                }
                .padding(6)
            }
        }
    }

    // MARK: - Logs Section

    @ViewBuilder
    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标准输出
            GroupBox("标准输出 (StandardOut)") {
                VStack(alignment: .leading, spacing: 6) {
                    if let path = item.standardOutPath {
                        Text(path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    logViewer(content: stdoutLogs.isEmpty ? "暂无输出内容或未配置文件重定向" : stdoutLogs)
                }
                .padding(6)
            }

            // 标准错误
            GroupBox("错误输出 (StandardError)") {
                VStack(alignment: .leading, spacing: 6) {
                    if let path = item.standardErrorPath {
                        Text(path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    logViewer(content: stderrLogs.isEmpty ? "暂无错误输出" : stderrLogs)
                }
                .padding(6)
            }

            // 系统统一日志 (按需提取)
            GroupBox("macOS 系统统一日志 (按需提取)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("仅在未重定向文件时排查崩溃问题使用 (最后 10 分钟)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isFetchingSystemLogs {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("提取系统日志 (2.5s 熔断)") {
                                fetchSystemLogs()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if let err = systemLogErrorMessage {
                        Text(err).font(.system(size: 11)).foregroundStyle(.red)
                    }

                    if !systemLogs.isEmpty {
                        logViewer(content: systemLogs)
                    }
                }
                .padding(6)
            }
        }
    }

    // MARK: - XML Section

    @ViewBuilder
    private var xmlSection: some View {
        GroupBox("Plist XML 源码") {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.plistURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(xmlContent)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
                .frame(minHeight: 300)
            }
            .padding(6)
        }
    }

    // MARK: - Helpers

    private func detailRow(title: String, value: String, showRevealButton: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)

            if showRevealButton {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("在 Finder 中高亮显示")
            }

            Spacer()
        }
    }

    private func logViewer(content: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(content)
                .font(.system(size: 10, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
        .cornerRadius(6)
        .frame(minHeight: 80, maxHeight: 150)
    }

    private func loadLogs() {
        if let outPath = item.standardOutPath, FileManager.default.fileExists(atPath: outPath) {
            stdoutLogs = readTail(of: outPath, lines: 100)
        }
        if let errPath = item.standardErrorPath, FileManager.default.fileExists(atPath: errPath) {
            stderrLogs = readTail(of: errPath, lines: 100)
        }
    }

    private func loadXml() {
        if let data = try? Data(contentsOf: item.plistURL),
           let str = String(data: data, encoding: .utf8) {
            xmlContent = str
        }
    }

    private func readTail(of path: String, lines: Int) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let str = String(data: data, encoding: .utf8) else { return "" }
        let allLines = str.components(separatedBy: "\n")
        let tailLines = allLines.suffix(lines)
        return tailLines.joined(separator: "\n")
    }

    private func fetchSystemLogs() {
        isFetchingSystemLogs = true
        systemLogErrorMessage = nil
        Task {
            defer { isFetchingSystemLogs = false }
            do {
                let procName = item.program ?? item.label
                let predicate = "subsystem == '\(item.label)' OR process == '\(procName)'"
                let output = try await ShellRunner.runAsync(
                    "/usr/bin/log",
                    arguments: ["show", "--predicate", predicate, "--last", "10m", "--style", "compact"],
                    timeout: 2.5
                )
                self.systemLogs = output.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                self.systemLogErrorMessage = "获取系统日志超时或失败: \(error.localizedDescription)"
            }
        }
    }
}
