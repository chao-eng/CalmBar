import SwiftUI

public struct NewAgentSheetView: View {
    public let onDismiss: () -> Void
    public let onCreated: () -> Void

    @State private var label: String = "com.mycompany.service"
    @State private var scope: LaunchScope = .userAgent
    @State private var programArguments: String = "/usr/local/bin/my-script --start"
    @State private var workingDirectory: String = ""
    @State private var runAtLoad: Bool = true
    @State private var keepAlive: Bool = true
    @State private var enableLogging: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    public init(onDismiss: @escaping () -> Void, onCreated: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.onCreated = onCreated
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("新建自启服务项 (LaunchAgent)")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
            .padding(14)
            .background(.ultraThinMaterial)

            Divider()

            // Form
            Form {
                Section {
                    Picker("安装作用域", selection: $scope) {
                        Text("当前用户自启 (~/Library/LaunchAgents)").tag(LaunchScope.userAgent)
                        Text("全局所有用户 (/Library/LaunchAgents)").tag(LaunchScope.systemAgent)
                    }

                    TextField("唯一标识 (Label):", text: $label)
                        .textFieldStyle(.roundedBorder)

                    TextField("运行命令与参数:", text: $programArguments)
                        .textFieldStyle(.roundedBorder)
                        .help("多个参数以空格分隔，首项为可执行文件完整路径")

                    TextField("工作目录 (可选):", text: $workingDirectory)
                        .textFieldStyle(.roundedBorder)
                }

                Section("生命周期与守护") {
                    Toggle("开机登录时自动载入 (RunAtLoad)", isOn: $runAtLoad)
                    Toggle("崩溃或意外退出后自动重启 (KeepAlive)", isOn: $keepAlive)
                    Toggle("自动配置日志重定向 (~/Library/Logs/CalmBar/)", isOn: $enableLogging)
                }

                if let error = errorMessage {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .padding(12)

            Divider()

            // Footer
            HStack {
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建并装载") {
                    createAndBootstrap()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty ||
                          programArguments.trimmingCharacters(in: .whitespaces).isEmpty ||
                          isSubmitting)
            }
            .padding(14)
            .background(.ultraThinMaterial)
        }
        .frame(width: 520, height: 420)
    }

    private func createAndBootstrap() {
        isSubmitting = true
        errorMessage = nil

        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        // 按引号规则拆分参数，避免含空格的路径被错误切分
        let args = LaunchPlistService.tokenizeArguments(programArguments)

        guard let targetDir = scope.directoryURL else {
            errorMessage = "作用域目录不可用"
            isSubmitting = false
            return
        }

        let targetURL = targetDir.appendingPathComponent("\(trimmedLabel).plist")

        var dict: [String: Any] = [
            "Label": trimmedLabel,
            "ProgramArguments": args,
            "RunAtLoad": runAtLoad,
            "KeepAlive": keepAlive
        ]

        if !workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty {
            dict["WorkingDirectory"] = workingDirectory.trimmingCharacters(in: .whitespaces)
        }

        if enableLogging {
            let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CalmBar")
            dict["StandardOutPath"] = logsDir.appendingPathComponent("\(trimmedLabel).stdout.log").path
            dict["StandardErrorPath"] = logsDir.appendingPathComponent("\(trimmedLabel).stderr.log").path
        }

        Task {
            do {
                try LaunchPlistService.shared.writeDictionary(dict, to: targetURL)
                try await LaunchctlService.shared.bootstrap(targetURL, scope: scope)
                await LaunchManager.shared.refreshAll()
                onCreated()
                onDismiss()
            } catch {
                self.errorMessage = "创建失败: \(error.localizedDescription)"
                self.isSubmitting = false
            }
        }
    }
}
