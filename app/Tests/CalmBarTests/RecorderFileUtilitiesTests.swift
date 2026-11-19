import Foundation
import Testing
@testable import CalmBar

@Suite("Recorder File Utilities")
struct RecorderFileUtilitiesTests {
    @Test("同名成片已存在时自动改用 (1)/(2)，不覆盖")
    func avoidsOverwritingExistingRecording() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecorderFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferred = directory.appendingPathComponent("录制 2026-01-01.mp4")
        let first = directory.appendingPathComponent("录制 2026-01-01 (1).mp4")
        let partial = directory.appendingPathComponent("录制 2026-01-01.partial.mp4")
        try Data("old".utf8).write(to: preferred)
        try Data("old-1".utf8).write(to: first)
        try Data("new".utf8).write(to: partial)

        let result = try RecorderFileUtilities.moveToUniqueDestination(from: partial, preferred: preferred)

        #expect(result.lastPathComponent == "录制 2026-01-01 (2).mp4")
        #expect(try Data(contentsOf: preferred) == Data("old".utf8))
        #expect(try Data(contentsOf: first) == Data("old-1".utf8))
        #expect(try Data(contentsOf: result) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test("目标文件名未占用时直接使用原文件名")
    func usesPreferredNameWhenAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecorderFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferred = directory.appendingPathComponent("录制 2026-01-02.mp4")
        let partial = directory.appendingPathComponent("录制 2026-01-02.partial.mp4")
        try Data("new".utf8).write(to: partial)

        let result = try RecorderFileUtilities.moveToUniqueDestination(from: partial, preferred: preferred)

        #expect(result == preferred)
        #expect(try Data(contentsOf: result) == Data("new".utf8))
    }
}
