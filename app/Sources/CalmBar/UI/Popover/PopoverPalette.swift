import SwiftUI

// MARK: - 面板色彩令牌（墨水层保持黑灰中性，彩色仅落在图标/数值/图表/徽章）
// 强调色为双值自适应：浅色模式用加深版保证与浅背景对比度，深色模式用系统亮色

enum PopoverPalette {
    // MARK: 自适应强调色

    /// 浅色/深色双值自适应色
    private static func adaptive(lightMode: UInt32, darkMode: UInt32) -> Color {
        let nsColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark
            ]) != nil
            return srgb(isDark ? darkMode : lightMode)
        }
        return Color(nsColor: nsColor)
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    // 基础色板：浅色加深（约 4.5:1 白底对比度）/ 深色用系统亮色
    static let accentBlue = adaptive(lightMode: 0x0058BE, darkMode: 0x0A84FF)
    static let accentOrange = adaptive(lightMode: 0xB85A00, darkMode: 0xFF9F0A)
    static let accentGreen = adaptive(lightMode: 0x1A7A3C, darkMode: 0x30D158)
    static let accentPink = adaptive(lightMode: 0xC72B58, darkMode: 0xFF375F)
    static let accentPurple = adaptive(lightMode: 0x8340C0, darkMode: 0xBF5AF2)
    static let accentTeal = adaptive(lightMode: 0x0C7484, darkMode: 0x40C8E0)
    static let accentIndigo = adaptive(lightMode: 0x4543AE, darkMode: 0x5E5CE6)
    static let accentRed = adaptive(lightMode: 0xCE0010, darkMode: 0xFF453A)
    static let accentBrown = adaptive(lightMode: 0x8F5B3A, darkMode: 0xC08A5C)   // 防休眠咖啡棕（与面板咖啡杯图标同源）

    /// 设置页图标徽章渐变（主色 → 加深 22%），色相与面板图标保持一致
    static func badgeGradient(_ base: Color) -> [Color] {
        guard let rgb = NSColor(base).usingColorSpace(.sRGB) else { return [base, base] }
        let shaded = NSColor(
            srgbRed: rgb.redComponent * 0.78,
            green: rgb.greenComponent * 0.78,
            blue: rgb.blueComponent * 0.78,
            alpha: 1
        )
        return [base, Color(nsColor: shaded)]
    }

    // MARK: 分区主题色（Tab 图标 / 分区内强调色）

    static let thermalAccent: Color = accentOrange      // 温控：温度橙
    static let guardianAccent: Color = accentBlue       // 守护：防护蓝
    static let toolsAccent: Color = accentPurple        // 工具：工具紫
    static let monitorAccent: Color = accentGreen       // 监控：健康绿
    static let audioAccent: Color = accentPink          // 声音：声波粉
    static let gatewayAccent: Color = accentTeal        // 网关：链路青

    /// 网关速率折线系列色（蓝 / 绿 / 金 / 紫，同令牌体系自适应）
    static let gatewaySeriesColors: [Color] = [
        accentBlue,
        accentGreen,
        adaptive(lightMode: 0x9A6A00, darkMode: 0xFFD60A),
        accentPurple
    ]

    // MARK: 监控指标色

    static func metricColor(_ id: String) -> Color {
        switch id {
        case "cpu": accentBlue
        case "memory": accentPurple
        case "network": accentGreen
        case "disk": accentOrange
        default: accentBlue
        }
    }

    // MARK: 状态语义色

    static let statusSuccess: Color = accentGreen       // 正常运行
    static let statusWarning: Color = accentOrange      // 需要注意
    static let statusCritical: Color = accentRed        // 异常/告警

    /// 温度冷暖色：低温蓝 → 暖温橙 → 高温红
    static func tempColor(_ temp: Double) -> Color {
        switch temp {
        case ..<60: accentBlue
        case ..<80: accentOrange
        default: accentRed
        }
    }

    private static var increasedContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    // MARK: 面层（背景填充）

    /// 卡片底：指标卡 / 工具格 / 横幅卡
    static var surfaceCard: Color {
        Color.primary.opacity(increasedContrast ? 0.08 : 0.04)
    }

    /// 卡片悬停底：工具格 hover
    static var surfaceCardHover: Color {
        Color.primary.opacity(increasedContrast ? 0.14 : 0.08)
    }

    /// 内嵌块底：音频行内小块 / 设备按钮 / 温控守护横幅 / 常态徽章
    static var surfaceWell: Color {
        Color.primary.opacity(increasedContrast ? 0.10 : 0.06)
    }

    /// 分区栏容器轨道底
    static var surfaceBarTrack: Color {
        Color.primary.opacity(increasedContrast ? 0.10 : 0.05)
    }

    /// 选中胶囊底
    static var surfaceSelected: Color {
        Color.primary.opacity(increasedContrast ? 0.18 : 0.10)
    }

    /// 告警徽章底（与选中态拉开差距，保证告警语义醒目）
    static var surfaceAlert: Color {
        Color.primary.opacity(increasedContrast ? 0.32 : 0.18)
    }

    // MARK: 线面（描边）

    /// 细描边：卡片 hairline
    static var separatorHairline: Color {
        Color.primary.opacity(increasedContrast ? 0.20 : 0.05)
    }

    /// 强调描边：悬停描边 / 面板外框
    static var separatorEmphasized: Color {
        Color.primary.opacity(increasedContrast ? 0.32 : 0.12)
    }

    // MARK: 数据面（图表 / 进度）

    /// 进度条轨道 / 折线面积
    static var barTrack: Color {
        Color.primary.opacity(increasedContrast ? 0.16 : 0.10)
    }

    /// 进度条填充
    static var barFill: Color {
        Color.primary.opacity(increasedContrast ? 0.80 : 0.55)
    }

    /// 迷你柱状图常态柱
    static var sparkDim: Color {
        Color.primary.opacity(increasedContrast ? 0.55 : 0.35)
    }

    /// 迷你柱状图当前柱 / 折线主线
    static var sparkLive: Color {
        Color.primary.opacity(increasedContrast ? 0.95 : 0.70)
    }

    // MARK: 点缀

    /// 状态指示点（头部徽章圆点）
    static var statusDot: Color {
        Color.secondary.opacity(increasedContrast ? 0.9 : 0.6)
    }
}
