import Charts
import SwiftUI

// MARK: - 网关分区（FR-07：状态行 + 指标条 + 内容卡）

struct GatewaySectionView: View {
    let viewportHeight: CGFloat
    var onOpenSettings: () -> Void
    var onOpenHistory: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var service = GatewayService.shared

    @State private var series: GatewaySeriesResult = .empty
    @State private var summary: GatewayWindowSummary = .empty
    @State private var ranking: [GatewayChannelSummary] = []
    @State private var metric: GatewayMetric = .speed
    @State private var rankingMetric: GatewayRankingMetric = .requests
    @State private var showsRanking = false
    @State private var hoverDate: Date?

    private var range: GatewayRange {
        settings.aiGatewayRange
    }

    /// 内容卡的四段切换：前三段是图表口径，最后一段切到渠道排行
    private static let sectionItems: [(id: String, title: String)] =
        GatewayMetric.allCases.map { ($0.rawValue, $0.title) } + [(Self.rankingSectionID, "排行")]

    private static let rankingSectionID = "ranking"

    private var sectionSelection: String {
        showsRanking ? Self.rankingSectionID : metric.rawValue
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
        .task(id: reloadKey) {
            await reload()
        }
        .onChange(of: service.revision) { _, _ in
            Task { await reload() }
        }
        .onChange(of: settings.aiGatewayEnabled) { _, enabled in
            guard enabled else {
                series = .empty
                summary = .empty
                ranking = []
                return
            }
            Task { await reload() }
        }
    }

    /// 时间窗口、图表口径或排行维度任一变化都重新查询
    private var reloadKey: String {
        "\(range.rawValue)-\(metric.rawValue)-\(rankingMetric.rawValue)"
    }

    // MARK: 已启用

    private var enabledContent: some View {
        VStack(spacing: Self.rowGap) {
            statusRow

            if case .failed(let reason) = service.status {
                errorBanner(reason)
            }

            metricsStrip

            contentCard
                .frame(height: contentCardHeight)

            Spacer(minLength: 0)
        }
        .frame(height: viewportHeight, alignment: .top)
    }

    // 面板视口高度固定：指标条与状态行先占位，其余高度全给内容卡
    private static let rowGap: CGFloat = 6
    private static let statusRowHeight: CGFloat = 18
    private static let metricsStripHeight: CGFloat = 44
    private static let errorBannerHeight: CGFloat = 18

