import SwiftUI
import CalmBarKit

public struct TemperatureGaugeView: View {
    public let title: String
    public let temp: Float
    public let icon: String
    public let color: Color

    public init(title: String, temp: Float, icon: String, color: Color = .orange) {
        self.title = title
        self.temp = temp
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(temp))")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("°")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

public struct FanRPMGaugeView: View {
    public let fan: FanSnapshot
    public let title: String

    public init(fan: FanSnapshot, title: String = "风扇") {
        self.fan = fan
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(formattedRPM(Int(fan.actualRPM)))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("RPM")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func formattedRPM(_ rpm: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rpm)) ?? "\(rpm)"
    }
}

public struct CardSection<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(4)
        }
    }
}
