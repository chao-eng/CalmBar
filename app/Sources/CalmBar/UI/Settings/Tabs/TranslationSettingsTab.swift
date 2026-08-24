import SwiftUI
import CalmBarKit

public struct TranslationSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var translationManager = TranslationManager.shared
    @ObservedObject private var translationHistory = TranslationHistoryManager.shared

    @State private var isTestingTranslation = false
    @State private var testTranslationResult: String?
    @State private var testTranslationError: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .translation)

                // 1. 服务端接口与连接配置
                GroupBox(label: Label("HTTP OpenAI 兼容服务端配置 (如 HY-MT2 / Ollama / vLLM)", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("启用 AI 划词翻译")
                                    .font(.system(size: 12, weight: .medium))
                                Text("开启后可通过双击 ⌘+C、全局快捷键 ⌥⌘T 或 OCR 联动直接调用 AI 模型翻译。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.translationEnabled)
                                .labelsHidden()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API 基础地址 (Base URL):")
                                .font(.system(size: 12, weight: .medium))
                            TextField("例如 http://10.0.8.2:8000/v1 或 https://api.openai.com/v1", text: $settings.translationAPIBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("模型名称 (Model Name):")
                                    .font(.system(size: 12, weight: .medium))
                                TextField("Hy-MT2", text: $settings.translationModel)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("API Key (可选，无鉴权可留空):")
                                    .font(.system(size: 12, weight: .medium))
                                SecureField("sk-...", text: $settings.translationAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }

                        Divider()

                        HStack {
                            Button(action: runTranslationConnectionTest) {
                                HStack(spacing: 6) {
                                    if isTestingTranslation {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.horizontal.fill")
                                    }
                                    Text(isTestingTranslation ? "正在测试连接..." : "测试连接")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isTestingTranslation)

                            Spacer()

                            if let res = testTranslationResult {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(res)
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                }
                            } else if let err = testTranslationError {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(err)
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 2. 语言与提示词偏好
                GroupBox(label: Label("多语言与提示词偏好 (支持 38 种语言)", systemImage: "globe")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("默认目标翻译语言")
                                    .font(.system(size: 12, weight: .medium))
                                Text("默认翻译输出语言，支持藏语、维吾尔语、粤语、哈萨克语等 38 种语言体系。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.translationTargetLanguageCode) {
                                ForEach(TranslationLanguage.supportedLanguages) { lang in
                                    Text(lang.displayName).tag(lang.code)
                                }
                            }
                            .frame(width: 220)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("自定义 Prompt 提示词模板 (可选，留空使用 HY-MT2 默认规范):")
                                .font(.system(size: 12, weight: .medium))
                            Text("支持占位符: {targetLanguage} (英文名), {targetLanguageZH} (中文名), {text} (原文)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField("Translate the following segment into {targetLanguage}, without additional explanation: {text}", text: $settings.translationCustomPrompt)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 3. 交互与触发设置 (Double ⌘+C & Hotkey)
                GroupBox(label: Label("触发交互与浮窗行为 (参考 cctrans)", systemImage: "hand.tap.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("开启双击 ⌘+C (Double Copy) 划词就地翻译", isOn: $settings.translationDoubleCopyEnabled)

                        if settings.translationDoubleCopyEnabled {
                            HStack {
                                Text("双击判断时间阈值:")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)
                                Slider(value: $settings.translationDoubleCopyInterval, in: 0.4...1.5, step: 0.1)
                                Text(String(format: "%.1f 秒", settings.translationDoubleCopyInterval))
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 50, alignment: .trailing)
                            }
                            .padding(.leading, 18)
                        }

                        Divider()

                        Toggle("翻译浮窗自动倒计时消失", isOn: $settings.translationAutoDismiss)

                        if settings.translationAutoDismiss {
                            HStack {
                                Text("自动消失延迟:")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)
                                Slider(value: $settings.translationAutoDismissDelay, in: 3.0...20.0, step: 1.0)
                                Text(String(format: "%.0f 秒", settings.translationAutoDismissDelay))
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 50, alignment: .trailing)
                            }
                            .padding(.leading, 18)
                        }

                        Divider()

                        HStack {
                            Text("全局快捷键: **⌥⌘T** (翻译剪贴板/选区文本)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 4. 历史记录管理
                GroupBox(label: Label("历史归档与操作", systemImage: "clock.arrow.circlepath")) {
                    HStack(spacing: 12) {
                        Button(action: {
                            TranslationHistoryWindowController.shared.show()
                        }) {
                            Label("打开翻译历史窗口", systemImage: "macwindow.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(action: {
                            translationManager.translateFromClipboard()
                        }) {
                            Label("立即翻译剪贴板", systemImage: "character.bubble")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        if !translationHistory.history.isEmpty {
                            Button(role: .destructive, action: {
                                translationHistory.clearAll()
                            }) {
                                Label("清空历史 (\(translationHistory.history.count) 条)", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private func runTranslationConnectionTest() {
        isTestingTranslation = true
        testTranslationResult = nil
        testTranslationError = nil

        Task {
            do {
                let res = try await TranslationService.shared.testConnection(
                    baseURL: settings.translationAPIBaseURL,
                    apiKey: settings.translationAPIKey.isEmpty ? nil : settings.translationAPIKey,
                    model: settings.translationModel
                )
                await MainActor.run {
                    self.isTestingTranslation = false
                    self.testTranslationResult = "连接成功 (\(res.latencyMs)ms): \(res.sampleResponse.prefix(20))"
                }
            } catch {
                await MainActor.run {
                    self.isTestingTranslation = false
                    self.testTranslationError = error.localizedDescription
                }
            }
        }
    }
}
