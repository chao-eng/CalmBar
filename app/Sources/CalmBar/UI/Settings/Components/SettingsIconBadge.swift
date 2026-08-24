import SwiftUI

public struct SettingsIconBadge: View {
    public let icon: String
    public let gradientColors: [Color]
    public var size: CGFloat = 26
    public var cornerRadius: CGFloat = 6.5
    public var iconScale: CGFloat = 0.58

    public init(
        icon: String,
        gradientColors: [Color],
        size: CGFloat = 26,
        cornerRadius: CGFloat = 6.5,
        iconScale: CGFloat = 0.58
    ) {
        self.icon = icon
        self.gradientColors = gradientColors
        self.size = size
        self.cornerRadius = cornerRadius
        self.iconScale = iconScale
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: gradientColors.first?.opacity(0.25) ?? .clear, radius: 2, x: 0, y: 1)

            Image(systemName: icon)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
