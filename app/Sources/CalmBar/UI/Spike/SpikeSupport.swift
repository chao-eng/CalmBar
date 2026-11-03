import AppKit

// Spike 专用落盘日志与窗口自截图，供 tabbar / height 两种模式共用
enum SpikeTrace {
    static func log(_ message: String, mode: String) {
        let path = "/tmp/calmbar_spike_\(mode).log"
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

    // 终端无屏幕录制权限时 screencapture 取不到其他 App 窗口，改为窗口自截图
    @MainActor
    @discardableResult
    static func capture(_ window: NSWindow, to path: String, mode: String) -> Bool {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            log("自截图失败：无法创建位图 path=\(path)", mode: mode)
            return false
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("自截图失败：无法编码 PNG path=\(path)", mode: mode)
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            log("自截图已保存 path=\(path) size=\(rep.pixelsWide)x\(rep.pixelsHigh)", mode: mode)
            return true
        } catch {
            log("自截图写入失败: \(error)", mode: mode)
            return false
        }
    }
}
