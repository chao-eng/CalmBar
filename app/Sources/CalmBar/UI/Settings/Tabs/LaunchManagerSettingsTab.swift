import SwiftUI
import CalmBarKit

public struct LaunchManagerSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 主入口卡片
                GroupBox(label: Label("启动项与常驻服务管理", systemImage: "gearshape.arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("统一纳管当前用户自启项、全局 LaunchAgents、系统 LaunchDaemons 以及本地端口占用进程。支持一键禁用流氓残留自启与崩溃死循环熔断。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        Button {
                            LaunchManagerWindowController.shared.show()
                        } label: {
                            Label("打开启动项与服务管理主窗口", systemImage: "macwindow.on.rectangle")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 安全与备份设置
                GroupBox(label: Label("安全防护与自动备份", systemImage: "shield.checkered")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("操作前自动创建快照备份 (推荐开启)", isOn: $settings.launchManagerAutoBackupEnabled)
                            .font(.system(size: 12.5, weight: .medium))

                        Text("在任何修改、停用或删除操作前自动生成 Plist 快照备份，支持在快照中心一键无损还原，保留 30 天。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            Text("死循环崩溃主动告警阈值：")
                                .font(.system(size: 12.5, weight: .medium))
                            Stepper("\(settings.launchManagerCrashLoopAlertThreshold) 次连续崩溃", value: $settings.launchManagerCrashLoopAlertThreshold, in: 1...10)
                                .font(.system(size: 12))
                        }
                        Text("当常驻后台服务异常退出并连续重启达到此阈值时，在菜单栏与主面板发出高亮告警。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 范围与开发者模式
                GroupBox(label: Label("显示范围与模式", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("显示系统级服务 (Global Agents & Launch Daemons)", isOn: $settings.launchManagerShowSystemDaemons)
                            .font(.system(size: 12.5, weight: .medium))

                        Toggle("显示 macOS 系统核心只读项 (需关心的极客用户开启)", isOn: $settings.launchManagerShowAppleProtected)
                            .font(.system(size: 12.5, weight: .medium))

                        Divider()

                        Toggle("启用开发者工具与端口看板", isOn: $settings.launchManagerDeveloperModeEnabled)
                            .font(.system(size: 12.5, weight: .medium))

                        Text("在侧边栏激活本地 TCP 监听端口透视、Docker 容器关联以及一键转自启 Agent 工具。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}
