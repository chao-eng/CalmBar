import Combine
import Foundation
import SwiftUI
import CommandPaletteKit

public enum PinyinHelper {
    public static func toPinyin(_ text: String) -> (full: String, initials: String) {
        let mutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        let pinyin = (mutableString as String).lowercased()

        let full = pinyin.replacingOccurrences(of: " ", with: "")
        let words = pinyin.split(separator: " ")
        let initials = words.compactMap { $0.first }.map { String($0) }.joined()

        return (full, initials)
    }
}

@MainActor
public final class CommandCenter: ObservableObject {
    public static let shared = CommandCenter()

    @Published public private(set) var registeredCommands: [CommandDescriptor] = []

    public init() {
        registerBuiltInCommands()
        let featureManager = FeatureManager.shared
        featureManager.registerDefaultFeatures()
        registerFeatureCommands(from: featureManager)
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

    public func paletteResults(onActivate: ((CommandDescriptor) -> Void)? = nil) -> [PaletteResult] {
        registeredCommands.map { cmd in
            var searchTokens: [String] = [cmd.title]
            let pinyin = PinyinHelper.toPinyin(cmd.title)
            if !pinyin.full.isEmpty { searchTokens.append(pinyin.full) }
            if !pinyin.initials.isEmpty { searchTokens.append(pinyin.initials) }
            if let sub = cmd.subtitle, !sub.isEmpty { searchTokens.append(sub) }
            searchTokens.append(cmd.category.displayName)
            for alias in cmd.aliases {
                searchTokens.append(alias)
                let aliasPy = PinyinHelper.toPinyin(alias)
                if !aliasPy.full.isEmpty { searchTokens.append(aliasPy.full) }
                if !aliasPy.initials.isEmpty { searchTokens.append(aliasPy.initials) }
            }
            let richSearchText = searchTokens.joined(separator: " ")

            return PaletteResult(
                id: cmd.id,
                title: cmd.title,
                subtitle: cmd.subtitle,
                category: cmd.category.displayName,
                icon: Image(systemName: cmd.iconName),
                searchText: richSearchText,
                action: { [weak self] in
                    if let onActivate {
                        onActivate(cmd)
                    } else {
                        Task { @MainActor in
                            _ = await self?.execute(command: cmd)
                        }
                    }
                }
            )
        }
    }

    public func search(query: String) -> [CommandDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return registeredCommands
        }

        let tokens = trimmed.split(separator: " ").map { String($0) }
        var scoredCommands: [(cmd: CommandDescriptor, score: Int)] = []

        for cmd in registeredCommands {
            var totalScore = 0
            var allTokensMatched = true

            let titleLower = cmd.title.lowercased()
            let subLower = (cmd.subtitle ?? "").lowercased()
            let catLower = cmd.category.displayName.lowercased()

            let titlePinyin = PinyinHelper.toPinyin(cmd.title)

            for token in tokens {
                var tokenScore = 0
                let isASCII = token.allSatisfy { $0.isASCII }

                // --- 1. 中文 / 真实字符直接匹配 (权重最高) ---
                if titleLower == token {
                    tokenScore += 1000
                } else if titleLower.hasPrefix(token) {
                    tokenScore += 500
                } else if titleLower.contains(token) {
                    tokenScore += 200
                }

                if subLower.contains(token) {
                    tokenScore += 100
                }

                if catLower.contains(token) {
                    tokenScore += 50
                }

                // --- 2. 别名直接匹配 (中文/英文) ---
                for alias in cmd.aliases {
                    let aLower = alias.lowercased()
                    if aLower == token {
                        tokenScore += 300
                        break
                    } else if aLower.hasPrefix(token) {
                        tokenScore += 150
                        break
                    } else if aLower.contains(token) {
                        tokenScore += 80
                        break
                    }
                }

                // --- 3. 仅当输入为 ASCII (字母/数字) 时进行拼音匹配 ---
                if isASCII {
                    // 全拼前缀匹配 (如 shubiao, dakaipianhao)
                    if titlePinyin.full.hasPrefix(token) {
                        tokenScore += 250
                    } else if titlePinyin.full.contains(token) {
                        tokenScore += 100
                    }

                    // 首字母精准匹配 (如 sb 匹配 鼠标, fs 匹配 风扇, jtb 匹配 剪贴板)
                    if titlePinyin.initials == token {
                        tokenScore += 300
                    } else if titlePinyin.initials.hasPrefix(token) {
                        tokenScore += 180
                    }

                    // 别名拼音全拼/首字母匹配
                    for alias in cmd.aliases {
                        let aliasPinyin = PinyinHelper.toPinyin(alias)
                        if aliasPinyin.full == token || aliasPinyin.initials == token {
                            tokenScore += 200
                            break
                        } else if aliasPinyin.full.hasPrefix(token) || aliasPinyin.initials.hasPrefix(token) {
                            tokenScore += 120
                            break
                        }
                    }
                }

                if tokenScore == 0 {
                    allTokensMatched = false
                    break
                } else {
                    totalScore += tokenScore
                }
            }

            if allTokensMatched && totalScore > 0 {
                scoredCommands.append((cmd, totalScore))
            }
        }

        // 按得分从高到低严格排序
        scoredCommands.sort { $0.score > $1.score }
        return scoredCommands.map { $0.cmd }
    }

