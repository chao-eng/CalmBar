import Foundation
import SwiftUI

public enum SearchSensitivityLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case strict = "Strict"
    case balanced = "Balanced"
    case deep = "Deep"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .strict: return "严格 (最安全)"
        case .balanced: return "标准 (推荐)"
        case .deep: return "深度 (广域搜索)"
        }
    }
}

public enum AppSortOption: String, CaseIterable, Identifiable, Sendable {
    case name = "Name"
    case size = "Size"
    case dateModified = "Date Modified"
    case arch = "Architecture"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .name: return "应用名称"
        case .size: return "占用体积"
        case .dateModified: return "修改日期"
        case .arch: return "架构类型"
        }
    }
}

public enum AppArchitecture: String, CaseIterable, Sendable {
    case appleSilicon = "Apple Silicon"
    case intel = "Intel"
    case universal = "Universal"
    case unknown = "Unknown"

    public var badgeColor: Color {
        switch self {
        case .appleSilicon: return .purple
        case .intel: return .blue
        case .universal: return .green
        case .unknown: return .gray
        }
    }
}

public enum AssociatedFileType: String, CaseIterable, Identifiable, Sendable {
    case appBundle = "Application Bundle"
    case appSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case launchAgents = "Launch Agents / Daemons"
    case savedState = "Saved Application State"
    case logs = "Logs & Crash Reports"
    case webKit = "WebKit & HTTP Storages"
    case other = "Other Residuals"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .appBundle: return "应用程序本体"
        case .appSupport: return "应用支持 (App Support)"
        case .caches: return "应用缓存 (Caches)"
        case .preferences: return "偏好设置 (Preferences)"
        case .containers: return "沙盒容器 (Containers)"
        case .groupContainers: return "共享容器 (Group Containers)"
        case .launchAgents: return "自启服务 (LaunchAgents)"
        case .savedState: return "恢复状态 (Saved State)"
        case .logs: return "日志与崩溃报告 (Logs)"
        case .webKit: return "网络与存储 (WebKit/HTTP)"
        case .other: return "其他相关项"
        }
    }

    public var iconName: String {
        switch self {
        case .appBundle: return "app.badge.fill"
        case .appSupport: return "folder.fill.badge.gearshape"
        case .caches: return "archivebox.fill"
        case .preferences: return "slider.horizontal.3"
        case .containers: return "shippingbox.fill"
        case .groupContainers: return "square.stack.3d.up.fill"
        case .launchAgents: return "bolt.shield.fill"
        case .savedState: return "clock.arrow.circlepath"
        case .logs: return "doc.plaintext.fill"
        case .webKit: return "globe"
        case .other: return "folder.fill"
        }
    }
}
