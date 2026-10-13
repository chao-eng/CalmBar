import SwiftUI

public struct ListeningServicesView: View {
    @ObservedObject private var manager = LaunchManager.shared
    @State private var searchQuery: String = ""
    @State private var serviceToMakeAgent: ListeningServiceItem?
    @State private var serviceToKill: ListeningServiceItem?
    @State private var createdAgentSuccessName: String?
    @State private var showTipsBanner: Bool = true

    public init() {}

    public var filteredServices: [ListeningServiceItem] {
        if searchQuery.isEmpty {
            return manager.listeningServices
        }
        let q = searchQuery.lowercased()
        return manager.listeningServices.filter {
            "\($0.port)".contains(q) ||
            $0.processName.lowercased().contains(q) ||
            ($0.commandLine?.lowercased().contains(q) ?? false) ||
            ($0.containerName?.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索端口或服务进程...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .focusEffectDisabled()
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                Spacer()

                Button {
                    Task { await manager.refreshListeningPorts() }
                } label: {
                    if manager.isScanningPorts {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新端口", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isScanningPorts)
            }
            .padding(12)
            .background(.ultraThinMaterial)

            Divider()

            // 小白用户友好说明横幅
            if showTipsBanner {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("💡 什么是「服务监听」与「设为开机常驻」？")
                            .font(.system(size: 12, weight: .semibold))

                        Text("• 服务监听：展示本机当前正在对外提供网络服务的进程（如开发服务、数据库或代理）。\n• 设为开机常驻：将临时运行的服务封装为系统后台守护任务（LaunchAgent），电脑开机后自动在后台静默运行。适合本地工具或代理，普通临时调试项目无需点击。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }

                    Spacer()

                    Button {
                        withAnimation { showTipsBanner = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("关闭说明")
                }
                .padding(10)
                .background(Color.blue.opacity(0.07))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // List
            if manager.isScanningPorts && manager.listeningServices.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("正在扫描服务监听端口与 Docker 容器...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if filteredServices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("暂无活跃的服务监听端口")
                        .font(.system(size: 14, weight: .medium))
                    Text("请确认是否有 Web 服务 (如 Next.js、Go、Python) 或数据库在本地运行")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(filteredServices) { service in
                    serviceRow(service)
                }
                .listStyle(.inset)
            }
        }
        .task {
            if manager.listeningServices.isEmpty {
                await manager.refreshListeningPorts()
            }
        }
        .confirmationDialog(
            "确认将该服务设为开机常驻？",
            isPresented: Binding(
                get: { serviceToMakeAgent != nil },
                set: { if !$0 { serviceToMakeAgent = nil } }
            ),
            titleVisibility: .visible,
            presenting: serviceToMakeAgent
        ) { service in
            Button("确认生成后台自启任务") {
                Task {
                    await manager.createAgent(from: service)
                    // 仅在未产生错误时提示成功，避免失败仍弹出成功提示
                    if manager.errorMessage == nil {
                        createdAgentSuccessName = service.processName
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: { service in
            Text("将为进程「\(service.processName)」(端口 :\(service.port)) 自动生成系统 LaunchAgent 配置文件并激活。\n\n开机登录后该服务将在后台自动运行并保活。若仅为临时开发测试，请点击取消。")
        }
        .confirmationDialog(
            "确认终止该端口进程？",
            isPresented: Binding(
                get: { serviceToKill != nil },
                set: { if !$0 { serviceToKill = nil } }
            ),
            titleVisibility: .visible,
            presenting: serviceToKill
        ) { service in
            Button("强制终止进程 (Kill)", role: .destructive) {
                kill(Int32(service.pid), SIGTERM)
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await manager.refreshListeningPorts()
                }
            }
            Button("取消", role: .cancel) {}
        } message: { service in
            Text("将向进程「\(service.processName)」(PID: \(service.pid), 端口 :\(service.port)) 发送终止信号 (SIGTERM)。这会导致当前连接被断开。")
        }
        .alert(
            "已成功创建开机常驻服务",
            isPresented: Binding(
                get: { createdAgentSuccessName != nil },
                set: { if !$0 { createdAgentSuccessName = nil } }
            )
        ) {
            Button("知道了") { createdAgentSuccessName = nil }
        } message: {
            if let name = createdAgentSuccessName {
                Text("已为「\(name)」成功注册 macOS 后台守护服务。你可以在左侧「自启管理」中随时查看、开启或删除它。")
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { manager.errorMessage = nil }
        } message: {
            if let msg = manager.errorMessage {
                Text(msg)
            }
        }
    }

    private func serviceRow(_ service: ListeningServiceItem) -> some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(service.isDocker ? Color.cyan.opacity(0.12) : Color.blue.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: service.isDocker ? "shippingbox.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13))
                    .foregroundStyle(service.isDocker ? Color.cyan : Color.blue)
            }

            // 进程信息
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(service.processName)
                        .font(.system(size: 13, weight: .semibold))

                    if service.isDocker {
                        HStack(spacing: 3) {
                            Image(systemName: "shippingbox.fill")
                            Text(service.containerName ?? "Docker")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(4)
                    }

                    Spacer()

                    // 占用端口：灰色显示在 PID 之前
                    Text(":\(String(service.port))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("PID: \(String(service.pid))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let cmd = service.commandLine {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let cwd = service.workingDirectory {
                    Text(cwd)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // 操作按键
            HStack(spacing: 8) {
                if service.isDocker {
                    Text("Docker 托管")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .help("此服务运行在 Docker 容器中，由 Docker 引擎自主管理生命周期")
                } else {
                    Button {
                        serviceToMakeAgent = service
                    } label: {
                        Label("设为开机常驻", systemImage: "plus.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("为此服务生成持久化自启 LaunchAgent，开机后自动在后台运行")
                }

                Button(role: .destructive) {
                    serviceToKill = service
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("终止此占用端口的进程 (SIGTERM)")
            }
        }
        .padding(.vertical, 4)
    }
}
