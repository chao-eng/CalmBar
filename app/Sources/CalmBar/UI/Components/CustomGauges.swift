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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text("\(Int(temp))°")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: temp)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(formattedRPM(Int(fan.actualRPM)))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: fan.actualRPM)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
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
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
