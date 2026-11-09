import AppKit
import SwiftUI

// MARK: - 偏好设置「局域网互传」Tab

public struct LANShareSettingsTab: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var service = LANShareService.shared

    @State private var serverName = ""
    @State private var portText = ""
    @State private var receiveDirectory = ""
    @State private var saveMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeatureMasterToggleCard(
                    icon: SettingsTab.lanShare.icon,
                    iconColors: SettingsTab.lanShare.gradientColors,
                    title: "启用局域网互传",
                    activeSubtitle: activeSubtitle,
                    inactiveSubtitle: "已停用 · 不监听端口，分享列表与设置保留",
                    isEnabled: $appSettings.lanShareEnabled
                )

                if let message = saveMessage {
                    warningBanner(message)
                }

                if let error = service.lastError, !service.isRunning, appSettings.lanShareEnabled {
                    warningBanner(error.userMessage)
                }

                connectionCard
                storageCard
                securityCard
                interfaceCard
                tipsCard
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .onAppear {
            syncDrafts()
        }
        .onChange(of: service.settings) { _, _ in
            syncDrafts()
        }
    }

    private var activeSubtitle: String {
        switch service.status {
        case .running:
            return "已激活 · \(service.shareURL ?? "端口 \(service.settings.port)")"
        case .starting:
            return "正在启动服务"
        case .restricted:
            return "已启用 · 等待网络连接"
        case .failed:
            return "已启用 · 服务启动失败"
        case .stopped:
            return "已启用 · 服务未运行"
        }
    }

    // MARK: - 连接信息

    private var connectionCard: some View {
        card(title: "连接信息") {
            HStack(spacing: 8) {
                Text("分享地址")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(service.shareURL ?? "服务未运行")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("复制") {
                    service.copyShareLink()
                }
                .controlSize(.small)
                .disabled(service.shareURL == nil)
            }

            if let prefix = service.networkPrefix {
                HStack(spacing: 8) {
                    Text("当前网段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(prefix)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Text("服务器名称")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                TextField("在对方网页上显示的名称", text: $serverName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit { save() }
                Button("保存") { save() }
                    .controlSize(.small)
                Spacer()
            }
        }
    }

    // MARK: - 接收目录与端口

    private var storageCard: some View {
        card(title: "接收与端口") {
            HStack(spacing: 8) {
                Text("接收目录")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(receiveDirectory)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(receiveDirectory)
                Spacer()
                Button("选择…") { chooseDirectory() }
                    .controlSize(.small)
                Button("打开") { service.openReceiveDirectory() }
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Text("监听端口")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                TextField("47820", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit { save() }
                Button("应用") { save() }
                    .controlSize(.small)
                Text("默认 47820，被占用时自动依次尝试 47821–47829")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - 访问安全

    private var securityCard: some View {
        card(title: "访问安全") {
            Toggle("需要 6 位口令才能访问", isOn: passcodeBinding)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack(spacing: 8) {
                Text(service.hasPasscode ? "已设置访问口令" : "尚未设置访问口令")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if let code = service.passcodeToShowOnce {
                    Text("当前口令：\(code)")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button(service.hasPasscode ? "重置口令" : "生成口令") {
                    service.setPasscode(nil)
                }
                .controlSize(.small)

                if service.hasPasscode {
                    Button("清除") {
                        service.clearPasscode()
                    }
                    .controlSize(.small)
                }
            }

            Toggle("允许对方上传文件与发送文本", isOn: uploadBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: - 网络接口

    private var interfaceCard: some View {
        card(title: "网络接口") {
            HStack(spacing: 8) {
                Text("监听网卡")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)

                Picker("", selection: interfaceBinding) {
                    Text("自动选择").tag("")
                    ForEach(availableInterfaces, id: \.interfaceName) { address in
                        Text("\(address.interfaceName) · \(address.address)")
                            .tag(address.interfaceName)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 300)

                Spacer()
            }

            Text("默认仅允许所选网段内的设备访问，访客网络与跨网段设备会被拒绝。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 使用提示

    private var tipsCard: some View {
        card(title: "使用提示") {
            Text("· 手机与 Mac 连接同一 Wi-Fi 后，用浏览器打开分享链接即可下载或上传。")
            Text("· 分享链接中的令牌只在本机服务运行期间有效，重启后需要重新获取链接。")
            Text("· 若系统首次弹出「本地网络」授权提示，请选择允许，否则其他设备无法访问。")
            Text("· 关闭「允许上传」后，对方只能查看与下载，不能回传文件或文本。")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    // MARK: - 绑定

    private var passcodeBinding: Binding<Bool> {
        Binding(
            get: { service.settings.passcodeEnabled },
            set: { newValue in
                var updated = service.settings
                updated.passcodeEnabled = newValue
                apply(updated)
            }
        )
    }

    private var uploadBinding: Binding<Bool> {
        Binding(
            get: { service.settings.allowUpload },
            set: { newValue in
                var updated = service.settings
                updated.allowUpload = newValue
                apply(updated)
            }
        )
    }

    private var interfaceBinding: Binding<String> {
        Binding(
            get: { service.settings.selectedInterface ?? "" },
            set: { newValue in
                var updated = service.settings
                updated.selectedInterface = newValue.isEmpty ? nil : newValue
                apply(updated)
            }
        )
    }

    private var availableInterfaces: [LANShareNetworkAddress] {
        let addresses = service.availableAddresses.filter { !$0.isLinkLocal && !$0.isVirtual }
        let ipv4 = addresses.filter { $0.family == .ipv4 }
        return ipv4.isEmpty ? addresses : ipv4
    }

    // MARK: - 读写

    private func syncDrafts() {
        serverName = service.settings.serverName
        portText = String(service.settings.port)
        receiveDirectory = service.settings.receiveDirectory
    }

    private func save() {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)) else {
            saveMessage = LANShareError.invalidPort.userMessage
            return
        }
        var updated = service.settings
        updated.serverName = serverName
        updated.port = port
        updated.receiveDirectory = receiveDirectory
        apply(updated)
    }

    private func apply(_ settings: LANShareSettings) {
        if let error = service.updateSettings(settings) {
            saveMessage = error.userMessage
        } else {
            saveMessage = nil
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择接收目录"
        panel.directoryURL = URL(fileURLWithPath: receiveDirectory, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        receiveDirectory = url.path
        save()
    }

    // MARK: - 视图工具

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }
}
