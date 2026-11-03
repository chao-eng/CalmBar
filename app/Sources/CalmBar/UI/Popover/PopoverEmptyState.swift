import SwiftUI

// MARK: - 统一空状态（PRD §5.9 / BR-09）

struct PopoverEmptyState: View {
    private let icon: String
    private let title: String
    private let detail: String
    private let accessibilityValue: String
    private let actionTitle: String?
    private let deepLinkGroup: PopoverVisibilityGroup?
    private let onAction: (() -> Void)?

    /// 可勾选分区：文案取自分组真源，按钮默认打开通用设置
    init(group: PopoverVisibilityGroup, onOpenSettings: (() -> Void)? = nil) {
        self.icon = group.emptyIcon
        self.title = group.emptyTitle
        self.detail = group.emptyDetail
        self.accessibilityValue = group.title
        self.actionTitle = "去勾选"
        self.deepLinkGroup = group
        self.onAction = onOpenSettings
    }

    /// 预留分区：只读空状态，无操作按钮
    init(icon: String, title: String, detail: String, accessibilityValue: String) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.accessibilityValue = accessibilityValue
        self.actionTitle = nil
        self.deepLinkGroup = nil
        self.onAction = nil
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)

            if let actionTitle {
                Button(actionTitle) {
                    if let onAction {
                        onAction()
                    } else if let deepLinkGroup {
                        PopoverSettingsDeepLink.shared.open(deepLinkGroup)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
                .help(deepLinkGroup.map { "打开偏好设置，定位到「\($0.settingsTitle)」分组" } ?? "")
                .accessibilityLabel(actionTitle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("分区空状态")
        .accessibilityValue(accessibilityValue)
    }
}
