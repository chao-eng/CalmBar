import SwiftUI

public struct AppItemRowView: View {
    public let app: CleanableApp
    public let isSelected: Bool

    public var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if app.isRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .help("应用正在运行")
                    }
                }

                HStack(spacing: 6) {
                    Text("v\(app.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(app.architecture.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(app.architecture.badgeColor.opacity(0.15))
                        .foregroundStyle(app.architecture.badgeColor)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Text(app.formattedBundleSize)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
