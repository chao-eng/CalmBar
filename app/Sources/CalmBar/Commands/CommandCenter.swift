import Combine
import Foundation

@MainActor
public final class CommandCenter: ObservableObject {
    public static let shared = CommandCenter()

    @Published public private(set) var registeredCommands: [CommandDescriptor] = []

    public init() {
        registerBuiltInCommands()
    }

    public func register(_ command: CommandDescriptor) {
        if let idx = registeredCommands.firstIndex(where: { $0.id == command.id }) {
            registeredCommands[idx] = command
        } else {
            registeredCommands.append(command)
        }
    }

    public func command(id: String) -> CommandDescriptor? {
        registeredCommands.first(where: { $0.id == id })
    }

    public func search(query: String) -> [CommandDescriptor] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return registeredCommands
        }
        return registeredCommands.filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(q) ||
            (cmd.subtitle?.localizedCaseInsensitiveContains(q) ?? false) ||
            cmd.category.displayName.localizedCaseInsensitiveContains(q) ||
            cmd.aliases.contains(where: { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    public func execute(command: CommandDescriptor) async -> CommandResult {
        // Pre-flight permission check
        for perm in command.requiredPermissions {
            if !PermissionManager.shared.isGranted(perm) {
                return .permissionDenied(perm)
            }
        }

        return await command.run()
    }

    public func registerBuiltInCommands() {
        // 1. Settings & Permissions
        register(CommandDescriptor(
            id: "system.settings",
            title: "打开偏好设置",
            subtitle: "配置 CalmBar 各模块偏好",
            iconName: "gearshape",
            category: .general,
            aliases: ["settings", "preferences", "sz"],
            run: {
                StatusBarManager.shared.openSettingsWindow()
                return .success("已打开偏好设置")
            }
        ))

        register(CommandDescriptor(
            id: "system.permissions",
            title: "打开权限安全中心",
            subtitle: "查看与管理系统授权状态",
            iconName: "shield.lefthalf.filled",
            category: .general,
            aliases: ["permission", "qx", "auth"],
            run: {
                StatusBarManager.shared.openSettingsWindow(tab: .permissions)
                return .success("已打开权限中心")
            }
        ))

        // 2. OCR
        register(CommandDescriptor(
            id: "ocr.capture",
            title: "开始屏幕选区识字",
            subtitle: "框选屏幕区域离线识别文字与二维码",
            iconName: "text.viewfinder",
            category: .productivity,
            featureID: .ocr,
            requiredPermissions: [.screenRecording],
            aliases: ["ocr", "sz", "capture", "shizi", "qrcode"],
            run: {
                OCRManager.shared.startCaptureAndRecognize()
                return .success("已启动选区截屏")
            }
        ))

        register(CommandDescriptor(
            id: "ocr.history",
            title: "打开 OCR 历史记录",
            subtitle: "查看和复制历史识别结果",
            iconName: "clock.arrow.circlepath",
            category: .productivity,
            featureID: .ocr,
            aliases: ["ocrhistory", "ls"],
            run: {
                StatusBarManager.shared.openSettingsWindow(tab: .ocr)
                return .success("已打开 OCR 历史")
            }
        ))

        // 3. Clipboard
        register(CommandDescriptor(
            id: "clipboard.history",
            title: "打开剪贴板历史",
            subtitle: "查看、搜索与粘贴历史剪贴板记录",
            iconName: "doc.on.clipboard",
            category: .productivity,
            featureID: .clipboard,
            aliases: ["clipboard", "jtb", "history"],
            run: {
                StatusBarManager.shared.openSettingsWindow(tab: .clipboard)
                return .success("已打开剪贴板历史")
            }
        ))

        // 4. Caffeine
        register(CommandDescriptor(
            id: "caffeine.toggle",
            title: "切换防休眠状态",
            subtitle: "阻止系统和显示器进入休眠",
            iconName: "cup.and.saucer",
            category: .system,
            featureID: .caffeine,
            aliases: ["caffeine", "awake", "fxm", "xiuxian"],
            run: {
                CaffeineManager.shared.toggle()
                return .success("已切换防休眠状态")
            }
        ))

        // 5. Battery
        register(CommandDescriptor(
            id: "battery.topUp",
            title: "电池临时充至 100%",
            subtitle: "出门前临时解除 80% 充电上限限制",
            iconName: "battery.100.bolt",
            category: .hardware,
            featureID: .battery,
            requiredPermissions: [.privilegedHelper],
            aliases: ["topup", "cm", "battery"],
            run: {
                BatteryChargeManager.shared.toggleTopUp()
                return .success("已切换临时充满模式")
            }
        ))

        // 6. Scroll
        register(CommandDescriptor(
            id: "scroll.toggle",
            title: "切换鼠标滚轮反转",
            subtitle: "独立反转外接鼠标与触控板方向",
            iconName: "computermouse",
            category: .input,
            featureID: .scroll,
            requiredPermissions: [.accessibility],
            aliases: ["scroll", "gl", "mouse"],
            run: {
                AppSettings.shared.scrollReverserEnabled.toggle()
                return .success("已切换滚轮反转")
            }
        ))

        // 7. MenuBar
        register(CommandDescriptor(
            id: "menubar.toggle",
            title: "展开/折叠菜单栏",
            subtitle: "收纳隐藏低频菜单栏图标",
            iconName: "menubar.rectangle",
            category: .system,
            featureID: .menuBar,
            aliases: ["menubar", "fold", "sn", "cdl"],
            run: {
                MenuBarOrganizer.shared.toggleExpandCollapse()
                return .success("已切换菜单栏折叠")
            }
        ))

        // 8. Cleaner
        register(CommandDescriptor(
            id: "cleaner.scanDev",
            title: "扫描开发工具链缓存",
            subtitle: "扫描 Xcode、Node、Python 等开发缓存与工作区",
            iconName: "hammer",
            category: .cleanup,
            featureID: .cleaner,
            aliases: ["dev", "clean", "xcode", "npm", "cache"],
            run: {
                CleanerManager.shared.refreshDevCaches()
                StatusBarManager.shared.openSettingsWindow(tab: .cleaner)
                return .success("已开始扫描开发缓存")
            }
        ))

        register(CommandDescriptor(
            id: "cleaner.scanApps",
            title: "扫描已安装应用",
            subtitle: "扫描应用程序及其 Library 残留缓存",
            iconName: "trash",
            category: .cleanup,
            featureID: .cleaner,
            aliases: ["app", "clean", "uninstall", "xz"],
            run: {
                CleanerManager.shared.refreshAllApps()
                StatusBarManager.shared.openSettingsWindow(tab: .cleaner)
                return .success("已开始扫描应用程序")
            }
        ))
    }
}
