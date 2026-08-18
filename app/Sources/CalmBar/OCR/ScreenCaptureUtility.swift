import AppKit
import Foundation

public enum ScreenCaptureUtility {
    /// 调起 macOS 原生交互式截图工具 (/usr/sbin/screencapture -cix)
    /// - Parameter completion: 截图完成回调（主线程返回 NSImage）
    public static func captureSelection(completion: @escaping @MainActor (NSImage?) -> Void) {
        let initialChangeCount = NSPasteboard.general.changeCount

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -c: 存入剪贴板, -i: 交互选区, -x: 静音
            process.arguments = ["-cix"]

            process.terminationHandler = { proc in
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    // 用户正常截屏完成时 terminationStatus == 0 且剪贴板发生了更新
                    if proc.terminationStatus == 0 && pasteboard.changeCount != initialChangeCount,
                       let image = pasteboard.readObjects(forClasses: [NSImage.self], options: [:])?.first as? NSImage {
                        completion(image)
                    } else {
                        // 用户按 ESC 取消框选或未能捕获到新图片
                        completion(nil)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
