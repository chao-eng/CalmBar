import AppKit

// MARK: - M1 骨架落盘日志与窗口自截图

enum M1Trace {
    private static var logPath: String {
        let args = CommandLine.arguments
        if args.contains("--visual") { return "/tmp/calmbar_visual.log" }
        if args.contains("--m8") { return "/tmp/calmbar_m8.log" }
        if args.contains("--m7") || args.contains("--m7-empty") { return "/tmp/calmbar_m7.log" }
        if args.contains("--m6") || args.contains("--m6-empty") { return "/tmp/calmbar_m6.log" }
        if args.contains("--m5") || args.contains("--m5-stress") { return "/tmp/calmbar_m5.log" }
        if args.contains("--m4") { return "/tmp/calmbar_m4.log" }
        if args.contains("--m3") { return "/tmp/calmbar_m3.log" }
        if args.contains("--m2") { return "/tmp/calmbar_m2.log" }
        return "/tmp/calmbar_m1.log"
    }

    static func log(_ message: String) {
        let path = logPath
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    @discardableResult
    static func capture(_ window: NSWindow, to path: String) -> Bool {
        guard let view = window.contentView else {
            log("capture failed: no bitmap path=\(path)")
            return false
        }
        // 按屏幕缩放倍率渲染，Retina 下输出 2x 位图，避免文字发虚
        let scale = max(window.backingScaleFactor, 2)
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            log("capture failed: no bitmap path=\(path)")
            return false
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("capture failed: png encode path=\(path)")
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            log("screenshot saved path=\(path) size=\(rep.pixelsWide)x\(rep.pixelsHigh)")
            return true
        } catch {
            log("capture write failed: \(error)")
            return false
        }
    }
}
