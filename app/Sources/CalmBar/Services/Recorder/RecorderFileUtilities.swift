import Foundation

/// 录制文件命名工具：正式成片与 .partial 恢复共用。
enum RecorderFileUtilities {
    /// 把 source 移动到 preferred 位置；若 preferred 已存在，则依次尝试
    /// `name (1).ext`、`name (2).ext`，绝不覆盖已有成片。
    static func moveToUniqueDestination(from source: URL, preferred: URL) throws -> URL {
        let directory = preferred.deletingLastPathComponent()
        let stem = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension

        for index in 0..<1000 {
            let candidate: URL
            if index == 0 {
                candidate = preferred
            } else {
                let name = ext.isEmpty
                    ? "\(stem) (\(index))"
                    : "\(stem) (\(index)).\(ext)"
                candidate = directory.appendingPathComponent(name)
            }
            guard !FileManager.default.fileExists(atPath: candidate.path) else { continue }
            do {
                try FileManager.default.moveItem(at: source, to: candidate)
                return candidate
            } catch let error as NSError where error.code == NSFileWriteFileExistsError {
                // 竞态下目标被其他进程占用，继续尝试下一个编号。
                continue
            }
        }

        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteFileExistsError,
            userInfo: [NSLocalizedDescriptionKey: "同名录制文件过多，无法生成新文件名"]
        )
    }
}
