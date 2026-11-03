import AppKit
import Foundation

// MARK: - 菜单栏读数组装（BR-24 / BR-25 / BR-26）

@MainActor
enum MenuBarReadout {
    static let maxWidth: CGFloat = 140

    /// 按「温度 > CPU > 内存 > 网络 > 磁盘」优先级组装，最多 3 项，超宽时从末位截断
    static func title(
        sample: MonitorSample?,
        temperature: Double,
        thermalEnabled: Bool,
        items: [String],
        monitorEnabled: Bool
    ) -> String {
        let ordered = AppSettings.menuBarReadoutOrder.filter { items.contains($0) }
        var parts: [String] = []

        for item in ordered.prefix(AppSettings.menuBarReadoutLimit) {
            guard let part = part(
                for: item,
                sample: sample,
                temperature: temperature,
                thermalEnabled: thermalEnabled,
                monitorEnabled: monitorEnabled
            ) else { continue }
            parts.append(part)
        }

        // BR-26：超过 140pt 时按优先级从低到高省略
        while parts.count > 1, measuredWidth(parts) > maxWidth {
            parts.removeLast()
        }

        guard !parts.isEmpty else { return "" }
        return " " + parts.joined(separator: "  ")
    }

    static func measuredWidth(_ parts: [String]) -> CGFloat {
        let text = " " + parts.joined(separator: "  ")
        let font = NSFont.systemFont(ofSize: 11)
        let size = (text as NSString).size(withAttributes: [.font: font])
        // 预留菜单栏图标与系统间距
        return size.width + 22
    }

    private static func part(
        for item: String,
        sample: MonitorSample?,
        temperature: Double,
        thermalEnabled: Bool,
        monitorEnabled: Bool
    ) -> String? {
        switch item {
        case "temperature":
            guard thermalEnabled, temperature > 0 else { return nil }
            return "\(Int(temperature.rounded()))°"
        case "cpu":
            guard monitorEnabled, let sample else { return nil }
            return "CPU \(Int((sample.cpuUsage * 100).rounded()))%"
        case "memory":
            guard monitorEnabled, let sample else { return nil }
            return "内存 \(Int((sample.memoryUsage * 100).rounded()))%"
        case "network":
            guard monitorEnabled, let sample else { return nil }
            return "↓ \(rate(sample.networkIn))"
        case "disk":
            guard monitorEnabled, let sample else { return nil }
            return "磁盘 \(Int((sample.diskUsage * 100).rounded()))%"
        default:
            return nil
        }
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.1fG/s", bytesPerSecond / 1_073_741_824)
        }
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.0fK/s", bytesPerSecond / 1024)
        }
        return "\(Int(bytesPerSecond))B/s"
    }
}