    /// 内容卡（趋势图或渠道排行）吃掉剩余高度；错误条先扣减
    private var contentCardHeight: CGFloat {
        var used = Self.statusRowHeight + Self.metricsStripHeight
        var gaps = 2 * Self.rowGap
        if case .failed = service.status {
            used += Self.errorBannerHeight
            gaps += Self.rowGap
        }
        return max(150, viewportHeight - used - gaps)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

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
        .frame(height: Self.statusRowHeight)
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
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(PopoverPalette.statusCritical)
            Text(reason)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(PopoverPalette.surfaceAlert)
        }
        .help(reason)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("网关错误：\(reason)")
    }

    // MARK: 指标条（请求 / Token / 平均速度）

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            metricCell(
                title: "请求",
                value: Self.compactCount(summary.requestCount),
                footnote: summary.failureCount > 0 ? "\(summary.failureCount) 次失败" : "全部成功",
                footnoteTint: summary.failureCount > 0 ? PopoverPalette.statusCritical : nil,
                accent: PopoverPalette.gatewayAccent,
                detail: "\(range.windowTitle)共 \(summary.requestCount) 次请求，成功 \(summary.successCount) 次，失败 \(summary.failureCount) 次"
            )

            metricDivider

            metricCell(
                title: "Token",
                value: Self.compactTokens(summary.totalTokens),
                footnote: "输入 \(Self.compactTokens(summary.inputTokens)) · 输出 \(Self.compactTokens(summary.outputTokens))",
                footnoteTint: nil,
                accent: PopoverPalette.accentBlue,
                detail: "\(range.windowTitle)共消耗 \(summary.totalTokens) token，输入 \(summary.inputTokens)，输出 \(summary.outputTokens)"
            )

            metricDivider

            metricCell(
                title: "平均速度",
                value: summary.averageTPS.map { String(format: "%.0f", $0) } ?? "—",
                footnote: summary.averageTPS == nil ? "暂无样本" : "tok/s 输出",
                footnoteTint: nil,
                accent: PopoverPalette.accentGreen,
                detail: summary.averageTPS.map { String(format: "%@平均输出速率 %.1f tok/s", range.windowTitle, $0) } ?? "\(range.windowTitle)暂无成功样本"
            )
        }
        .frame(height: Self.metricsStripHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PopoverPalette.surfaceCard)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PopoverPalette.separatorHairline, lineWidth: 0.5)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(PopoverPalette.separatorHairline)
            .frame(width: 0.5, height: 28)
    }

    private func metricCell(
        title: String,
        value: String,
        footnote: String,
        footnoteTint: Color?,
        accent: Color,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(footnote)
                .font(.system(size: 8))
                .foregroundStyle(footnoteTint ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)，\(detail)")
    }

    // MARK: 内容卡（趋势图 / 渠道排行 二选一）

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            contentHeader

            SegmentedPillBar(
                items: Self.sectionItems,
                selection: sectionSelection,
                compact: false
            ) { raw in
                if raw == Self.rankingSectionID {
                    showsRanking = true
                } else if let value = GatewayMetric(rawValue: raw) {
                    showsRanking = false
                    metric = value
                }
                hoverDate = nil
            }
            .accessibilityLabel("图表指标口径与渠道排行切换")

            if showsRanking {
                rankingContent
            } else {
                chartContent
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

    /// 头部：左标题随视图切换；右侧固定是时间窗口，排行时左侧多一个排序维度
    private var contentHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: showsRanking ? "list.bullet" : "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(showsRanking ? "排行" : range.windowTitle)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize()

            if showsRanking {
                SegmentedPillBar(
                    items: GatewayRankingMetric.allCases.map { ($0.rawValue, $0.title) },
                    selection: rankingMetric.rawValue,
                    compact: true
                ) { raw in
                    guard let value = GatewayRankingMetric(rawValue: raw) else { return }
                    rankingMetric = value
                }
                .frame(width: 96)
                .accessibilityLabel("排行排序维度")
            } else {
                Text("· \(metric.unitTitle)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 4)

            SegmentedPillBar(
                items: GatewayRange.allCases.map { ($0.rawValue, $0.title) },
                selection: range.rawValue,
                compact: true
            ) { raw in
                guard let value = GatewayRange(rawValue: raw) else { return }
                settings.aiGatewayRange = value
                hoverDate = nil
            }
            .frame(width: 116)
            .accessibilityLabel("统计时间范围")
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        if !series.series.isEmpty {
            legendRow
        }

        if series.points.isEmpty {
            emptyChartState
        } else {
            chart
        }
    }

    private var legendRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(series.series.enumerated()), id: \.element.id) { index, descriptor in
                HStack(spacing: 3) {
                    Circle()
                        .fill(seriesColor(at: index))
                        .frame(width: 5, height: 5)
                    Text(descriptor.model)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("\(descriptor.channelName) · \(descriptor.model)")
            }
        }
        .frame(height: 12)
    }

    private var emptyChartState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("\(range.windowTitle)暂无请求")
                .font(.system(size: 11, weight: .medium))
            Text("发起一次请求后，这里会显示各渠道的\(metric.title)趋势")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title)趋势空状态")
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
                AxisValueLabel(anchor: xAxisAnchor(for: value)) {
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
                        Text(yLabel(number))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(metric.title)趋势折线图")
    }

    @ChartContentBuilder
    private var seriesMarks: some ChartContent {
        switch metric {
        case .speed:
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    lineMark(segment: segment, point: point)
                    pointMark(segment: segment, point: point)
                }
                if let latest = segment.points.last {
                    latestPointMark(segment: segment, point: latest)
                }
            }
        case .tokens, .requests:
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    barMark(segment: segment, point: point)
                }
            }
        }
    }

    @ChartContentBuilder
    private func lineMark(segment: SeriesSegment, point: GatewaySeriesPoint) -> some ChartContent {
        LineMark(
            x: .value("时间", point.bucketStart),
            y: .value(metric.unitTitle, point.value),
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
            y: .value(metric.unitTitle, point.value)
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
            y: .value(metric.unitTitle, point.value)
        )
        .foregroundStyle(segment.color)
        .symbolSize(22)
    }

    /// Token 与请求口径用柱状图。日期轴是连续刻度，`width: .ratio` 推不出桶宽会把柱压成 0，
    /// 这里按系列数给固定点宽，保证柱子在任意桶距下都可见
    @ChartContentBuilder
    private func barMark(segment: SeriesSegment, point: GatewaySeriesPoint) -> some ChartContent {
        BarMark(
            x: .value("时间", point.bucketStart),
            y: .value(metric.unitTitle, point.value),
            width: .fixed(barWidth)
        )
        .position(by: .value("系列", segment.id))
        .foregroundStyle(segment.color.opacity(0.85))
        .cornerRadius(1.5)
    }

    /// 桶内按系列平分可用宽度：3 个系列约 6pt，4 个系列约 4.5pt
    private var barWidth: CGFloat {
        let count = max(1, series.series.count)
        return max(3, 18 / CGFloat(count))
    }

    private func tooltip(at bucket: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tooltipLabel(bucket))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)

            let rows = series.series.enumerated().compactMap { index, descriptor -> (String, Color, Double)? in
                guard let value = series.value(for: descriptor.key, at: bucket) else { return nil }
                return (descriptor.model, seriesColor(at: index), value)
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
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(valueText(row.2))
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

    // MARK: 渠道排行（内容卡内嵌）

    private var rankingContent: some View {
        Group {
            if ranking.isEmpty {
                emptyRankingState
            } else {
                let total = max(1, ranking.reduce(0) { $0 + rankingWeight($1) })

                VStack(spacing: 12) {
                    ForEach(Array(ranking.enumerated()), id: \.element.id) { index, item in
                        rankingRow(item, index: index, totalWeight: total)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyRankingState: some View {
        VStack(spacing: 4) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("\(range.windowTitle)暂无渠道数据")
                .font(.system(size: 11, weight: .medium))
            Text("成功请求会按渠道聚合到这里")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("渠道排行空状态")
    }

    /// 排行主数值：随所选维度切换
    private func rankingValue(_ item: GatewayChannelSummary) -> String {
        switch rankingMetric {
        case .requests: return "\(item.requestCount)"
        case .tokens: return Self.compactTokens(item.totalTokens)
        case .speed: return item.averageTPS.map { String(format: "%.0f", $0) } ?? "—"
        }
    }

    /// 占比条权重：速度口径无样本时按 0 计
    private func rankingWeight(_ item: GatewayChannelSummary) -> Double {
        switch rankingMetric {
        case .requests: return Double(item.requestCount)
        case .tokens: return Double(item.totalTokens)
        case .speed: return item.averageTPS ?? 0
        }
    }

    private func rankingRow(_ item: GatewayChannelSummary, index: Int, totalWeight: Double) -> some View {
        let tint = rankingColor(for: item.key, fallbackIndex: index)
        let share = Double(rankingWeight(item)) / Double(totalWeight)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(item.model)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(rankingValue(item))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .fixedSize()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PopoverPalette.barTrack)
                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: max(2, proxy.size.width * min(1, max(0, share))))
                }
            }
            .frame(height: 4)

            Text(rankingFootnote(item))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .help("\(item.channelName) · \(item.model)｜\(rankingFootnote(item))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.channelName) \(item.model)，\(item.requestCount) 次请求，\(item.totalTokens) token")
    }

    /// 细节行：主数值口径之外的信息，避免与右侧主数值重复
    private func rankingFootnote(_ item: GatewayChannelSummary) -> String {
        var parts: [String] = []
        if rankingMetric != .requests {
            parts.append("\(item.requestCount) 次请求")
        }
        if rankingMetric != .tokens {
            parts.append("\(Self.compactTokens(item.totalTokens)) token")
        }
        if rankingMetric != .speed, let tps = item.averageTPS {
            parts.append(String(format: "%.0f tok/s", tps))
        }
        if let ttft = item.averageTTFT {
            parts.append(String(format: "首字 %.1fs", ttft / 1000))
        }
        let percent = Int((item.successRate * 100).rounded())
        if percent < 100 {
            parts.append("成功 \(percent)%")
        }
        return parts.joined(separator: " · ")
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
        // 每个系列一条连续折线：即便中间有空洞也连线，避免只剩孤立圆点
        series.series.enumerated().compactMap { index, descriptor in
            let points = series.points
                .filter { $0.seriesKey == descriptor.key }
                .sorted { $0.bucketStart < $1.bucketStart }
            guard !points.isEmpty else { return nil }
            return SeriesSegment(
                id: descriptor.key,
                color: seriesColor(at: index),
                points: points
            )
        }
    }

    private var hoveredBucket: Date? {
        guard let hoverDate else { return nil }
        return series.buckets.min {
            abs($0.timeIntervalSince(hoverDate)) < abs($1.timeIntervalSince(hoverDate))
        }
    }

    private var xDomain: ClosedRange<Date> {
        let buckets = series.buckets
        // 两端各留半个桶宽：折线末点与柱状最后一根柱都落在桶起点上，不留边距会被绘图区裁掉一半
        let pad = Double(range.bucketSeconds) / 2
        guard let first = buckets.first, let last = buckets.last else {
            let now = Date()
            return now.addingTimeInterval(-Double(range.bucketSeconds))...now
        }
        if first == last {
            // 只有一个桶（例如刚过零点看「今天」）时按单桶宽度铺开，避免退化成无宽度的区间
            return first.addingTimeInterval(-pad)...first.addingTimeInterval(pad)
        }
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    /// 三个刻度均匀铺开，并在右端留出余量：标签以刻度为中心，贴边时半宽会被裁掉
    private var xAxisValues: [Date] {
        let buckets = series.buckets
        guard buckets.count > 3 else { return buckets }
        let lastIndex = Double(buckets.count - 1) * 0.85
        var values: [Date] = []
        for index in 0..<3 {
            let ratio = Double(index) / 2
            let position = Int((ratio * lastIndex).rounded())
            let date = buckets[min(position, buckets.count - 1)]
            if values.last != date { values.append(date) }
        }
        return values
    }

    private func seriesColor(at index: Int) -> Color {
        let colors = PopoverPalette.gatewaySeriesColors
        return colors[index % colors.count]
    }

    /// 渠道排行的色点与图例保持一致：优先复用该「渠道 · 模型」在图例中的颜色
    private func rankingColor(for key: String, fallbackIndex: Int) -> Color {
        if let index = series.series.firstIndex(where: { $0.key == key }) {
            return seriesColor(at: index)
        }
        let offset = series.series.count
        return seriesColor(at: offset + fallbackIndex)
    }

    /// 首尾刻度把标签向内对齐，避免半宽被绘图区裁掉
    private func xAxisAnchor(for value: AxisValue) -> UnitPoint? {
        guard let date = value.as(Date.self), let first = xAxisValues.first, let last = xAxisValues.last else {
            return nil
        }
        if date == first { return .topLeading }
        if date == last { return .topTrailing }
        return nil
    }

    private func xLabel(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        switch range {
        case .hour:
            return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        case .today:
            return String(format: "%02d:00", components.hour ?? 0)
        case .month, .all:
            return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
        }
    }

    private func tooltipLabel(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        switch range {
        case .hour:
            return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        case .today:
            return String(format: "%02d:00", components.hour ?? 0)
        case .month, .all:
            return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
        }
    }

    /// 坐标轴刻度：Token 用紧凑单位，其余保留整数或一位小数
    private func yLabel(_ value: Double) -> String {
        switch metric {
        case .tokens:
            return Self.compactTokens(Int(value))
        case .requests:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .speed:
            return value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// 提示气泡与图例中的数值文案
    private func valueText(_ value: Double) -> String {
        switch metric {
        case .tokens: return Self.compactTokens(Int(value))
        case .requests: return String(format: "%.0f 次", value)
        case .speed: return String(format: "%.1f tok/s", value)
        }
    }

    // MARK: 数值格式化

    /// 1.2M / 480K / 900
    static func compactTokens(_ value: Int) -> String {
        let number = Double(value)
        switch abs(value) {
        case 1_000_000...:
            return String(format: "%.1fM", number / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 1_000...:
            return String(format: "%.1fK", number / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default:
            return "\(value)"
        }
    }

    static func compactCount(_ value: Int) -> String {
        value > 9_999 ? compactTokens(value) : "\(value)"
    }

    // MARK: 加载

    private func reload() async {
        guard settings.aiGatewayEnabled else {
            series = .empty
            summary = .empty
            ranking = []
            return
        }
        let currentRange = range
        let currentMetric = metric
        let currentRankingMetric = rankingMetric

        async let seriesTask = service.series(range: currentRange, metric: currentMetric)
        async let summaryTask = service.summary(range: currentRange)
        async let rankingTask = service.channelSummaries(
            range: currentRange,
            limit: 4,
            metric: currentRankingMetric
        )

        let result = await seriesTask
        let windowSummary = await summaryTask
        let channelRanking = await rankingTask

        guard !Task.isCancelled else { return }
        series = result
        summary = windowSummary
        ranking = channelRanking
    }
}
