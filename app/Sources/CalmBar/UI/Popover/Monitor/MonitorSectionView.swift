import SwiftUI

// MARK: - 监控分区（真实快照 / 趋势 / 告警降级提示）

struct MonitorSectionView: View {
    var onMeasure: ((CGFloat) -> Void)?
    var onAction: ((String) -> Void)?

    @ObservedObject private var monitor = SystemMonitorService.shared
    @ObservedObject private var alerts = MonitorAlertEngine.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: PopoverLayout.blockGap) {
            HStack(spacing: 8) {
                ForEach(metrics) { metric in
                    metricCard(metric)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("监控指标")

            trendCard

            if let degraded = alerts.degradedAlert {
                degradedBanner(degraded)
            }

            Button {
                onAction?("alert-settings")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 11))
                    Text("告警设置")
                        .font(.system(size: 10, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("告警设置")
            .accessibilityValue("按钮")
        }
        .frame(width: PopoverLayout.contentWidth, alignment: .top)
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { onMeasure?(proxy.size.height) }
            }
        }
    }

    // MARK: 指标卡

    private struct MetricCardModel: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        let tint: Color
    }

    private var metrics: [MetricCardModel] {
        let sample = monitor.snapshot
        return [
            MetricCardModel(
                id: "cpu",
                icon: "cpu",
                title: "CPU",
                value: sample.map { "\(Int(($0.cpuUsage * 100).rounded()))%" } ?? "—",
                tint: .primary
            ),
            MetricCardModel(
                id: "memory",
                icon: "memorychip",
                title: "内存",
                value: sample.map { "\(Int(($0.memoryUsage * 100).rounded()))%" } ?? "—",
                tint: memoryTint(sample?.memoryPressure)
            ),
            MetricCardModel(
                id: "network",
                icon: "network",
                title: "网络",
                value: sample.map { Self.rate($0.networkIn) } ?? "—",
                tint: .primary
            )
        ]
    }

    private func memoryTint(_ pressure: MemoryPressureLevel?) -> Color {
        switch pressure {
        case .critical: .red
        case .warning: .orange
        default: .primary
        }
    }

    private func metricCard(_ metric: MetricCardModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: metric.icon)
                    .font(.system(size: 9))
                Text(metric.title)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)

            Text(metric.value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(metric.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title) \(metric.value)")
    }

    // MARK: 趋势

    private var trendRange: MonitorRange {
        MonitorRange(rawValue: settings.systemMonitorHistoryWindow) ?? .minute1
    }

    private var trendCard: some View {
        let range = trendRange
        let samples = monitor.samples(in: range)
        let values = samples.map(\.cpuUsage)
        let current = values.last ?? 0
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("近 \(range.titleZH) · CPU")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(trendStatusText)
                    .font(.system(size: 9))
                    .foregroundStyle(monitor.isStale ? .orange : .secondary)
            }
            if values.count >= 2 {
                SparklineView(values: values)
                    .frame(height: 52)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("积累中 · 至少需要 2 个采样点")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(width: PopoverLayout.contentWidth, height: 76)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(values.count >= 2
            ? "近 \(range.titleZH) CPU 趋势，当前 \(Int((current * 100).rounded()))%，平均 \(Int((average * 100).rounded()))%"
            : "近 \(range.titleZH) CPU 趋势积累中")
    }

    private var trendStatusText: String {
        if monitor.isStale { return "数据延迟" }
        guard let sample = monitor.snapshot else { return "采样中" }
        return Self.timeFormatter.string(from: sample.timestamp)
    }

    // MARK: 告警降级胶囊

    private func degradedBanner(_ event: MonitorAlertEvent) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "bell.slash")
                .font(.system(size: 9))
            Text("通知不可用 · \(compactText(event))")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                alerts.dismissDegradedAlert()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("忽略告警提示")
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onAction?("alert-settings")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("通知权限不可用，\(compactText(event))")
    }

    private func compactText(_ event: MonitorAlertEvent) -> String {
        switch event.type {
        case .cpu: "CPU \(Int(event.currentValue.rounded()))%"
        case .memory: "内存压力\(event.currentValue >= 2 ? "告急" : "偏高")"
        case .disk: "磁盘仅剩 \(String(format: "%.1f", event.currentValue))GB"
        case .battery: "电量 \(Int(event.currentValue.rounded()))%"
        case .temperature: "温度 \(Int(event.currentValue.rounded()))°C"
        }
    }

    // MARK: 格式化

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "↓%.1fM/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1024 {
            return String(format: "↓%.0fK/s", bytesPerSecond / 1024)
        }
        return "↓\(Int(bytesPerSecond))B/s"
    }
}

// MARK: - 真实历史折线

private struct SparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let step = width / CGFloat(max(1, values.count - 1))

            ZStack(alignment: .bottomLeading) {
                areaPath(width: width, height: height)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.39, green: 0.82, blue: 1).opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                linePath(height: height, step: step)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0.39, green: 0.82, blue: 1), Color(red: 0.04, green: 0.52, blue: 1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func point(index: Int, step: CGFloat, height: CGFloat) -> CGPoint {
        let value = min(1, max(0, values[index]))
        return CGPoint(x: CGFloat(index) * step, y: height * (1 - value))
    }

    private func linePath(height: CGFloat, step: CGFloat) -> Path {
        Path { path in
            for index in values.indices {
                let point = point(index: index, step: step, height: height)
                if index == values.startIndex {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func areaPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height))
            for index in values.indices {
                path.addLine(to: point(index: index, step: width / CGFloat(max(1, values.count - 1)), height: height))
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
    }
}
