import AppKit
import Combine
import Foundation
import Vision

@MainActor
public final class ClipboardMonitor: ObservableObject {
    public static let shared = ClipboardMonitor()

    @Published public var isMonitoring: Bool = false
    @Published public var lastCopiedItem: ClipboardItem?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.lastChangeCount = pasteboard.changeCount

        // Observe settings changes
        AppSettings.shared.$clipboardHistoryEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        // Observe operational states (screen sleep, lock, wake)
        SystemEventCoordinator.shared.$isOperational
            .receive(on: RunLoop.main)
            .sink { [weak self] operational in
                guard let self = self else { return }
                guard AppSettings.shared.clipboardHistoryEnabled else { return }
                if operational {
                    self.startTimer()
                } else {
                    self.stopTimer()
                }
            }
            .store(in: &cancellables)

        if AppSettings.shared.clipboardHistoryEnabled {
            startMonitoring()
        }
    }

    public func startMonitoring() {
        self.lastChangeCount = pasteboard.changeCount
        self.isMonitoring = true
        if SystemEventCoordinator.shared.isOperational {
            startTimer()
        }
    }

    public func stopMonitoring() {
        self.isMonitoring = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        self.lastChangeCount = pasteboard.changeCount
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }

    // MARK: - Change Detection & Ingestion

    @objc private func checkForChanges() {
        guard isMonitoring else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let settings = AppSettings.shared
        guard settings.clipboardHistoryEnabled else { return }

        // 获取前台应用 Bundle ID
        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        guard let pbItem = pasteboard.pasteboardItems?.first else { return }

        // 安全过滤
        if ClipboardSecurityFilter.shouldIgnore(
            item: pbItem,
            sourceAppBundle: sourceApp,
            userIgnoredApps: settings.clipboardIgnoredApps,
            filterSensitive: settings.clipboardFilterSensitive
        ) {
            return
        }

        // 解析并创建记录
        if let (createdItem, imageToOCR) = extractClipboardItem(from: pbItem, sourceAppBundle: sourceApp) {
            self.lastCopiedItem = createdItem
            let targetId = ClipboardHistoryManager.shared.add(item: createdItem, maxCount: settings.clipboardMaxCount)
            if let img = imageToOCR {
                performImageOCR(image: img, itemId: targetId)
            }
        }
    }

    // MARK: - Extract Content Types

    private func extractClipboardItem(from item: NSPasteboardItem, sourceAppBundle: String?) -> (item: ClipboardItem, imageForOCR: NSImage?)? {
        let types = item.types
        let settings = AppSettings.shared

        // 1. 检查是否为文件 URL (若文件均为图片格式，优先归类为 .image 并生成缩略图)
        if types.contains(.fileURL) {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                let paths = urls.map { $0.path }
                let imageExts: Set<String> = [
                    "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "svg", "ico", "icns"
                ]
                let isAllImageFiles = urls.allSatisfy { imageExts.contains($0.pathExtension.lowercased()) }

                if isAllImageFiles, settings.clipboardSaveImages, let firstURL = urls.first {
                    if let nsImage = NSImage(contentsOf: firstURL) {
                        let filename = "img_\(UUID().uuidString).png"
                        let fileURL = ClipboardHistoryManager.shared.imagesDirectoryURL.appendingPathComponent(filename)

                        if let tiffRepresentation = nsImage.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
                           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                            try? pngData.write(to: fileURL)
                        } else if let tiffData = nsImage.tiffRepresentation {
                            try? tiffData.write(to: fileURL)
                        }

                        let width = Int(nsImage.size.width)
                        let height = Int(nsImage.size.height)
                        let dimensions = (width > 0 && height > 0) ? "\(width) × \(height)" : ""
                        let title = urls.count == 1
                            ? (dimensions.isEmpty ? firstURL.lastPathComponent : "\(firstURL.lastPathComponent) (\(dimensions))")
                            : "\(urls.count) 张图片 (\(firstURL.lastPathComponent)...)"

                        let clipboardItem = ClipboardItem(
                            type: .image,
                            title: title,
                            textValue: paths.joined(separator: "\n"),
                            imageFileName: filename,
                            fileURLs: paths,
                            sourceAppBundle: sourceAppBundle
                        )

                        return (clipboardItem, nsImage)
                    }
                }

                // 常规非图片文件
                let title = urls.map { $0.lastPathComponent }.joined(separator: ", ")
                let clipboardItem = ClipboardItem(
                    type: .fileURL,
                    title: title,
                    textValue: paths.joined(separator: "\n"),
                    fileURLs: paths,
                    sourceAppBundle: sourceAppBundle
                )
                return (clipboardItem, nil)
            }
        }

        // 2. 检查是否为图片 (截图、复制图像、各类图片格式)
        if settings.clipboardSaveImages {
            var foundImage: NSImage?

            // A. 从 NSPasteboardItem 中按类型匹配数据
            for imgType in ClipboardSecurityFilter.imageTypes {
                if types.contains(imgType), let data = item.data(forType: imgType), let img = NSImage(data: data) {
                    foundImage = img
                    break
                }
            }

            // B. 尝试通过 NSPasteboard 原生读取 NSImage (处理各类第三方应用截图与图片复制)
            if foundImage == nil {
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let first = images.first {
                    foundImage = first
                } else if let pbImage = NSImage(pasteboard: pasteboard) {
                    foundImage = pbImage
                }
            }

            if let nsImage = foundImage {
                let filename = "img_\(UUID().uuidString).png"
                let fileURL = ClipboardHistoryManager.shared.imagesDirectoryURL.appendingPathComponent(filename)

                // 保存 PNG 至缓存目录
                if let tiffRepresentation = nsImage.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                } else if let tiffData = nsImage.tiffRepresentation {
                    try? tiffData.write(to: fileURL)
                }

                let width = Int(nsImage.size.width)
                let height = Int(nsImage.size.height)
                let dimensions = (width > 0 && height > 0) ? "\(width) × \(height)" : ""
                let title = dimensions.isEmpty ? "图片" : "图片 (\(dimensions))"

                let clipboardItem = ClipboardItem(
                    type: .image,
                    title: title,
                    imageFileName: filename,
                    sourceAppBundle: sourceAppBundle
                )

                return (clipboardItem, nsImage)
            }
        }

        // 3. 检查富文本 (RTF / HTML)
        let rtfData = item.data(forType: .rtf)
        let htmlData = item.data(forType: .html)
        let stringVal = item.string(forType: .string)

        if let string = stringVal, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

            // URL 判断
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                let title = trimmed.count > 120 ? String(trimmed.prefix(120)) + "..." : trimmed
                let clipboardItem = ClipboardItem(
                    type: .url,
                    title: title,
                    textValue: trimmed,
                    sourceAppBundle: sourceAppBundle
                )
                return (clipboardItem, nil)
            }

            // 颜色 HEX 码判断 (例如 #FFFFFF, #3B82F6)
            if trimmed.hasPrefix("#") && (trimmed.count == 7 || trimmed.count == 4 || trimmed.count == 9) {
                let clipboardItem = ClipboardItem(
                    type: .color,
                    title: trimmed.uppercased(),
                    textValue: trimmed.uppercased(),
                    sourceAppBundle: sourceAppBundle
                )
                return (clipboardItem, nil)
            }

            // 富文本判断
            if rtfData != nil || htmlData != nil {
                let previewTitle = generateTextTitle(from: trimmed)
                let clipboardItem = ClipboardItem(
                    type: .richText,
                    title: previewTitle,
                    textValue: trimmed,
                    rtfData: rtfData,
                    htmlData: htmlData,
                    sourceAppBundle: sourceAppBundle
                )
                return (clipboardItem, nil)
            }

            // 普通纯文本
            let previewTitle = generateTextTitle(from: trimmed)
            let clipboardItem = ClipboardItem(
                type: .text,
                title: previewTitle,
                textValue: trimmed,
                sourceAppBundle: sourceAppBundle
            )
            return (clipboardItem, nil)
        }

        return nil
    }

    private func generateTextTitle(from text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.count > 100 {
            return String(singleLine.prefix(100)) + "..."
        }
        return singleLine
    }

    // MARK: - Vision Image OCR & Barcode Indexing

    nonisolated private static func getCGImage(from image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        if let tiff = image.tiffRepresentation,
           let source = CGImageSourceCreateWithData(tiff as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return nil
    }

    nonisolated private static func isNoiseString(_ str: String) -> Bool {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.count <= 1 {
            return !trimmed.allSatisfy { $0.isLetter || $0.isNumber }
        }
        // 如果包含中文字符，绝对不是噪点
        let containsChinese = trimmed.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
        if containsChinese {
            return false
        }
        let total = Double(trimmed.count)
        let symbols = Double(trimmed.filter { "*#^~|\\_`\"'[]{}<>/?;:$%&".contains($0) }.count)
        return (symbols / total) > 0.20
    }

    private func performImageOCR(image: NSImage, itemId: UUID) {
        guard let cgImage = Self.getCGImage(from: image) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var barcodeBoxes: [CGRect] = []
            var recognizedBarcodes: [String] = []
            var recognizedTexts: [String] = []

            // 1. 先进行二维码与条形码识别
            let barcodeRequest = VNDetectBarcodesRequest { req, _ in
                guard let observations = req.results as? [VNBarcodeObservation] else { return }
                for observation in observations {
                    barcodeBoxes.append(observation.boundingBox)
                    if let payload = observation.payloadStringValue, !payload.isEmpty {
                        recognizedBarcodes.append(payload)
                    }
                }
            }
            barcodeRequest.symbologies = [.qr, .aztec, .dataMatrix, .code128, .code39, .code93, .ean8, .ean13, .pdf417, .upce]

            try? requestHandler.perform([barcodeRequest])

            // 2. 高精度文字识别（支持简体中文、繁体中文、英文）
            let textRequest = VNRecognizeTextRequest { req, _ in
                guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
                for obs in observations {
                    if obs.confidence < 0.20 { continue }

                    // 过滤位于二维码区域内的噪点假文字（二维码黑白网格常被误识别为 ASCII 符号乱码）
                    let overlapsBarcode = barcodeBoxes.contains { box in
                        box.insetBy(dx: -0.05, dy: -0.05).intersects(obs.boundingBox)
                    }
                    if overlapsBarcode { continue }

                    if let top = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                       !top.isEmpty,
                       !Self.isNoiseString(top) {
                        recognizedTexts.append(top)
                    }
                }
            }

            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            try? requestHandler.perform([textRequest])

            var resultSections: [String] = []
            if !recognizedTexts.isEmpty {
                resultSections.append(recognizedTexts.joined(separator: "\n"))
            }
            if !recognizedBarcodes.isEmpty {
                for code in recognizedBarcodes {
                    resultSections.append("[二维码: \(code)]")
                }
            }

            let fullResult = resultSections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !fullResult.isEmpty {
                Task { @MainActor in
                    ClipboardHistoryManager.shared.updateOCRText(id: itemId, text: fullResult)
                }
            }
        }
    }
}
