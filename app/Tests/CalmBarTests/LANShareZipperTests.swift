import Foundation
import Testing
@testable import CalmBar

@Suite("LANShare Zipper")
struct LANShareZipperTests {
    private func makeZip(
        _ zipper: LANShareZipper,
        folder: URL,
        tempDirectory: URL
    ) async throws -> LANShareZipper.ZipResult {
        try await withCheckedThrowingContinuation { continuation in
            zipper.zip(
                folderPath: folder.path,
                displayName: folder.lastPathComponent,
                tempDirectory: tempDirectory
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("打包时排除 .calmbar-tmp 临时目录")
    func excludesTempDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareZip-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Share", isDirectory: true)
        let tempDirectory = folder.appendingPathComponent(".calmbar-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("public".utf8).write(to: folder.appendingPathComponent("visible.txt"))
        try Data("secret".utf8).write(to: tempDirectory.appendingPathComponent("partial.part"))
        defer { try? FileManager.default.removeItem(at: root) }

        let zipper = LANShareZipper()
        defer { zipper.cancelAll() }
        let result = try await makeZip(zipper, folder: folder, tempDirectory: tempDirectory)

        let entries = try run("/usr/bin/unzip", ["-Z1", result.url.path])
        #expect(entries.contains("visible.txt"))
        #expect(!entries.contains(".calmbar-tmp"))
        #expect(!entries.contains("partial.part"))
    }

    @Test("文件名包含换行时仍可打包")
    func handlesNewlineInFilename() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareZipNewline-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Share", isDirectory: true)
        let tempDirectory = folder.appendingPathComponent(".calmbar-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("line".utf8).write(to: folder.appendingPathComponent("line\nname.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let zipper = LANShareZipper()
        defer { zipper.cancelAll() }
        let result = try await makeZip(zipper, folder: folder, tempDirectory: tempDirectory)

        let entries = try run("/usr/bin/unzip", ["-Z1", result.url.path])
        // unzip 会把文件名中的换行显示为 ^J；真正重要的是没有打包失败。
        #expect(entries.contains("line^Jname.txt"))
    }

    @Test("文件内容变化后不会复用旧 zip 缓存")
    func invalidatesCacheWhenContentsChange() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANShareZipCache-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Share", isDirectory: true)
        let tempDirectory = folder.appendingPathComponent(".calmbar-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("a.txt")
        try Data("one".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let zipper = LANShareZipper()
        defer { zipper.cancelAll() }

        let first = try await makeZip(zipper, folder: folder, tempDirectory: tempDirectory)
        #expect(try run("/usr/bin/unzip", ["-p", first.url.path, "a.txt"]) == "one")

        // 未修改内容时应命中同一个 zip；写入 zip 本身不应触发失效。
        let repeated = try await makeZip(zipper, folder: folder, tempDirectory: tempDirectory)
        #expect(repeated.url == first.url)

        try Data("two-two".utf8).write(to: file)
        // FSEvents 有约 0.5 秒的合并延迟；等待失效通知后再请求。
        try await Task.sleep(nanoseconds: 800_000_000)
        let second = try await makeZip(zipper, folder: folder, tempDirectory: tempDirectory)

        #expect(second.url != first.url)
        #expect(try run("/usr/bin/unzip", ["-p", second.url.path, "a.txt"]) == "two-two")
    }
}
