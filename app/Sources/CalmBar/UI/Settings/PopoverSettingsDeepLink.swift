import Combine
import SwiftUI

// MARK: - 偏好设置分组深链（UC-U05 / BR-23）

@MainActor
final class PopoverSettingsDeepLink: ObservableObject {
    static let shared = PopoverSettingsDeepLink()

    /// 待定位的分组；通用设置页滚动到锚点后清零
    @Published private(set) var pendingGroup: PopoverVisibilityGroup?

    private init() {}

    /// 打开偏好设置「通用设置」并定位到指定分组
    func open(_ group: PopoverVisibilityGroup) {
        pendingGroup = group
        StatusBarManager.shared.openSettingsWindow(tab: .general)
    }

    func consume() -> PopoverVisibilityGroup? {
        defer { pendingGroup = nil }
        return pendingGroup
    }
}
