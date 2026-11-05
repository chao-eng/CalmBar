import AppKit
import Combine
import SwiftUI

// MARK: - 偏好设置「AI 网关」Tab（FR-09）

public struct AIGatewaySettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var service = GatewayService.shared

    @State private var portText = ""
    @State private var serverKeyDraft = ""
    @State private var editingChannel: ChannelDraft?
    @State private var editingModel: ModelDraft?
    @State private var testStates: [String: ChannelTestState] = [:]
    @State private var copiedEndpoint = false
    @State private var generatedServerKey = false
    @State private var now = Date()

    private let cooldownTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeatureMasterToggleCard(
                    icon: SettingsTab.aiGateway.icon,
                    iconColors: SettingsTab.aiGateway.gradientColors,
                    title: "启用本地 AI 网关",
                    activeSubtitle: "已激活 · \(service.status.title) · \(GatewayService.endpoint)",
                    inactiveSubtitle: "已停用 · 不监听端口，配置与历史记录保留",
                    isEnabled: $settings.aiGatewayEnabled
                )

                if case .failed(let reason) = service.status {
                    errorBanner(reason)
                }

                validationBanner

                serviceConfig
                modelSection
                channelSection
                usageSection
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .onAppear {
            portText = String(settings.aiGatewayPort)
            serverKeyDraft = GatewayKeychain.serverKey()
        }
        .onReceive(cooldownTimer) { now = $0 }
        .sheet(item: $editingChannel) { draft in
            ChannelEditorSheet(draft: draft) { saved in
                saveChannel(saved)
            } onCancel: {
                editingChannel = nil
            }
        }
        .sheet(item: $editingModel) { draft in
            ModelEditorSheet(draft: draft, channels: settings.aiGatewayChannels) { saved in
                saveModel(saved)
            } onCancel: {
                editingModel = nil
            }
        }
    }

    // MARK: 状态与校验

    private func errorBanner(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("网关无法启动")
                    .font(.system(size: 12, weight: .semibold))
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        let issues = settings.aiGatewayEnabled ? service.validationIssues : []
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("配置校验未通过（\(issues.count) 项）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                ForEach(issues.prefix(5)) { issue in
                    Text("· \(issue.message)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            }
        }
    }

    // MARK: 服务配置

    private var serviceConfig: some View {
        GroupBox(label: Label("服务配置", systemImage: "server.rack")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("监听地址")
                        .font(.system(size: 12.5))
                        .frame(width: 80, alignment: .leading)
                    Text("127.0.0.1（固定回环，不可修改）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("监听端口")
                        .font(.system(size: 12.5))
                        .frame(width: 80, alignment: .leading)
                    TextField("8317", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                    Button("应用") {
                        applyPort()
                    }
                    if settings.aiGatewayPort != Int(portText) {
                        Text("修改后需应用，网关会按新端口重启")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("访问密钥")
                        .font(.system(size: 12.5))
                        .frame(width: 80, alignment: .leading)
                    SecureField("留空表示不校验客户端凭据", text: $serverKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 320)
                    Button("保存密钥") {
                        GatewayKeychain.setServerKey(serverKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        service.restart()
                    }
                    Button(generatedServerKey ? "已生成并复制" : "随机生成") {
                        let key = Self.randomServerKey()
                        serverKeyDraft = key
                        GatewayKeychain.setServerKey(key)
                        service.restart()
                        copyToPasteboard(key)
                        generatedServerKey = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            generatedServerKey = false
                        }
                    }
                    .disabled(generatedServerKey)
                    .help("生成 24 位随机访问密钥，保存并复制到剪贴板")
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("本地端点")
                        .font(.system(size: 12.5))
                        .frame(width: 80, alignment: .leading)
                    Text(GatewayService.endpoint)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                    Button(copiedEndpoint ? "已复制" : "复制") {
                        copyToPasteboard(GatewayService.endpoint)
                        copiedEndpoint = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copiedEndpoint = false
                        }
                    }
                    .disabled(copiedEndpoint)
                    Button("查看请求历史") {
                        GatewayHistoryWindowController.shared.show()
                    }
                    .help("打开独立的请求历史窗口，查看每条请求的耗时与 Token 明细")
                    Spacer()
                }

                if service.status.isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(verbatim: "网关正在监听 \(settings.aiGatewayPort) 端口")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("重启网关") {
                            service.restart()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: 模型别名

    private var modelSection: some View {
        GroupBox(label: Label("模型别名", systemImage: "arrow.triangle.branch")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("客户端请求使用的模型别名，按渠道顺序尝试并在失败时自动切换")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if settings.aiGatewayModels.isEmpty {
                    Text("尚未配置模型别名")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(settings.aiGatewayModels) { model in
                        modelRow(model)
                        if model.id != settings.aiGatewayModels.last?.id {
                            Divider()
                        }
                    }
                }

                Button {
                    editingModel = ModelDraft(originalAlias: nil, alias: "", bindings: [])
                } label: {
                    Label("新增模型别名", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(8)
        }
    }

    private func modelRow(_ model: AIGatewayModelRoute) -> some View {
        HStack(spacing: 8) {
            Text(model.alias)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

            Text(channelChain(model.channelIDs))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("编辑") {
                editingModel = ModelDraft(
                    originalAlias: model.alias,
                    alias: model.alias,
                    bindings: model.bindings
                )
            }
            .controlSize(.small)

            Button("删除") {
                settings.aiGatewayModels.removeAll { $0.alias == model.alias }
            }
            .controlSize(.small)
        }
        .frame(minHeight: 24)
    }

    private func channelChain(_ ids: [String]) -> String {
        let names = ids.map { id in
            settings.aiGatewayChannels.first(where: { $0.id == id })?.name ?? "（已删除）"
        }
        return names.isEmpty ? "未绑定渠道" : names.joined(separator: " → ")
    }

    // MARK: 渠道

    private var channelSection: some View {
        GroupBox(label: Label("渠道", systemImage: "point.3.connected.trianglepath.dotted")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("每个渠道对应一个上游端点；启用开关即时生效，禁用渠道不参与路由")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if settings.aiGatewayChannels.isEmpty {
                    Text("尚未配置渠道")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(settings.aiGatewayChannels) { channel in
                        channelRow(channel)
                        if channel.id != settings.aiGatewayChannels.last?.id {
                            Divider()
                        }
                    }
                }

                Button {
                    editingChannel = ChannelDraft(
                        channel: AIGatewayChannel(),
                        apiKey: "",
                        proxyPassword: "",
                        isNew: true
                    )
                } label: {
                    Label("新增渠道", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(8)
        }
    }

    private func channelRow(_ channel: AIGatewayChannel) -> some View {
        let references = settings.aiGatewayModels.filter { $0.channelIDs.contains(channel.id) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: channelEnabledBinding(channel.id))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                Text(channel.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                if !channel.enabled {
                    Text("已禁用")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if channel.proxy.mode != .direct {
                    Label("代理", systemImage: "network")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let remaining = cooldownRemaining(channel) {
                    Text("冷却 \(remaining)s")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }

                Spacer()

                testButton(channel)

                Button("编辑") {
                    editingChannel = ChannelDraft(
                        channel: channel,
                        apiKey: "",
                        proxyPassword: channel.proxy.passwordKeyID.map { GatewayKeychain.proxyPassword(for: $0) } ?? "",
                        isNew: false
                    )
                }
                .controlSize(.small)

                Button("删除") {
                    deleteChannel(channel)
                }
                .controlSize(.small)
                .disabled(!references.isEmpty)
                .help(references.isEmpty ? "删除该渠道" : "被模型别名引用，请先移除引用")
            }

            HStack(spacing: 6) {
                Text(channel.baseURL)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("· \(modelsSummary(channel.models))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(channel.models.joined(separator: "\n"))
                Spacer()
                Text(maskedKey(channel.id))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let state = testStates[channel.id] {
                testResultView(state)
            }
        }
        .frame(minHeight: 30)
    }

    private func cooldownRemaining(_ channel: AIGatewayChannel) -> Int? {
        channel.models.compactMap {
            GatewayCooldownStore.shared.remainingSeconds(channelID: channel.id, model: $0, now: now)
        }.max()
    }

    private func modelsSummary(_ models: [String]) -> String {
        guard let first = models.first else { return "未配置模型" }
        return models.count == 1 ? first : "\(first) 等 \(models.count) 个模型"
    }

    private func testButton(_ channel: AIGatewayChannel) -> some View {
        Button {
            runTest(channel)
        } label: {
            if case .testing = testStates[channel.id] {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text("连接测试")
            }
        }
        .controlSize(.small)
        .disabled(isTesting(channel.id))
        .help("请求 GET <base_url>/models，仅验证端点可达与延迟，不计入统计")
    }

    private func isTesting(_ id: String) -> Bool {
        if case .testing = testStates[id] { return true }
        return false
    }

    @ViewBuilder
    private func testResultView(_ state: ChannelTestState) -> some View {
        switch state {
        case .testing:
            Text("连接测试中…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .success(let milliseconds):
            Text("连接成功 · \(milliseconds) ms")
                .font(.system(size: 10))
                .foregroundStyle(.green)
                .help("仅验证 GET <Base URL>/models 可达，不代表 /chat/completions 端点一定可用")
        case .failure(let message):
            Text("连接失败：\(message)")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(4)
                .textSelection(.enabled)
                .help(message)
        }
    }

    private func runTest(_ channel: AIGatewayChannel) {
        testStates[channel.id] = .testing
        Task {
            let started = Date()
            do {
                try await GatewayConnectionTester.test(channel: channel)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                testStates[channel.id] = .success(elapsed)
            } catch {
                testStates[channel.id] = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: 调用示例

    private var usageSection: some View {
        GroupBox(label: Label("调用示例", systemImage: "terminal")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(curlExample)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }

                Text("任何兼容 OpenAI Chat Completions / Responses 的客户端，把 Base URL 指向本地端点即可，模型填上方配置的别名。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var curlExample: String {
        let alias = settings.aiGatewayModels.first?.alias ?? "gpt-4o-mini"
        let authLine = serverKeyDraft.isEmpty ? "" : "-H \"Authorization: Bearer <访问密钥>\" \\\n  "
        return """
        curl \(GatewayService.endpoint)/chat/completions \\
          \(authLine)-H "Content-Type: application/json" \\
          -d '{"model":"\(alias)","messages":[{"role":"user","content":"hi"}],"stream":true}'
        """
    }

    // MARK: 操作

    private func applyPort() {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)),
              GatewayConfigValidator.validatePort(port) == nil else { return }
        settings.aiGatewayPort = port
        service.restart()
    }

    private func saveChannel(_ draft: ChannelDraft) {
        var channel = draft.channel
        channel.models = AIGatewayChannel.normalizedModels(channel.models)
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            GatewayKeychain.setAPIKey(key, for: channel.id)
        }

        var proxy = channel.proxy
        if proxy.mode == .direct {
            proxy = GatewayProxyConfig()
        } else if !draft.proxyPassword.isEmpty {
            let keyID = proxy.passwordKeyID ?? "channel.\(channel.id).proxy"
            GatewayKeychain.setProxyPassword(draft.proxyPassword, for: keyID)
            proxy.passwordKeyID = keyID
        }
        channel.proxy = proxy

        if let index = settings.aiGatewayChannels.firstIndex(where: { $0.id == channel.id }) {
            settings.aiGatewayChannels[index] = channel
        } else {
            settings.aiGatewayChannels.append(channel)
        }
        editingChannel = nil
        service.restart()
    }

    private func deleteChannel(_ channel: AIGatewayChannel) {
        settings.aiGatewayChannels.removeAll { $0.id == channel.id }
        GatewayKeychain.removeAPIKey(for: channel.id)
        if let keyID = channel.proxy.passwordKeyID {
            GatewayKeychain.setProxyPassword("", for: keyID)
        }
        testStates[channel.id] = nil
        service.restart()
    }

    private func saveModel(_ draft: ModelDraft) {
        let alias = draft.alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return }

        var bindings = draft.bindings
        for index in bindings.indices {
            let value = bindings[index].upstreamModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            bindings[index].upstreamModel = value.isEmpty ? nil : value
        }
        let route = AIGatewayModelRoute(alias: alias, bindings: bindings)
        if let original = draft.originalAlias,
           let index = settings.aiGatewayModels.firstIndex(where: { $0.alias == original }) {
            settings.aiGatewayModels[index] = route
        } else if let index = settings.aiGatewayModels.firstIndex(where: { $0.alias == alias }) {
            settings.aiGatewayModels[index] = route
        } else {
            settings.aiGatewayModels.append(route)
        }
        editingModel = nil
    }

    private func channelEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.aiGatewayChannels.first(where: { $0.id == id })?.enabled ?? false },
            set: { value in
                guard let index = settings.aiGatewayChannels.firstIndex(where: { $0.id == id }) else { return }
                settings.aiGatewayChannels[index].enabled = value
            }
        )
    }

    private func maskedKey(_ channelID: String) -> String {
        let key = GatewayKeychain.apiKey(for: channelID)
        guard !key.isEmpty else { return "无密钥" }
        guard key.count > 8 else { return "sk-***" }
        return "\(key.prefix(3))***\(key.suffix(4))"
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 生成 `sk-calmbar-` 前缀 + 24 位小写十六进制随机密钥
    private static func randomServerKey() -> String {
        var generator = SystemRandomNumberGenerator()
        let hex = (0..<24).map { _ in String(format: "%x", Int.random(in: 0..<16, using: &generator)) }
        return "sk-calmbar-\(hex.joined())"
    }
}

// MARK: - 测试结果

private enum ChannelTestState {
    case testing
    case success(Int)
    case failure(String)
}

// MARK: - 渠道草稿与编辑弹层

private struct ChannelDraft: Identifiable {
    var channel: AIGatewayChannel
    var apiKey: String
    var proxyPassword: String
    var isNew: Bool

    var id: String { channel.id }

    init(channel: AIGatewayChannel, apiKey: String, proxyPassword: String, isNew: Bool) {
        self.channel = channel
        self.apiKey = apiKey
        self.proxyPassword = proxyPassword
        self.isNew = isNew
    }
}

private struct ChannelEditorSheet: View {
    @State private var draft: ChannelDraft
    @State private var proxyHost: String
    @State private var proxyPort: String
    @State private var proxyUsername: String

    private let onSave: (ChannelDraft) -> Void
    private let onCancel: () -> Void

    init(draft: ChannelDraft, onSave: @escaping (ChannelDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _proxyHost = State(initialValue: draft.channel.proxy.host)
        _proxyPort = State(initialValue: draft.channel.proxy.port > 0 ? String(draft.channel.proxy.port) : "")
        _proxyUsername = State(initialValue: draft.channel.proxy.username)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var protocolHint: String {
        switch draft.channel.protocolMode {
        case .auto:
            return "按客户端入口透传：/v1/chat/completions 走 Chat，/v1/responses 走 Responses"
        case .chat:
            return "上游只支持 Chat Completions，客户端必须调用 /v1/chat/completions"
        case .responses:
            return "上游只支持 Responses，客户端必须调用 /v1/responses"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.isNew ? "新增渠道" : "编辑渠道")
                .font(.system(size: 14, weight: .semibold))
                .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("名称") {
                        TextField("例如：官方 A", text: $draft.channel.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Base URL") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("https://api.example.com/v1", text: $draft.channel.baseURL)
                                .textFieldStyle(.roundedBorder)
                            Text("需填 OpenAI 兼容端点，例如百炼：https://dashscope.aliyuncs.com/compatible-mode/v1")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    field("上游模型") {
                        UpstreamModelsEditor(models: $draft.channel.models) {
                            try await fetchUpstreamModels()
                        }
                    }

                    field("协议") {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("", selection: $draft.channel.protocolMode) {
                                ForEach(AIGatewayUpstreamProtocol.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 220)
                            Text(protocolHint)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    field("API Key") {
                        SecureField(draft.isNew ? "留空表示本地上游无需鉴权" : "留空保持原值", text: $draft.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("鉴权头") {
                        Picker("", selection: $draft.channel.authHeader) {
                            ForEach(GatewayAuthHeaderStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    field("启用") {
                        Toggle("参与路由与故障切换", isOn: $draft.channel.enabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    Divider()

                    field("代理类型") {
                        Picker("", selection: $draft.channel.proxy.mode) {
                            ForEach(GatewayProxyMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    if draft.channel.proxy.mode != .direct {
                        field("代理主机") {
                            TextField("127.0.0.1", text: $proxyHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        field("代理端口") {
                            TextField("1080", text: $proxyPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                        }
                        field("代理用户名") {
                            TextField("可选", text: $proxyUsername)
                                .textFieldStyle(.roundedBorder)
                        }
                        field("代理密码") {
                            SecureField("可选", text: $draft.proxyPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if !validationMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(validationMessages, id: \.self) { message in
                                Text("· \(message)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: 460, height: 540)

            Divider()

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    draft.channel.proxy.host = proxyHost.trimmingCharacters(in: .whitespaces)
                    draft.channel.proxy.port = Int(proxyPort) ?? 0
                    draft.channel.proxy.username = proxyUsername
                    draft.channel.baseURL = normalizedBaseURL(draft.channel.baseURL)
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!validationMessages.isEmpty)
            }
            .padding(16)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 72, alignment: .leading)
                .padding(.top, 3)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var validationMessages: [String] {
        var messages: [String] = []
        let channel = draft.channel
        if channel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("渠道名称不能为空")
        }
        let urlText = normalizedBaseURL(channel.baseURL)
        if let url = URL(string: urlText),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host?.isEmpty == false,
           url.query == nil,
           url.fragment == nil {
            // 合法
        } else {
            messages.append("Base URL 必须是 http/https 地址，且不含查询参数或片段")
        }
        if channel.models.isEmpty {
            messages.append("至少添加一个上游模型")
        }
        if channel.proxy.mode != .direct {
            if proxyHost.trimmingCharacters(in: .whitespaces).isEmpty {
                messages.append("代理主机不能为空")
            }
            if let port = Int(proxyPort), (1...65535).contains(port) {
                // 合法
            } else {
                messages.append("代理端口需在 1–65535 之间")
            }
        }
        return messages
    }

    private func normalizedBaseURL(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// 用草稿中的地址与密钥探测 /models，新增渠道尚未保存也能拉取
    private func fetchUpstreamModels() async throws -> [String] {
        var probe = draft.channel
        probe.id = draft.channel.id
        probe.baseURL = normalizedBaseURL(draft.channel.baseURL)
        probe.proxy.host = proxyHost.trimmingCharacters(in: .whitespaces)
        probe.proxy.port = Int(proxyPort) ?? 0
        probe.proxy.username = proxyUsername
        let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = try await GatewayConnectionTester.fetchModels(
            channel: probe,
            apiKey: key.isEmpty ? nil : key
        )
        guard !models.isEmpty else { throw GatewayConnectionTestError.invalidModelsPayload }
        return models
    }
}

// MARK: - 模型别名草稿与编辑弹层

private struct ModelDraft: Identifiable {
    let originalAlias: String?
    /// 固定身份：新增草稿也必须在整个编辑周期内保持不变，避免 sheet(item:) 反复重建
    let id: String
    var alias: String
    var bindings: [AIGatewayModelBinding]

    init(originalAlias: String?, alias: String, bindings: [AIGatewayModelBinding]) {
        self.originalAlias = originalAlias
        self.id = originalAlias ?? "new-model-\(UUID().uuidString)"
        self.alias = alias
        self.bindings = bindings
    }

    var channelIDs: [String] { bindings.map(\.channelID) }

    mutating func toggle(channelID: String, selected: Bool) {
        if selected {
            guard !bindings.contains(where: { $0.channelID == channelID }) else { return }
            bindings.append(AIGatewayModelBinding(channelID: channelID))
        } else {
            bindings.removeAll { $0.channelID == channelID }
        }
    }
}

private struct ModelEditorSheet: View {
    @State private var draft: ModelDraft
    private let channels: [AIGatewayChannel]
    private let onSave: (ModelDraft) -> Void
    private let onCancel: () -> Void

    init(draft: ModelDraft, channels: [AIGatewayChannel], onSave: @escaping (ModelDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.channels = channels
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.originalAlias == nil ? "新增模型别名" : "编辑模型别名")
                .font(.system(size: 14, weight: .semibold))
                .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("别名")
                        .font(.system(size: 12))
                        .frame(width: 72, alignment: .leading)
                    TextField("客户端请求使用的模型名", text: $draft.alias)
                        .textFieldStyle(.roundedBorder)
                }

                Text("勾选渠道并调整顺序，顺序即故障切换的尝试顺序；上游模型默认自动（优先同名）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if channels.isEmpty {
                    Text("请先添加渠道")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(channels) { channel in
                                channelRow(channel)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460)
    }

    private func channelRow(_ channel: AIGatewayChannel) -> some View {
        let selection = draft.bindings.first { $0.channelID == channel.id }
        let order = draft.channelIDs.firstIndex(of: channel.id).map { $0 + 1 }
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selection != nil },
                set: { selected in draft.toggle(channelID: channel.id, selected: selected) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(channel.name)
                .font(.system(size: 12))
                .lineLimit(1)

            if !channel.enabled {
                Text("已禁用")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selection != nil {
                upstreamModelPicker(channel)
            }

            if let order {
                Text("#\(order)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button {
                move(channel.id, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(order == nil || order == 1)

            Button {
                move(channel.id, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(order == nil || order == draft.channelIDs.count)
        }
        .frame(minHeight: 22)
    }

    /// 逐渠道指定该别名使用的上游模型；留空自动（同名优先，否则主模型）
    private func upstreamModelPicker(_ channel: AIGatewayChannel) -> some View {
        let current = draft.bindings.first { $0.channelID == channel.id }?.upstreamModel
        var options = channel.models
        if let current, !current.isEmpty, !options.contains(current) {
            options.append(current)
        }
        return Picker("", selection: upstreamModelBinding(channel.id)) {
            Text("自动（同名优先）").tag(String?.none)
            ForEach(options, id: \.self) { model in
                Text(model).tag(String?.some(model))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .font(.system(size: 11))
        .frame(width: 150)
        .help("自动：渠道存在与别名同名的模型时用同名，否则用渠道主模型")
    }

    private func upstreamModelBinding(_ channelID: String) -> Binding<String?> {
        Binding(
            get: { draft.bindings.first { $0.channelID == channelID }?.upstreamModel },
            set: { value in
                guard let index = draft.bindings.firstIndex(where: { $0.channelID == channelID }) else { return }
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                draft.bindings[index].upstreamModel = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func move(_ id: String, by delta: Int) {
        guard let index = draft.bindings.firstIndex(where: { $0.channelID == id }) else { return }
        let target = index + delta
        guard draft.bindings.indices.contains(target) else { return }
        draft.bindings.swapAt(index, target)
    }
}

// MARK: - 上游多模型编辑器

/// 可搜索的多选上游模型编辑器：候选来自 GET <Base URL>/models，也允许手动输入
private struct UpstreamModelsEditor: View {
    @Binding var models: [String]
    let onFetch: () async throws -> [String]

    @State private var query = ""
    @State private var fetched: [String] = []
    @State private var fetchState: FetchState = .idle

    private enum FetchState: Equatable {
        case idle
        case loading
        case loaded(Int)
        case failed(String)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [String] {
        fetched.filter { model in
            !models.contains(model) && (trimmedQuery.isEmpty || model.localizedCaseInsensitiveContains(trimmedQuery))
        }
    }

    private var isLoading: Bool {
        if case .loading = fetchState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if models.isEmpty {
                Text("尚未添加模型")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(models.enumerated()), id: \.element) { index, model in
                    HStack(spacing: 6) {
                        if index == 0 {
                            Text("主")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                                .help("主模型：别名未绑定上游模型且没有同名模型时使用")
                        }
                        Text(model)
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            models.removeAll { $0 == model }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("移除该模型")
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("搜索上游模型，或直接输入后添加", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTyped() }

                Button("添加") { addTyped() }
                    .controlSize(.small)
                    .disabled(trimmedQuery.isEmpty || models.contains(trimmedQuery))

                Button {
                    Task { await refresh() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("获取模型列表")
                    }
                }
                .controlSize(.small)
                .disabled(isLoading)
                .help("请求 GET <Base URL>/models 拉取候选模型")
            }

            if !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { model in
                            Button {
                                add(model)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                    Text(model)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 96)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }

            fetchStatusView
        }
    }

    @ViewBuilder
    private var fetchStatusView: some View {
        switch fetchState {
        case .idle:
            Text("未拉取列表时可手动输入模型名；首项为主模型")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .loading:
            Text("正在请求 /models…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .loaded(let count):
            Text("已获取 \(count) 个候选模型")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("获取失败：\(message)，可手动输入")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func addTyped() {
        add(trimmedQuery)
    }

    private func add(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !models.contains(trimmed) else { return }
        models.append(trimmed)
        query = ""
    }

    private func refresh() async {
        fetchState = .loading
        do {
            let list = try await onFetch()
            fetched = list
            fetchState = .loaded(list.count)
        } catch {
            fetchState = .failed(error.localizedDescription)
        }
    }
}