    public func registerFeatureCommands(from featureManager: FeatureManager = .shared) {
        for feature in featureManager.allFeatures() {
            let commandCategory: CommandCategory
            switch feature.category {
            case .system: commandCategory = .system
            case .hardware: commandCategory = .hardware
            case .productivity: commandCategory = .productivity
            case .input: commandCategory = .input
            case .security: commandCategory = .security
            case .cleanup: commandCategory = .cleanup
            }

            for fcmd in feature.commands {
                var perms: [PermissionType] = []
                if let p = fcmd.requiredPermission {
                    perms.append(p)
                }

                let descriptor = CommandDescriptor(
                    id: fcmd.id,
                    title: fcmd.title,
                    subtitle: fcmd.subtitle,
                    iconName: iconName(for: feature.id),
                    category: commandCategory,
                    featureID: feature.id,
                    requiredPermissions: perms,
                    aliases: defaultAliases(for: fcmd.id, featureID: feature.id),
                    run: {
                        fcmd.action()
                        return .success("已执行: \(fcmd.title)")
                    }
                )
                register(descriptor)
            }
        }
    }

    private func iconName(for featureID: FeatureID) -> String {
        switch featureID {
        case .thermal: return "flame.fill"
        case .battery: return "battery.100.bolt"
        case .caffeine: return "cup.and.saucer"
        case .clipboard: return "doc.on.clipboard"
        case .ocr: return "text.viewfinder"
        case .cleaner: return "trash"
        case .scroll: return "computermouse"
        case .noTunes: return "music.note"
        case .gatekeeper: return "lock.shield"
        case .menuBar: return "menubar.rectangle"
        }
    }

