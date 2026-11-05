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
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    metricCard(metrics[0])
                    metricCard(metrics[1])
                }
                HStack(spacing: 8) {
                    metricCard(metrics[2])
                    metricCard(metrics[3])
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
                        .foregroundStyle(PopoverPalette.statusWarning)
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
                        .fill(PopoverPalette.surfaceCard)
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

    private enum BadgeTone {
        case quiet
        case normal
        case alert
    }

    private struct MetricBadge {
        let text: String
        let tone: BadgeTone
    }

    private enum Accessory {
        case sparkline([Double])
        case progress(Double)
    }

    private struct MetricCardModel: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        let unit: String
        let badge: MetricBadge
        let accessory: Accessory
        let footnote: String
    }

    private var trendRange: MonitorRange {
        MonitorRange(rawValue: settings.systemMonitorHistoryWindow) ?? .minute1
    }

    private var metrics: [MetricCardModel] {
        let range = trendRange
        let samples = monitor.samples(in: range)
        let cpuHistory = Array(samples.map(\.cpuUsage).suffix(16))
        let networkHistory = Array(samples.map(\.networkIn).suffix(16))
        let sample = monitor.snapshot

        let cpu = sample?.cpuUsage ?? 0
        let cpuAverage = cpuHistory.isEmpty ? 0 : cpuHistory.reduce(0, +) / Double(cpuHistory.count)
        let cpuPeak = cpuHistory.max() ?? 0
        let cpuParts = (Self.percent(cpu), "%")

        var memoryValue = "—"
        var memoryUnit = ""
        var memoryBadge = MetricBadge(text: "采样中", tone: .quiet)
        var memoryFootnote = "等待首个采样"
        var memoryRatio = 0.0
        if let sample {
            memoryValue = Self.percent(sample.memoryUsage)
            memoryUnit = "%"
            memoryRatio = sample.memoryUsage
            memoryBadge = Self.memoryBadge(sample.memoryPressure)
            memoryFootnote = "已用 \(Self.gibibytes(sample.memoryUsed)) / \(Self.gibibytes(sample.memoryTotal)) GB"
        }

        let networkParts = sample.map { Self.rateParts($0.networkIn) } ?? ("—", "")
        let networkFootnote = sample.map { "上行 \(Self.shortRate($0.networkOut))" } ?? "等待首个采样"

        var diskValue = "—"
        var diskUnit = ""
        var diskBadge = MetricBadge(text: "采样中", tone: .quiet)
        var diskFootnote = "等待首个采样"
        var diskRatio = 0.0
        if let sample {
            diskValue = Self.percent(sample.diskUsage)
            diskUnit = "%"
            diskRatio = sample.diskUsage
            diskBadge = Self.diskBadge(sample.diskUsage)
            diskFootnote = "可用 \(Self.gigabytes(sample.diskFree)) GB"
        }

        return [
            MetricCardModel(
                id: "cpu",
                icon: "cpu",
                title: "CPU",
                value: cpuParts.0,
                unit: cpuParts.1,
                badge: Self.cpuBadge(cpu),
                accessory: .sparkline(cpuHistory),
                footnote: "均 \(Self.percent(cpuAverage))% · 峰 \(Self.percent(cpuPeak))%"
            ),
            MetricCardModel(
                id: "memory",
                icon: "memorychip",
                title: "内存",
                value: memoryValue,
                unit: memoryUnit,
                badge: memoryBadge,
                accessory: .progress(memoryRatio),
                footnote: memoryFootnote
            ),
            MetricCardModel(
                id: "network",
                icon: "network",
                title: "网络",
                value: networkParts.0,
                unit: networkParts.1,
                badge: Self.networkBadge(sample?.networkIn ?? 0),
                accessory: .sparkline(networkHistory),
                footnote: networkFootnote
            ),
            MetricCardModel(
                id: "disk",
                icon: "internaldrive",
                title: "磁盘",
                value: diskValue,
                unit: diskUnit,
                badge: diskBadge,
                accessory: .progress(diskRatio),
                footnote: diskFootnote
            )
        ]
    }

    private func metricCard(_ metric: MetricCardModel) -> some View {
        let accent = PopoverPalette.metricColor(metric.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: metric.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(accent)
                Text(metric.title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                badgeView(metric.badge, accent: accent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(metric.unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            accessoryView(metric.accessory, accent: accent)
                .frame(height: 14)

            Text(metric.footnote)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 96)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PopoverPalette.surfaceCard)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title) \(metric.value)\(metric.unit)，\(metric.badge.text)，\(metric.footnote)")
    }

    private func badgeView(_ badge: MetricBadge, accent: Color) -> some View {
        HStack(spacing: 2) {
            if badge.tone == .alert {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 7, weight: .bold))
            }
            Text(badge.text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(badgeForeground(badge.tone, accent: accent))
        .padding(.horizontal, 5)
        .frame(height: 14)
        .background {
            Capsule(style: .continuous)
                .fill(badgeToneFill(badge.tone, accent: accent))
        }
    }

    private func badgeForeground(_ tone: BadgeTone, accent: Color) -> Color {
        switch tone {
        case .quiet: .secondary
        case .normal: accent
        case .alert: PopoverPalette.statusCritical
        }
    }

    private func badgeToneFill(_ tone: BadgeTone, accent: Color) -> Color {
        switch tone {
        case .quiet: .clear
        case .normal: accent.opacity(0.12)
        case .alert: PopoverPalette.statusCritical.opacity(0.14)
        }
    }

    @ViewBuilder
    private func accessoryView(_ accessory: Accessory, accent: Color) -> some View {
        switch accessory {
        case .sparkline(let values):
            MiniBarSparklineView(values: values, tint: accent)
        case .progress(let ratio):
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RatioBar(ratio: ratio, tint: accent)
                    .frame(height: 4)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 状态阈值

    private static func cpuBadge(_ usage: Double) -> MetricBadge {
        if usage < 0.4 {
            MetricBadge(text: "空闲", tone: .quiet)
        } else if usage < 0.8 {
            MetricBadge(text: "正常", tone: .normal)
        } else {
            MetricBadge(text: "繁忙", tone: .alert)
        }
    }

    private static func memoryBadge(_ pressure: MemoryPressureLevel) -> MetricBadge {
        switch pressure {
        case .normal: MetricBadge(text: "正常", tone: .quiet)
        case .warning: MetricBadge(text: "偏高", tone: .normal)
        case .critical: MetricBadge(text: "告急", tone: .alert)
        }
    }

    private static func diskBadge(_ usage: Double) -> MetricBadge {
        if usage < 0.7 {
            MetricBadge(text: "充足", tone: .quiet)
        } else if usage < 0.85 {
            MetricBadge(text: "正常", tone: .normal)
        } else {
            MetricBadge(text: "不足", tone: .alert)
        }
    }

    private static func networkBadge(_ bytesPerSecond: Double) -> MetricBadge {
        if bytesPerSecond < 512 * 1024 {
            MetricBadge(text: "空闲", tone: .quiet)
        } else if bytesPerSecond < 8 * 1024 * 1024 {
            MetricBadge(text: "正常", tone: .normal)
        } else {
            MetricBadge(text: "繁忙", tone: .alert)
        }
    }

    // MARK: 趋势

    private var trendCard: some View {
        let range = trendRange
        let samples = monitor.samples(in: range)
        let values = samples.map(\.cpuUsage)
        let current = values.last ?? 0
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let peak = values.max() ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("近 \(range.titleZH) · CPU")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(trendSummaryText(values: values, average: average, peak: peak))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if values.count >= 2 {
                SparklineView(values: values, tint: PopoverPalette.metricColor("cpu"))
                    .frame(height: 52)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.secondary)
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
                .fill(PopoverPalette.surfaceCard)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(values.count >= 2
            ? "近 \(range.titleZH) CPU 趋势，当前 \(Self.percent(current))%，平均 \(Self.percent(average))%，峰值 \(Self.percent(peak))%"
            : "近 \(range.titleZH) CPU 趋势积累中")
    }

    private func trendSummaryText(values: [Double], average: Double, peak: Double) -> String {
        if monitor.isStale { return "数据延迟" }
        guard values.count >= 2 else { return "采样中" }
        return "均 \(Self.percent(average))% · 峰 \(Self.percent(peak))%"
    }

    // MARK: 告警降级胶囊

    private func degradedBanner(_ event: MonitorAlertEvent) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "bell.slash")
                .font(.system(size: 9))
                .foregroundStyle(PopoverPalette.statusCritical)
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
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PopoverPalette.surfaceWell)
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

    private static func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))"
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        // 十进制 GB，与系统设置 / 访达的容量显示单位一致
        String(format: "%.1f", Double(bytes) / 1_000_000_000)
    }

    private static func gibibytes(_ bytes: UInt64) -> String {
        // 二进制 GiB，与活动监视器的内存口径一致：16 GiB 显示为 16.0 GB
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    private static func rateParts(_ bytesPerSecond: Double) -> (String, String) {
        if bytesPerSecond >= 1_048_576 {
            return (String(format: "%.1f", bytesPerSecond / 1_048_576), "M/s")
        }
        if bytesPerSecond >= 1024 {
            return (String(format: "%.0f", bytesPerSecond / 1024), "K/s")
        }
        return ("\(Int(bytesPerSecond))", "B/s")
    }

    private static func shortRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.0fK/s", bytesPerSecond / 1024)
        }
        return "\(Int(bytesPerSecond))B/s"
    }
}

