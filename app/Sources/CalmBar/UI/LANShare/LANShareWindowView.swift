import AppKit
import CoreImage
import SwiftUI

// MARK: - 局域网互传窗口

public struct LANShareWindowView: View {
    @ObservedObject private var service = LANShareService.shared
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var showingTextComposer = false
    @State private var draftText = ""
    @State private var draftIntro = ""
    @State private var showingActivity = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let code = service.passcodeToShowOnce {
                        passcodeBanner(code)
                    }
                    statusCard
                    if service.isRunning {
                        shareLinkCard
                    }
                    if let error = service.lastError, !service.isRunning {
                        errorCard(error)
                    }
                    itemsCard
                    if !activeTransfers.isEmpty {
                        transfersCard
                    }
                    activityCard
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 700, minHeight: 560)
        .sheet(isPresented: $showingTextComposer) {
            textComposer
        }
    }

    // MARK: - 顶部

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("局域网互传")
                    .font(.system(size: 15, weight: .semibold))
                Text("同一 Wi-Fi 下用浏览器访问，无需安装 App")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                service.openReceiveDirectory()
            } label: {
                Label("接收文件夹", systemImage: "folder")
            }
            .controlSize(.small)
            .focusable(false)

            Button {
                StatusBarManager.shared.openSettingsWindow(tab: .lanShare)
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .controlSize(.small)
            .focusable(false)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    // MARK: - 状态

    private var statusCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if service.isRunning {
                Text("\(service.sessionCount) 台设备在线")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Toggle("", isOn: $appSettings.lanShareEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var statusColor: Color {
        switch service.status {
        case .running: return .green
        case .starting: return .orange
        case .restricted: return .orange
        case .failed: return .red
        case .stopped: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var statusTitle: String {
        switch service.status {
        case .running:
            return "正在共享"
        case .starting:
            return "正在启动服务"
        case .restricted:
            return "未连接局域网"
        case .failed:
            return "服务启动失败"
        case .stopped:
            return appSettings.lanShareEnabled ? "服务已停止" : "局域网互传未开启"
        }
    }

    private var statusDetail: String {
        switch service.status {
        case .running:
            let port = service.settings.port
            let connections = service.connectionCount
            return "端口 \(port) · \(connections) 个活动连接"
        case .starting:
            return "正在监听端口，请稍候"
        case .restricted:
            return "请先连接 Wi-Fi 或有线网络"
        case .failed:
            return service.lastError?.userMessage ?? "请检查端口与接收文件夹"
        case .stopped:
            return appSettings.lanShareEnabled ? "正在等待服务启动" : "打开右侧开关即可开始共享"
        }
    }

    // MARK: - 口令提示

    private func passcodeBanner(_ code: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("已生成访问口令")
                    .font(.system(size: 12, weight: .semibold))
                Text("请把这 6 位口令告诉对方：\(code)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
            .controlSize(.small)
            Button("知道了") {
                service.dismissPasscodeHint()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    // MARK: - 分享链接

    private var shareLinkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分享链接")
                .font(.system(size: 12, weight: .semibold))

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(service.shareURL ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)

                    HStack(spacing: 10) {
                        Button {
                            service.copyShareLink()
                        } label: {
                            Label("复制链接", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)

                        Text(service.settings.passcodeEnabled
                             ? "访问者需要输入 6 位口令"
                             : "链接内已包含访问令牌，请勿公开分享")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                if let url = service.shareURL {
                    LANShareQRCodeView(text: url)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func errorCard(_ error: LANShareError) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(error.userMessage)
                    .font(.system(size: 12, weight: .semibold))
                if let next = error.nextStep {
                    Text(next)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("重试") {
                service.restart()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    // MARK: - 分享内容

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("已分享内容")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(service.items.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    pickFiles()
                } label: {
                    Label("文件", systemImage: "plus")
                }
                .controlSize(.small)

                Button {
                    draftText = ""
                    draftIntro = ""
                    showingTextComposer = true
                } label: {
                    Label("文本", systemImage: "text.alignleft")
                }
                .controlSize(.small)

                if !service.items.isEmpty {
                    Button("清空") {
                        service.removeAllItems()
                    }
                    .controlSize(.small)
                }
            }

            if service.items.isEmpty {
                Text("还没有分享内容。添加文件、文件夹或文本后，对方的网页上会立即出现。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(service.items) { item in
                        itemRow(item)
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func itemRow(_ item: LANShareItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: itemIcon(item.kind))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(itemMeta(item))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !item.isValid {
                Text("已失效")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Button {
                service.removeItem(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("从分享列表移除")
        }
        .padding(.vertical, 8)
    }

    private func itemIcon(_ kind: LANShareItemKind) -> String {
        switch kind {
        case .file: return "doc"
        case .folder: return "folder"
        case .text: return "text.alignleft"
        }
    }

    private func itemMeta(_ item: LANShareItem) -> String {
        var parts: [String] = []
        switch item.kind {
        case .file: parts.append("文件")
        case .folder: parts.append("文件夹")
        case .text: parts.append("文本")
        }
        if let size = item.sizeText {
            parts.append(size)
        }
        if item.source == .remote {
            if let ip = item.uploaderIP, !ip.isEmpty {
                parts.append("来自 \(ip)")
            } else {
                parts.append("来自对方")
            }
        }
        if let intro = item.intro, !intro.isEmpty {
            parts.append(intro)
        }
        if !item.isValid, let reason = item.invalidReason {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 传输进度

    /// 只展示进行中的任务，完成/失败/取消的条目不再占用「正在传输」卡片。
    private var activeTransfers: [LANShareTransferTask] {
        service.transfers.filter { $0.state == .waiting || $0.state == .transferring }
    }

    private var transfersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("正在传输")
                .font(.system(size: 12, weight: .semibold))

            ForEach(activeTransfers) { task in
                transferRow(task)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func transferRow(_ task: LANShareTransferTask) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: task.direction == .download ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(.secondary)
                Text(task.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(transferMeta(task))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: transferProgress(task))
                .progressViewStyle(.linear)
        }
        .padding(.vertical, 3)
    }

    private func transferProgress(_ task: LANShareTransferTask) -> Double {
        guard task.totalBytes > 0 else { return task.state == .completed ? 1 : 0 }
        return min(1, Double(task.transferredBytes) / Double(task.totalBytes))
    }

    private func transferMeta(_ task: LANShareTransferTask) -> String {
        switch task.state {
        case .completed:
            return "已完成"
        case .failed:
            return task.errorMessage ?? "失败"
        case .cancelled:
            return "已取消"
        case .waiting:
            return "等待中"
        case .transferring:
            let done = ByteCountFormatter.string(fromByteCount: task.transferredBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
            let speed = ByteCountFormatter.string(fromByteCount: Int64(task.bytesPerSecond), countStyle: .file) + "/s"
            return "\(done) / \(total) · \(speed)"
        }
    }

    // MARK: - 最近活动

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingActivity.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showingActivity ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("最近活动")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingActivity {
                if service.activityLog.isEmpty {
                    Text("暂无活动记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(service.activityLog.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - 文本编辑

    private var textComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加要分享的文本")
                .font(.system(size: 14, weight: .semibold))

            TextEditor(text: $draftText)
                .font(.system(size: 12))
                .frame(minWidth: 460, minHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            TextField("备注（可选）", text: $draftIntro)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") {
                    showingTextComposer = false
                }
                .keyboardShortcut(.cancelAction)

                Button("添加") {
                    service.addText(draftText, intro: draftIntro)
                    showingTextComposer = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - 工具

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加到分享"
        panel.message = "选择要分享的文件或文件夹"
        if panel.runModal() == .OK {
            service.addFiles(panel.urls)
        }
    }
}

// MARK: - 二维码

struct LANShareQRCodeView: View {
    let text: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: 126, height: 126)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
        )
        .onAppear { image = Self.generate(text) }
        .onChange(of: text) { _, newValue in
            image = Self.generate(newValue)
        }
    }

    private static func generate(_ text: String) -> NSImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