    private func defaultAliases(for commandID: String, featureID: FeatureID) -> [String] {
        var aliases: [String] = [featureID.rawValue]
        switch featureID {
        case .thermal:
            aliases.append(contentsOf: ["风扇", "温度", "降温", "温控", "散热", "cpu", "gpu", "fan", "thermal", "temp", "speed", "转速", "fs", "wk", "sr"])
        case .battery:
            aliases.append(contentsOf: ["电池", "充电", "80%", "100%", "充满", "电量", "旁路", "电源", "battery", "charge", "topup", "power", "dc", "cd", "cm"])
        case .caffeine:
            aliases.append(contentsOf: ["防休眠", "休眠", "常亮", "清醒", "防离开", "办公", "caffeine", "awake", "sleep", "keepalive", "fxm", "xm", "cl"])
        case .clipboard:
            aliases.append(contentsOf: ["剪贴板", "复制", "粘贴", "剪切板", "记录", "历史", "clipboard", "copy", "paste", "history", "jtb", "fz", "zt"])
        case .ocr:
            aliases.append(contentsOf: ["识字", "屏幕识字", "截图", "截屏", "文字识别", "二维码", "扫码", "ocr", "capture", "scan", "qrcode", "text", "sz", "jt", "jp", "wz", "sm"])
        case .cleaner:
            aliases.append(contentsOf: ["清理", "垃圾", "缓存", "开发缓存", "xcode", "卸载", "应用残留", "clean", "cache", "dev", "storage", "disk", "workspace", "ql", "lj", "hc", "xz"])
        case .scroll:
            aliases.append(contentsOf: ["鼠标", "滚轮", "鼠标滚轮", "自然滚动", "触控板", "滚动反转", "反转", "scroll", "mouse", "wheel", "reverser", "trackpad", "sb", "gl", "zr", "fz"])
        case .noTunes:
            aliases.append(contentsOf: ["音乐", "apple music", "拦截", "notunes", "music", "itunes", "block", "yy", "lj"])
        case .gatekeeper:
            aliases.append(contentsOf: ["隔离", "去隔离", "已损坏", "签名", "打不开", "修复", "gatekeeper", "quarantine", "sign", "fix", "repair", "gl", "qgl", "xf"])
        case .menuBar:
            aliases.append(contentsOf: ["菜单栏", "收纳", "折叠", "隐藏图标", "menubar", "hide", "fold", "collapse", "organizer", "cdl", "sn", "zd", "yc"])
        }

        if commandID.contains("settings") {
            aliases.append(contentsOf: ["设置", "偏好设置", "配置", "选项", "settings", "preferences", "config", "sz", "ph", "pz"])
        }
        if commandID.contains("permissions") {
            aliases.append(contentsOf: ["权限", "安全", "授权", "隐私", "permission", "security", "auth", "privacy", "qx", "aq", "sq"])
        }
        if commandID.contains("toggle") {
            aliases.append("toggle")
        }
        if commandID.contains("history") {
            aliases.append(contentsOf: ["history", "ls", "历史", "记录"])
        }
        if commandID.contains("scan") {
            aliases.append(contentsOf: ["scan", "clean", "扫描", "清理"])
        }
        return aliases
    }

    public func execute(command: CommandDescriptor) async -> CommandResult {
        // 1. Pre-flight permission check
        for perm in command.requiredPermissions {
            if !PermissionManager.shared.isGranted(perm) {
                return .permissionDenied(perm)
            }
        }

        // 2. Pre-flight feature state check
        if let fid = command.featureID, let feature = FeatureManager.shared.feature(id: fid) {
            switch feature.state {
            case .unavailable:
                return .failure("功能「\(feature.title)」在当前硬件或系统环境下不可用")
            case .failed(let message):
                return .failure("功能「\(feature.title)」异常: \(message)")
            case .needsPermission:
                return .failure("功能「\(feature.title)」缺少必需系统授权")
            case .disabled, .enabled, .running, .suspended, .degraded:
                break
            }
        }

        return await command.run()
    }

