import Charts
import SwiftUI

// MARK: - 网关分区（FR-07：状态行 + Output TPS 速率折线图）

struct GatewaySectionView: View {
    let viewportHeight: CGFloat
    var onOpenSettings: () -> Void
    var onOpenHistory: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var service = GatewayService.shared

    @State private var series: GatewaySeriesResult = .empty
    @State private var hoverDate: Date?

    private var granularity: GatewayGranularity {
        settings.aiGatewayGranularity
    }

    var body: some View {
        Group {
            if settings.aiGatewayEnabled {
                enabledContent
            } else {
                guideCard
            }
        }
        .frame(width: PopoverLayout.contentWidth, alignment: .top)
        .task(id: granularity) {
            await reload()
        }
        .onChange(of: service.revision) { _, _ in
            Task { await reload() }
        }
        .onChange(of: settings.aiGatewayEnabled) { _, enabled in
            if enabled {
                Task { await reload() }
            }
        }
    }

    // MARK: 已启用

    private var enabledContent: some View {
        VStack(spacing: 8) {
            statusRow

            if case .failed(let reason) = service.status {
                errorBanner(reason)
            }

            chartCard
                .frame(maxHeight: .infinity)
        }
        .frame(height: viewportHeight, alignment: .top)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)

            Text(verbatim: "127.0.0.1:\(settings.aiGatewayPort)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: onOpenHistory) {
                HStack(spacing: 2) {
                    Text("历史")
                        .font(.system(size: 9))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看完整请求历史")
            .accessibilityLabel("查看完整请求历史")

            Toggle("", isOn: $settings.aiGatewayEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("启用或停用本地 AI 网关")
                .accessibilityLabel("AI 网关总开关")
        }
        .frame(height: 18)
    }

    private var statusText: String {
        // 运行中状态由下方地址行展示端口，这里只显示状态词，避免端口重复
        if case .running = service.status { return "运行中" }
        return service.status.title
    }

    private var statusTint: Color {
        switch service.status {
        case .running: PopoverPalette.statusSuccess
        case .failed: PopoverPalette.statusCritical
        case .starting: PopoverPalette.statusWarning
        case .stopped: PopoverPalette.statusDot
        }
    }

    private func errorBanner(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(PopoverPalette.statusCritical)
            Text(reason)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(PopoverPalette.surfaceAlert)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("网关错误：\(reason)")
    }

    // MARK: 折线图卡

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            chartHeader

            if !series.series.isEmpty {
                legendRow
            }

            if series.points.isEmpty {
                emptyChartState
            } else {
                chart
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PopoverPalette.surfaceCard)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PopoverPalette.separatorHairline, lineWidth: 0.5)
        }
    }

    private var chartHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text("模型速度趋势（近\(granularity.durationTitle)）")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Picker("", selection: $settings.aiGatewayGranularity) {
                ForEach(GatewayGranularity.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .frame(width: 94)
            .accessibilityLabel("速率图时间粒度")
        }
    }

    private var legendRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(series.series.enumerated()), id: \.element.id) { index, descriptor in
                HStack(spacing: 3) {
                    Circle()
                        .fill(seriesColor(at: index))
                        .frame(width: 5, height: 5)
                    Text("\(descriptor.channelName) · \(descriptor.model)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 12)
    }

    private var emptyChartState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("近\(granularity.durationTitle)暂无请求")
                .font(.system(size: 11, weight: .medium))
            Text("发起一次请求后，这里会显示各渠道的 Output TPS 趋势")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("速率图空状态")
    }

    private var chart: some View {
        Chart {
            seriesMarks

            if let bucket = hoveredBucket {
                RuleMark(x: .value("时间", bucket))
                    .foregroundStyle(PopoverPalette.separatorEmphasized)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltip(at: bucket)
                    }
            }
        }
        .chartXSelection(value: $hoverDate)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(PopoverPalette.separatorHairline)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xLabel(date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(PopoverPalette.separatorHairline)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(alignment: .topTrailing) {
                Text("tok/s")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                    .padding(.trailing, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("模型速度趋势折线图")
    }

    @ChartContentBuilder
    private var seriesMarks: some ChartContent {
        ForEach(segments) { segment in
            ForEach(segment.points) { point in
                lineMark(segment: segment, point: point)
                pointMark(segment: segment, point: point)
            }
            if let latest = segment.points.last {
                latestPointMark(segment: segment, point: latest)
            }
        }
    }

    @ChartContentBuilder
    private func lineMark(segment: SeriesSegment, point: GatewaySeriesPoint) -> some ChartContent {
        LineMark(
            x: .value("时间", point.bucketStart),
            y: .value("tok/s", point.averageTPS),
            series: .value("系列", segment.id)
        )
        .foregroundStyle(segment.color)
        .interpolationMethod(.monotone)
        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    @ChartContentBuilder
    private func pointMark(segment: SeriesSegment, point: GatewaySeriesPoint) -> some ChartContent {
        PointMark(
            x: .value("时间", point.bucketStart),
            y: .value("tok/s", point.averageTPS)
        )
        .foregroundStyle(segment.color)
        .symbol {
            Circle()
                .strokeBorder(segment.color, lineWidth: 1)
                .frame(width: 3, height: 3)
        }
    }

    @ChartContentBuilder
    private func latestPointMark(segment: SeriesSegment, point: GatewaySeriesPoint) -> some ChartContent {
        PointMark(
            x: .value("时间", point.bucketStart),
            y: .value("tok/s", point.averageTPS)
        )
        .foregroundStyle(segment.color)
        .symbolSize(22)
    }

    private func tooltip(at bucket: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tooltipLabel(bucket))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)

            let rows = series.series.enumerated().compactMap { index, descriptor -> (String, Color, Double)? in
                guard let value = series.averageTPS(for: descriptor.key, at: bucket) else { return nil }
                return ("\(descriptor.channelName) · \(descriptor.model)", seriesColor(at: index), value)
            }

            if rows.isEmpty {
                Text("该时间点无请求")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(row.1)
                            .frame(width: 4, height: 4)
                        Text(row.0)
                            .font(.system(size: 8))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(String(format: "%.1f tok/s", row.2))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(PopoverPalette.separatorHairline, lineWidth: 0.5)
        }
        .frame(width: 132)
    }

    // MARK: 引导卡

    private var guideCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text("AI 网关未启用")
                .font(.system(size: 12, weight: .medium))

            Text("启用后可在本地代理 OpenAI 兼容请求，并在这里查看各渠道的模型速度趋势")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)

            Button("前往设置") {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
            .accessibilityLabel("前往设置配置 AI 网关")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: 数据

    private struct SeriesSegment: Identifiable {
        let id: String
        let color: Color
        let points: [GatewaySeriesPoint]
    }

    private var segments: [SeriesSegment] {
        let bucketSeconds = granularity.bucketSeconds
        return series.series.enumerated().map { index, descriptor in
            let points = series.points
                .filter { $0.seriesKey == descriptor.key }
                .sorted { $0.bucketStart < $1.bucketStart }

            var chunks: [[GatewaySeriesPoint]] = []
            var current: [GatewaySeriesPoint] = []
            for point in points {
                if let last = current.last,
                   point.bucketStart.timeIntervalSince(last.bucketStart) > TimeInterval(bucketSeconds) {
                    chunks.append(current)
                    current = []
                }
                current.append(point)
            }
            if !current.isEmpty { chunks.append(current) }

            let color = seriesColor(at: index)
            return chunks.enumerated().map { chunkIndex, chunk in
                SeriesSegment(
                    id: "\(descriptor.key)#\(chunkIndex)",
                    color: color,
                    points: chunk
                )
            }
        }
        .flatMap { $0 }
    }

    private var hoveredBucket: Date? {
        guard let hoverDate else { return nil }
        return series.buckets.min {
            abs($0.timeIntervalSince(hoverDate)) < abs($1.timeIntervalSince(hoverDate))
        }
    }

    private var xDomain: ClosedRange<Date> {
        let buckets = series.buckets
        guard let first = buckets.first, let last = buckets.last, first < last else {
            let now = Date()
            return now.addingTimeInterval(-Double(granularity.bucketSeconds))...now
        }
        return first...last
    }

    private var xAxisValues: [Date] {
        let buckets = series.buckets
        guard buckets.count > 3 else { return buckets }
        // 不标注最后一个桶，避免标签在绘图区右边缘被裁切
        return [buckets[0], buckets[3], buckets[6]]
    }

    private func seriesColor(at index: Int) -> Color {
        let colors = PopoverPalette.gatewaySeriesColors
        return colors[index % colors.count]
    }

    private func xLabel(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        if granularity == .day {
            return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
        }
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func tooltipLabel(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        if granularity == .day {
            return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
        }
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func reload() async {
        guard settings.aiGatewayEnabled else {
            series = .empty
            return
        }
        let result = await service.series(granularity: granularity)
        guard !Task.isCancelled else { return }
        series = result
    }
}
