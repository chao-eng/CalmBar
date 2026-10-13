import SwiftUI

public struct LaunchManagerGuideSheetView: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 16))
                    Text("macOS 自启与常驻服务机制说明")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(14)
            .background(.ultraThinMaterial)

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. 与系统设置的差异
                    cardContainer(
                        icon: "gearshape.2.fill",
                        color: .blue,
                        title: "1. 为什么与「系统设置 - 登录项与扩展」显示不同？"
                    ) {
                        Text("macOS 系统的自启机制实际上分为两个完全不同的层级：")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        guideItem(
                            title: "【登录时打开】(应用级登录项)",
                            body: "系统设置上半部分展示的是图形应用（如微信、CalmBar 等）。它们是用户登录 Mac 桌面后直接拉起窗口运行的常规 App，由系统的 LaunchServices 框架维护。"
                        )

                        guideItem(
                            title: "【允许在后台】(macOS 13+ BTM 聚合管理 与 为什么单页看起来更少)",
                            body: "系统设置下半部分的「允许在后台」并不是单一目录，而是将三大目录（~/Library/LaunchAgents、/Library/LaunchAgents、/Library/LaunchDaemons）以及现代应用嵌入在 App 安装包内的 SMAppService 辅助工具全部混在一起，并按「软件开发商」进行卡片折叠展示。\nCalmBar 为了精准排查，将它们严格分门别类为「用户自启项」、「全局自启项」与「系统守护服务」三个独立标签页。将对应标签页的项目相加，即可涵盖系统的所有物理常驻项。"
                        )

                        guideItem(
                            title: "系统守护服务的真实状态 (system domain)",
                            body: "系统守护服务由系统最高特权 root 在开机时启动（位于 system 域）。CalmBar 穿透查询 macOS launchd system 域探针，实时反映守护进程的常驻 PID、空闲待命或崩溃状态。"
                        )
                    }

                    // 2. 三大自启目录与作用域对比
                    cardContainer(
                        icon: "folder.fill.badge.gearshape",
                        color: .purple,
                        title: "2. 三大自启作用域 (Scopes) 区别解析"
                    ) {
                        Text("macOS 根据权限与宿主将自启配置文件严格划分在三个目录：")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        scopeItem(
                            title: "用户自启项",
                            path: "~/Library/LaunchAgents",
                            user: "当前登录用户（普通权限）",
                            trigger: "仅当当前用户登录 Mac 桌面时启动",
                            usage: "个人软件的后台更新、菜单栏常驻、免密写入。"
                        )

                        scopeItem(
                            title: "全局自启项",
                            path: "/Library/LaunchAgents",
                            user: "当前登录用户（普通权限）",
                            trigger: "任何用户登录 Mac 桌面时均会启动",
                            usage: "全机共享的软件辅助工具、浏览器更新器、企业合规 Agent（修改需管理员密码）。"
                        )

                        scopeItem(
                            title: "系统守护服务",
                            path: "/Library/LaunchDaemons",
                            user: "root（系统最高特权）",
                            trigger: "电脑开机即运行（无论是否有用户登录图形桌面）",
                            usage: "底层数据库、网络过滤驱动、虚拟机核心、系统级监控服务（完全受限保护）。"
                        )
                    }

                    // 3. 排障与安全提示
                    cardContainer(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "3. 常见异常与排障小技巧"
                    ) {
                        guideItem(
                            title: "退出码为 78 是什么意思？",
                            body: "退出码 78 代表 EX_CONFIG（可执行程序不存在）。通常是因为软件已被卸载或删除，但残留的 plist 自启文件未清理。系统会陷入死循环报错，建议在 CalmBar 中直接点击「垃圾桶」删除。"
                        )

                        guideItem(
                            title: "删除安全吗？",
                            body: "CalmBar 在删除任何自启项前均会自动在本地创建无损备份快照。若误删，可在「快照恢复中心」中一键还原。"
                        )

                        guideItem(
                            title: "为什么不能修改系统守护？",
                            body: "Apple 系统的核心组件（/System/Library）受到 macOS SIP（系统完整性保护）硬性只读保护，禁止任何第三方软件改动。"
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("我明白了") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .frame(width: 620, height: 540)
    }

    // MARK: - Components

    private func cardContainer<Content: View>(
        icon: String,
        color: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            content()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }

    private func guideItem(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scopeItem(title: String, path: String, user: String, trigger: String, usage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("• 运行身份：\(user)")
                Text("• 启动时机：\(trigger)")
                Text("• 常见用途：\(usage)")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}