    public func registerBuiltInCommands() {
        // 1. Settings & Permissions
        register(CommandDescriptor(
            id: "system.settings",
            title: "打开偏好设置",
            subtitle: "配置 CalmBar 各模块偏好与高级选项",
            iconName: "gearshape",
            category: .general,
            aliases: ["settings", "preferences", "config", "设置", "偏好设置", "sz", "ph"],
            run: {
                StatusBarManager.shared.openSettingsWindow()
                return .success("已打开偏好设置")
            }
        ))

        register(CommandDescriptor(
            id: "system.permissions",
            title: "打开权限安全中心",
            subtitle: "查看与管理系统授权状态及功能受影响情况",
            iconName: "shield.lefthalf.filled",
            category: .general,
            aliases: ["permission", "security", "auth", "权限", "安全", "授权", "qx", "aq"],
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
            aliases: ["ocr", "sz", "capture", "shizi", "qrcode", "识字", "截图", "截屏", "扫码", "jt", "jp"],
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
            aliases: ["ocrhistory", "ls", "ocr历史", "识字历史", "ls"],
            run: {
                OCRHistoryWindowController.shared.show()
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
            aliases: ["clipboard", "jtb", "history", "剪贴板", "复制", "粘贴", "fz", "zt"],
            run: {
                ClipboardHistoryWindowController.shared.show()
                return .success("已打开剪贴板历史")
            }
        ))

        // 4. Caffeine
        register(CommandDescriptor(
            id: "caffeine.toggle",
            title: "切换防休眠状态",
            subtitle: "阻止系统和显示器进入休眠，保持系统常亮",
            iconName: "cup.and.saucer",
            category: .system,
            featureID: .caffeine,
            aliases: ["caffeine", "awake", "fxm", "xiuxian", "防休眠", "休眠", "常亮", "cl"],
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
            aliases: ["topup", "cm", "battery", "电池", "充电", "充满", "100%", "80%", "dc", "cd"],
            run: {
                BatteryChargeManager.shared.toggleTopUp()
                return .success("已切换临时充满模式")
            }
        ))

        // 6. Scroll
        register(CommandDescriptor(
            id: "scroll.toggle",
            title: "切换鼠标滚轮反转",
            subtitle: "独立反转外接鼠标与触控板方向，实现自然滚动",
            iconName: "computermouse",
            category: .input,
            featureID: .scroll,
            requiredPermissions: [.accessibility],
            aliases: ["scroll", "gl", "mouse", "鼠标", "滚轮", "自然滚动", "触控板", "sb", "zr"],
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
            aliases: ["menubar", "fold", "sn", "cdl", "菜单栏", "收纳", "折叠", "隐藏", "zd", "yc"],
            run: {
                MenuBarOrganizer.shared.toggleExpandCollapse()
                return .success("已切换菜单栏折叠")
            }
        ))

        // 8. Cleaner
        register(CommandDescriptor(
            id: "cleaner.scanDev",
            title: "扫描开发工具链缓存",
            subtitle: "扫描 Xcode、SPM、Node、Python 等开发缓存与工作区",
            iconName: "hammer",
            category: .cleanup,
            featureID: .cleaner,
            aliases: ["dev", "clean", "xcode", "npm", "cache", "开发缓存", "清理", "垃圾", "ql", "hc"],
            run: {
                CleanerManager.shared.refreshDevCaches()
                CleanerWindowController.shared.show()
                return .success("已打开清理中心并开始扫描开发缓存")
            }
        ))

        register(CommandDescriptor(
            id: "cleaner.scanApps",
            title: "扫描已安装应用",
            subtitle: "扫描应用程序及其 Library 残留缓存",
            iconName: "trash",
            category: .cleanup,
            featureID: .cleaner,
            aliases: ["app", "clean", "uninstall", "xz", "应用清理", "卸载残留", "yy"],
            run: {
                CleanerManager.shared.refreshAllApps()
                CleanerWindowController.shared.show()
                return .success("已打开清理中心并开始扫描应用程序")
            }
        ))

        // 9. Thermal
        register(CommandDescriptor(
            id: "thermal.restoreAuto",
            title: "恢复风扇自动控制",
            subtitle: "将散热策略重置为系统默认",
            iconName: "flame.fill",
            category: .hardware,
            featureID: .thermal,
            aliases: ["fan", "thermal", "fs", "auto", "风扇", "恢复风扇", "自动风扇", "降温"],
            run: {
                ThermalMonitor.shared.restoreSystemControl()
                AppSettings.shared.fanPreset = .auto
                return .success("已恢复风扇自动控制")
            }
        ))

        register(CommandDescriptor(
            id: "thermal.fanFull",
            title: "风扇全速运转",
            subtitle: "紧急降温：将风扇转速设为 100%",
            iconName: "flame.fill",
            category: .hardware,
            featureID: .thermal,
            requiredPermissions: [.privilegedHelper],
            aliases: ["fan", "thermal", "fs", "full", "全速", "满速", "风扇全速", "100%"],
            run: {
                AppSettings.shared.fanPreset = .manual
                AppSettings.shared.customFanFraction = 1.0
                return .success("风扇已设为全速运转")
            }
        ))
    }
}
