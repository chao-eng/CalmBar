import SwiftUI

public struct SettingsHeaderView: View {
    public let tab: SettingsTab

    public init(tab: SettingsTab) {
        self.tab = tab
    }

    public var body: some View {
        VStack(spacing: 8) {
            SettingsIconBadge(
                icon: tab.icon,
                gradientColors: tab.gradientColors,
                size: 52,
                cornerRadius: 13,
                iconScale: 0.52
            )

            Text(tab.titleZH)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)

            Text(tab.subtitleZH)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}
