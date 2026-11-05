import AppKit
import SwiftUI

// MARK: - 请求历史窗口（FR-08：分页表格 + 筛选 + 复算明细）

struct GatewayHistoryView: View {
    private let pageSize = 50

    @State private var records: [GatewayRequestRecord] = []
    @State private var models: [String] = []
    @State private var channels: [String] = []
    @State private var selectedModel = ""
    @State private var selectedChannel = ""
    @State private var selectedStatus = ""
    @State private var range: HistoryRange = .all
    @State private var isLoading = false
    /// 加载期间收到的刷新请求，加载结束后补一次，避免筛选条件与表格内容不一致
    @State private var pendingReload: Bool?
    @State private var nextCursor: GatewayRequestCursor?
    @State private var hasMore = true
    @State private var loadError: String?
    @State private var detail: GatewayRequestRecord?
    @State private var pendingDelete: GatewayRequestRecord?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 460)
        .task { await reload(reset: true) }
        .alert("删除这条记录？", isPresented: deleteAlertBinding, presenting: pendingDelete) { record in
            Button("删除", role: .destructive) {
                Task { await delete(record) }
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: { record in
            Text("「\(record.requestedModel)」于 \(timeText(record.createdAt)) 的请求记录将被永久删除。")
        }
        .alert("清空全部历史？", isPresented: $showClearConfirm) {
            Button("清空", role: .destructive) {
                Task { await clearAll() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("全部请求记录将被永久删除，速率图也会重置。")
        }
        .sheet(item: $detail) { record in
            detailSheet(record)
        }
    }

    // MARK: 顶部筛选

    private var toolbar: some View {
        HStack(spacing: 14) {
            filterMenu(
                title: "模型",
                selection: $selectedModel,
                allTitle: "全部模型",
                options: models.map { (label: $0, value: $0) },
                currentTitle: selectedModel.isEmpty ? "全部模型" : selectedModel
            )

            filterMenu(
                title: "渠道",
                selection: $selectedChannel,
                allTitle: "全部渠道",
                options: channels.map { (label: $0, value: $0) },
                currentTitle: selectedChannel.isEmpty ? "全部渠道" : selectedChannel
            )

            filterMenu(
                title: "状态",
                selection: $selectedStatus,
                allTitle: "全部状态",
                options: GatewayRequestStatus.allCases.map { (label: $0.title, value: $0.rawValue) },
                currentTitle: GatewayRequestStatus(rawValue: selectedStatus)?.title ?? "全部状态"
            )

            filterLabel(title: "时间") {
                Menu {
                    ForEach(HistoryRange.allCases) { item in
                        Button(item.title) { range = item }
                    }
                } label: {
                    filterValueLabel(range.title)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Spacer(minLength: 8)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await reload(reset: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")
            .disabled(isLoading)

            Button("清空历史") {
                showClearConfirm = true
            }
            .disabled(records.isEmpty && isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: selectedModel) { _, _ in Task { await reload(reset: true) } }
        .onChange(of: selectedChannel) { _, _ in Task { await reload(reset: true) } }
        .onChange(of: selectedStatus) { _, _ in Task { await reload(reset: true) } }
        .onChange(of: range) { _, _ in Task { await reload(reset: true) } }
    }

    // MARK: 筛选控件

    private func filterLabel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
        .fixedSize()
    }

    private func filterValueLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// 自绘筛选菜单：避免系统 Picker 在窄窗口下把内联标签与控件叠在一起
    private func filterMenu(
        title: String,
        selection: Binding<String>,
        allTitle: String,
        options: [(label: String, value: String)],
        currentTitle: String
    ) -> some View {
        filterLabel(title: title) {
            Menu {
                Button(allTitle) { selection.wrappedValue = "" }
                if !options.isEmpty {
                    Divider()
                }
                ForEach(options, id: \.value) { option in
                    Button(option.label) { selection.wrappedValue = option.value }
                }
            } label: {
                filterValueLabel(currentTitle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: 表格

    @ViewBuilder
    private var content: some View {
        if let loadError, records.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(PopoverPalette.statusCritical)
                Text("请求历史不可读")
                    .font(.system(size: 14, weight: .semibold))
                Text(loadError)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await reload(reset: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if records.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("暂无请求记录")
                    .font(.system(size: 14, weight: .semibold))
                Text("网关收到请求后，这里会显示完整明细")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                table
                Divider()
                footer
            }
        }
    }

    private var table: some View {
        Table(records) {
            TableColumn("时间") { record in
                Text(shortTimeText(record.createdAt))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .help(timeText(record.createdAt))
            }
            .width(100)

            TableColumn("模型") { record in
                Text(record.requestedModel)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .help(record.requestedModel)
            }
            .width(min: 60, ideal: 80, max: 110)

            TableColumn("渠道") { record in
                Text(record.channelName ?? "—")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .width(min: 56, ideal: 70, max: 96)

            TableColumn("状态") { record in
                Text(record.status.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(record.status))
            }
            .width(50)

            TableColumn("Tokens") { record in
                Text(tokenText(record))
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(80)

            TableColumn("TTFT") { record in
                Text(record.ttftMs.map { "\($0) ms" } ?? "—")
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(52)

            TableColumn("TPS") { record in
                Text(record.outputTPS.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(44)

            TableColumn("总耗时") { record in
                Text("\(record.durationMs) ms")
                    .font(.system(size: 11, design: .monospaced))
            }
            .width(64)

            TableColumn("切换原因") { record in
                Text(record.retryReason ?? "—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(record.retryReason ?? "")
            }
            .width(min: 56, ideal: 72, max: 200)

            TableColumn("操作") { record in
                HStack(spacing: 8) {
                    Button {
                        detail = record
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .help("查看详情")

                    if record.status == .failed {
                        Button {
                            copyError(record)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("复制错误信息")
                    }

                    Button {
                        pendingDelete = record
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("删除记录")
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .width(84)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("已加载 \(records.count) 条")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let loadError {
                Text("加载失败：\(loadError)")
                    .font(.system(size: 10))
                    .foregroundStyle(PopoverPalette.statusCritical)
                    .lineLimit(1)
            }

            Spacer()

            if hasMore {
                Button {
                    Task { await reload(reset: false) }
                } label: {
                    Text("加载更多")
                        .font(.system(size: 11))
                }
                .disabled(isLoading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: 详情

    private func detailSheet(_ record: GatewayRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("请求详情")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("关闭") {
                    detail = nil
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("请求 ID", record.requestID)
                    detailRow("时间", timeText(record.createdAt))
                    detailRow("端点", record.endpoint)
                    detailRow("协议", record.protocolName)
                    detailRow("流式", record.isStream ? "是" : "否")
                    detailRow("请求模型", record.requestedModel)
                    detailRow("上游模型", record.upstreamModel ?? "—")
                    detailRow("渠道", record.channelName ?? "—")
                    detailRow("渠道 ID", record.channelID ?? "—")
                    detailRow("状态", record.status.title)
                    detailRow("HTTP 状态", record.httpStatus.map(String.init) ?? "—")
                    detailRow("Input Tokens", tokenCountText(record.inputTokens, source: record.tokenSource))
                    detailRow("Output Tokens", tokenCountText(record.outputTokens, source: record.tokenSource))
                    detailRow("Total Tokens", record.totalTokens.map(String.init) ?? "—")
                    detailRow("Token 来源", record.tokenSource?.rawValue ?? "—")
                    detailRow("TTFT", record.ttftMs.map { "\($0) ms" } ?? "—")
                    detailRow("生成耗时", record.generationMs.map { "\($0) ms" } ?? "—")
                    detailRow("总耗时", "\(record.durationMs) ms")
                    detailRow("Output TPS", record.outputTPS.map { String(format: "%.2f", $0) } ?? "—")
                    detailRow("速度来源", record.speedSource?.rawValue ?? "—")
                    detailRow("切换原因", record.retryReason ?? "—")
                    detailRow("客户端取消", record.clientCancelled ? "是" : "否")
                    detailRow("错误信息", record.errorMessage ?? "—")
                }
                .padding(14)
            }
            .frame(width: 460, height: 420)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 数据

    private var currentFilter: GatewayRequestFilter {
        GatewayRequestFilter(
            model: selectedModel.isEmpty ? nil : selectedModel,
            channel: selectedChannel.isEmpty ? nil : selectedChannel,
            status: GatewayRequestStatus(rawValue: selectedStatus),
            since: range.since
        )
    }

    private func reload(reset: Bool) async {
        guard !isLoading else {
            pendingReload = (pendingReload ?? false) || reset
            return
        }
        isLoading = true
        var resetNow = reset
        while true {
            pendingReload = nil
            await load(reset: resetNow)
            guard let pending = pendingReload else { break }
            resetNow = resetNow || pending
        }
        isLoading = false
    }

    private func load(reset: Bool) async {
        do {
            if reset {
                loadError = nil
                models = (try? await GatewayDatabase.shared.distinctModels()) ?? models
                channels = (try? await GatewayDatabase.shared.distinctChannels()) ?? channels
            }
            let rows = try await GatewayDatabase.shared.recent(
                filter: currentFilter,
                before: reset ? nil : nextCursor,
                limit: pageSize
            )
            if reset {
                records = rows
            } else {
                records.append(contentsOf: rows)
            }
            nextCursor = rows.last.map(GatewayRequestCursor.init(record:))
            hasMore = rows.count >= pageSize
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ record: GatewayRequestRecord) async {
        pendingDelete = nil
        do {
            try await GatewayDatabase.shared.delete(id: record.id)
            await reload(reset: true)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func clearAll() async {
        // deleteAllHistory 内部已完成清空与 revision 刷新，这里不再重复删除
        await GatewayService.shared.deleteAllHistory()
        records = []
        hasMore = false
        nextCursor = nil
        models = (try? await GatewayDatabase.shared.distinctModels()) ?? []
        channels = (try? await GatewayDatabase.shared.distinctChannels()) ?? []
        if !selectedModel.isEmpty, !models.contains(selectedModel) { selectedModel = "" }
        if !selectedChannel.isEmpty, !channels.contains(selectedChannel) { selectedChannel = "" }
    }

    private func copyError(_ record: GatewayRequestRecord) {
        let text = record.errorMessage ?? "请求失败（无错误详情）"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: 格式化

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    /// 表格内紧凑时间：省略年份，完整时间放在 tooltip
    private func shortTimeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%02d-%02d %02d:%02d:%02d",
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    private func tokenText(_ record: GatewayRequestRecord) -> String {
        let mark = record.tokenSource == .estimated ? "≈" : ""
        let input = record.inputTokens.map { "\(mark)\($0)" } ?? "—"
        let output = record.outputTokens.map { "\(mark)\($0)" } ?? "—"
        return "\(input) / \(output)"
    }

    private func tokenCountText(_ value: Int?, source: GatewayTokenSource?) -> String {
        guard let value else { return "—" }
        return source == .estimated ? "≈\(value)" : "\(value)"
    }

    private func statusColor(_ status: GatewayRequestStatus) -> Color {
        switch status {
        case .success: PopoverPalette.statusSuccess
        case .failed: PopoverPalette.statusCritical
        case .cancelled: PopoverPalette.statusWarning
        case .rejected: .secondary
        }
    }
}

private enum HistoryRange: String, CaseIterable, Identifiable {
    case all
    case hour
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部时间"
        case .hour: return "近 1 小时"
        case .day: return "近 24 小时"
        case .week: return "近 7 天"
        }
    }

    var since: Date? {
        switch self {
        case .all: return nil
        case .hour: return Date().addingTimeInterval(-3600)
        case .day: return Date().addingTimeInterval(-86400)
        case .week: return Date().addingTimeInterval(-604800)
        }
    }
}
