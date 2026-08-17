import SwiftUI
import AppKit

public enum AppIcons {
    /// 加载 noTunes 官方应用图标
    public static var noTunesAppIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "noTunesIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 开发调试环境相对路径支持
        let relativePaths = [
            "Resources/noTunesIcon.png",
            "app/Resources/noTunesIcon.png",
            "../Resources/noTunesIcon.png"
        ]
        for path in relativePaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return NSImage(named: "noTunesIcon")
    }

    /// 加载 noTunes 状态栏/矢量模板图标
    public static var noTunesStatusIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "noTunesStatusIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        let relativePaths = [
            "Resources/noTunesStatusIcon.png",
            "app/Resources/noTunesStatusIcon.png",
            "../Resources/noTunesStatusIcon.png"
        ]
        for path in relativePaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                img.isTemplate = true
                return img
            }
        }
        return NSImage(named: "noTunesStatusIcon")
    }
}

public struct NoTunesIconView: View {
    public var size: CGFloat = 20
    public var isStatusTemplate: Bool = false

    public init(size: CGFloat = 20, isStatusTemplate: Bool = false) {
        self.size = size
        self.isStatusTemplate = isStatusTemplate
    }

    public var body: some View {
        if isStatusTemplate, let templateImg = AppIcons.noTunesStatusIcon {
            Image(nsImage: templateImg)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let appImg = AppIcons.noTunesAppIcon {
            Image(nsImage: appImg)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 0.5)
        } else {
            // 原生精美矢量回退绘制：粉红色圆角矩形 + 音符 + 斜杠
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.98, green: 0.36, blue: 0.52), Color(red: 0.88, green: 0.18, blue: 0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Image(systemName: "music.note")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundColor(.white)

                // 禁止斜杠
                Rectangle()
                    .fill(Color.white)
                    .frame(width: size * 0.75, height: 1.5)
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: size, height: size)
        }
    }
}

public struct GatekeeperIconView: View {
    public var size: CGFloat = 20

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.16, green: 0.52, blue: 0.98), Color(red: 0.05, green: 0.75, blue: 0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 0.5)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

public struct CaffeineIconView: View {
    public var size: CGFloat = 20
    public var isActive: Bool = true

    public init(size: CGFloat = 20, isActive: Bool = true) {
        self.size = size
        self.isActive = isActive
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(isActive ? LinearGradient(
                    colors: [Color(red: 0.62, green: 0.44, blue: 0.32), Color(red: 0.48, green: 0.30, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) : LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.10), radius: 1, x: 0, y: 0.5)

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size * 0.50, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

public struct BatteryIconView: View {
    public var size: CGFloat = 20
    public var isCharging: Bool = false
    public var isBypassed: Bool = false
    public var isDischarging: Bool = false

    public init(size: CGFloat = 20, isCharging: Bool = false, isBypassed: Bool = false, isDischarging: Bool = false) {
        self.size = size
        self.isCharging = isCharging
        self.isBypassed = isBypassed
        self.isDischarging = isDischarging
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(isDischarging ? LinearGradient(
                    colors: [Color(red: 0.78, green: 0.45, blue: 0.20), Color(red: 0.62, green: 0.32, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) : isBypassed ? LinearGradient(
                    colors: [Color(red: 0.16, green: 0.50, blue: 0.72), Color(red: 0.10, green: 0.38, blue: 0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) : isCharging ? LinearGradient(
                    colors: [Color(red: 0.18, green: 0.52, blue: 0.90), Color(red: 0.10, green: 0.40, blue: 0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) : LinearGradient(
                    colors: [Color(red: 0.25, green: 0.48, blue: 0.68), Color(red: 0.18, green: 0.38, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: Color.black.opacity(0.10), radius: 1, x: 0, y: 0.5)

            Image(systemName: isDischarging ? "arrow.down.to.line.compact" : (isBypassed ? "powerplug.fill" : (isCharging ? "bolt.fill" : "battery.100")))
                .font(.system(size: size * 0.50, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}