// MARK: - 卡内迷你柱状走势

private struct MiniBarSparklineView: View {
    let values: [Double]
    var tint: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            let count = values.count
            let spacing: CGFloat = 1.5
            let available = proxy.size.width - spacing * CGFloat(max(0, count - 1))
            let barWidth = max(1, available / CGFloat(max(1, count)))
            let peak = max(values.max() ?? 0, 0.001)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    UnevenRoundedRectangle(
                        topLeadingRadius: 1,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 1
                    )
                        .fill(index == count - 1 ? tint : tint.opacity(0.4))
                        .frame(
                            width: barWidth,
                            height: max(1.5, proxy.size.height * CGFloat(min(1, value / peak)))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 比率进度条

private struct RatioBar: View {
    let ratio: Double
    var tint: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(PopoverPalette.barTrack)
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.75))
                    .frame(width: max(2, proxy.size.width * CGFloat(min(1, max(0, ratio)))))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 真实历史折线

private struct SparklineView: View {
    let values: [Double]
    var tint: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let step = width / CGFloat(max(1, values.count - 1))

            ZStack(alignment: .bottomLeading) {
                areaPath(width: width, height: height)
                    .fill(tint.opacity(0.10))
                linePath(height: height, step: step)
                    .stroke(
                        tint.opacity(0.85),
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
