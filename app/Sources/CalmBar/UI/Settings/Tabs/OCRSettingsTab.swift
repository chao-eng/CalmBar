import SwiftUI
import CalmBarKit

public struct OCRSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var ocrManager = OCRManager.shared
    @ObservedObject private var ocrHistory = OCRHistoryManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeaderView(tab: .ocr)

                // 1. 识别引擎与精度
                GroupBox(label: Label("识别引擎与精度配置", systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("高精度识别模式 (深度学习神经网络)")
                                    .font(.system(size: 12, weight: .medium))
                                Text("开启后调用 Apple Vision 精准模型，对中英文混排、模糊小字等场景识别更精准。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.ocrQualityAccurate)
                                .labelsHidden()
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("目标识别语言")
                                    .font(.system(size: 12, weight: .medium))
                                Text("指定优先识别的语言，默认自动适配中英文。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.ocrLanguageCode) {
                                Text("自动识别 (中/英)").tag("auto")
                                Text("简体中文 (zh-Hans)").tag("zh-Hans")
                                Text("繁体中文 (zh-Hant)").tag("zh-Hant")
                                Text("英语 (en-US)").tag("en-US")
                                Text("日语 (ja)").tag("ja")
                                Text("韩语 (ko)").tag("ko")
                            }
                            .frame(width: 170)
                        }

                        Divider()

                        Toggle("保留原始换行符 (关闭后自动转为空格单行)", isOn: $settings.ocrKeepLineBreaks)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 2. 识别后自动化行为
                GroupBox(label: Label("自动化与交互动作", systemImage: "bolt.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("识别成功后自动写入系统剪贴板", isOn: $settings.ocrAutoCopyToClipboard)
                        Toggle("识别完成后播放提示音效", isOn: $settings.ocrPlaySound)
                        Toggle("识别完成后弹出半透明悬浮预览窗口", isOn: $settings.ocrShowFloatingPreview)

                        if settings.ocrShowFloatingPreview {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()

                                Toggle("悬浮预览窗口自动倒计时消失", isOn: $settings.ocrAutoDismiss)
                                    .padding(.leading, 12)

                                if settings.ocrAutoDismiss {
                                    HStack {
                                        Text("自动消失倒计时")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("", selection: $settings.ocrAutoDismissDelay) {
                                            Text("5 秒").tag(5.0)
                                            Text("8 秒").tag(8.0)
                                            Text("10 秒").tag(10.0)
                                            Text("15 秒").tag(15.0)
                                            Text("30 秒").tag(30.0)
                                            Text("60 秒").tag(60.0)
                                        }
                                        .frame(width: 100)
                                    }
                                    .padding(.leading, 24)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 3. 历史记录归档与管理
                GroupBox(label: Label("历史归档与管理", systemImage: "clock.arrow.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("最大历史记录保留条数")
                                    .font(.system(size: 12, weight: .medium))
                                Text("当前已存储 \(ocrHistory.items.count) 条识别记录。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.ocrMaxHistoryCount) {
                                Text("50 条").tag(50)
                                Text("100 条").tag(100)
                                Text("200 条").tag(200)
                                Text("500 条").tag(500)
                            }
                            .frame(width: 110)
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button(action: {
                                OCRHistoryWindowController.shared.show()
                            }) {
                                Label("打开历史记录独立窗口", systemImage: "macwindow.on.rectangle")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(action: {
                                ocrManager.startCaptureAndRecognize()
                            }) {
                                Label("立即框选识别", systemImage: "text.viewfinder")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            if !ocrHistory.items.isEmpty {
                                Button(role: .destructive, action: {
                                    ocrHistory.clearAll()
                                }) {
                                    Label("清空历史", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}
