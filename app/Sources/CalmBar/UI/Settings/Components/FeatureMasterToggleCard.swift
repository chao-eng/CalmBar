import SwiftUI

public struct FeatureMasterToggleCard: View {
    public let icon: String
    public let iconColors: [Color]
    public let title: String
    public let activeSubtitle: String
    public let inactiveSubtitle: String
    @Binding public var isEnabled: Bool

    public init(
        icon: String,
        iconColors: [Color],
        title: String,
        activeSubtitle: String,
        inactiveSubtitle: String,
        isEnabled: Binding<Bool>
    ) {
        self.icon = icon
        self.iconColors = iconColors
        self.title = title
        self.activeSubtitle = activeSubtitle
        self.inactiveSubtitle = inactiveSubtitle
        self._isEnabled = isEnabled
    }

    public var body: some View {
        HStack(spacing: 14) {
            SettingsIconBadge(
                icon: icon,
                gradientColors: isEnabled ? iconColors : [Color.gray.opacity(0.7), Color.gray.opacity(0.5)],
                size: 36,
                cornerRadius: 9,
                iconScale: 0.54
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(isEnabled ? "运行中" : "已停用")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(isEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                        .foregroundStyle(isEnabled ? .green : .secondary)
                        .cornerRadius(4)
                }

                Text(isEnabled ? activeSubtitle : inactiveSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
