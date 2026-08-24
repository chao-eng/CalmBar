import AppKit
import Foundation
import Vision
import Combine

@MainActor
public final class OCRManager: ObservableObject {
    public static let shared = OCRManager()

    @Published public var isRecognizing: Bool = false
    @Published public var latestResult: OCRItem?
    @Published public var statusMessage: String?

    private init() {}

    /// 触发交互式截屏并进行文字与二维码识别
    public func startCaptureAndRecognize(completion: ((OCRItem?) -> Void)? = nil) {
        guard AppSettings.shared.ocrEnabled else {
            completion?(nil)
            return
        }

        // 1. 先收起菜单栏主面板，避免遮挡用户想要框选的屏幕区域
        StatusBarManager.shared.closePopover()

        self.statusMessage = "请在屏幕上框选识别区域..."

        // 2. 稍微延迟 150ms 等待 macOS 完成 Popover 收起淡出动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureUtility.captureSelection { [weak self] capturedImage in
                guard let self = self else { return }
                guard let image = capturedImage else {
                    self.statusMessage = nil
                    completion?(nil)
                    return
                }

                Task {
                    let item = await self.recognize(image: image)
                    completion?(item)
                }
            }
        }
    }

    /// 执行图像识别流水线 (Vision Text + Barcode)
    public func recognize(image: NSImage) async -> OCRItem? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            self.statusMessage = "无法读取图片数据"
            return nil
        }

        self.isRecognizing = true
        self.statusMessage = "正在识别中..."

        let settings = AppSettings.shared
        let keepLineBreaks = settings.ocrKeepLineBreaks
        let languageCode = settings.ocrLanguageCode

        let result: (text: String, isBarcode: Bool) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                var recognizedTexts: [String] = []
                var recognizedBarcodes: [String] = []

                // 1. 文字识别请求
                let textRequest = VNRecognizeTextRequest { request, _ in
                    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                    for observation in observations {
                        if let top = observation.topCandidates(1).first?.string, !top.isEmpty {
                            recognizedTexts.append(top)
                        }
                    }
                }
                
                // 开启自动语言探测（macOS 13+）
                if #available(macOS 13.0, *) {
                    textRequest.automaticallyDetectsLanguage = true
                }
                
                // 中文识别与中英混排必须使用 .accurate 高精模型
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true
                
                if languageCode == "auto" || languageCode.isEmpty {
                    // 默认配置支持简体中文、繁体中文、英语、日语等混合排版识别
                    textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"]
                } else if languageCode == "en-US" {
                    textRequest.recognitionLanguages = ["en-US"]
                } else {
                    // 指定特定语言时，加入 en-US 支持混排代码与英文单词
                    textRequest.recognitionLanguages = [languageCode, "en-US"]
                }

                // 2. 条码与二维码识别请求
                let barcodeRequest = VNDetectBarcodesRequest { request, _ in
                    guard let observations = request.results as? [VNBarcodeObservation] else { return }
                    for observation in observations {
                        if let val = observation.payloadStringValue, !val.isEmpty {
                            recognizedBarcodes.append(val)
                        }
                    }
                }

                do {
                    try requestHandler.perform([textRequest, barcodeRequest])
                } catch {
                    // Vision 识别发生异常
                }

                let separator = keepLineBreaks ? "\n" : " "
                let combinedText = (recognizedTexts + recognizedBarcodes).joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                let isBarcodeOnly = recognizedTexts.isEmpty && !recognizedBarcodes.isEmpty

                continuation.resume(returning: (combinedText, isBarcodeOnly))
            }
        }

        self.isRecognizing = false
        self.statusMessage = nil

        guard !result.text.isEmpty else {
            self.statusMessage = "未识别到有效文字或二维码"
            return nil
        }

        let itemType: OCRType = result.isBarcode ? .barcode : .text
        let item = OCRItem(text: result.text, type: itemType)
        self.latestResult = item

        // 1. 自动写入剪贴板
        if settings.ocrAutoCopyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
        }

        // 2. 保存到历史记录 (传入相同的 item 实例以保证 UUID 统一)
        OCRHistoryManager.shared.add(item: item, maxCount: settings.ocrMaxHistoryCount)

        // 3. 播放提示音效
        if settings.ocrPlaySound {
            NSSound(named: "Tink")?.play()
        }

        // 4. 弹出悬浮预览窗口
        if settings.ocrShowFloatingPreview {
            OCRFloatingPreviewController.shared.show(item: item)
        }

        return item
    }
}
