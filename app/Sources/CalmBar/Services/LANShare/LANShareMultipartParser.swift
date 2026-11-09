import Foundation

// MARK: - multipart 流式解析

public struct LANShareMultipartResult {
    public let filename: String
    public let tempURL: URL
    public let byteCount: Int64
    public let contentType: String?

    public init(filename: String, tempURL: URL, byteCount: Int64, contentType: String?) {
        self.filename = filename
        self.tempURL = tempURL
        self.byteCount = byteCount
        self.contentType = contentType
    }
}

/// 只解析 `multipart/form-data` 中的文件字段，边读边写临时文件。
public final class LANShareMultipartParser {
    private enum State {
        case preamble
        case headers
        case body
        case marker
        case epilogue
        case failed
    }

    private struct PartMetadata {
        let name: String?
        let filename: String?
        let contentType: String?
        let isFile: Bool
    }

    private let boundary: String
    private let boundaryData: Data
    private let firstDelimiter: Data
    private let tempDirectory: URL
    private var state: State = .preamble
    private var buffer = Data()
    private var cursor = 0
    private var partCount = 0
    private var metadata: PartMetadata?
    private var fileHandle: FileHandle?
    private var tempURL: URL?
    private var fileBytes: Int64 = 0
    private var result: LANShareMultipartResult?

    public init(boundary: String, tempDirectory: URL) throws {
        guard !boundary.isEmpty, boundary.utf8.count <= LANShareLimits.maxBoundaryLength else {
            throw LANShareError.unsupportedMedia
        }
        self.boundary = boundary
        self.boundaryData = Data(("--" + boundary).utf8)
        self.firstDelimiter = Data(("--" + boundary).utf8)
        self.tempDirectory = tempDirectory
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    public var failure: LANShareError? {
        state == .failed ? LANShareError.unsupportedMedia : nil
    }

    /// 当前正在接收的文件名（已清洗）；解析到 part 头部后即可用，供传输列表实时展示。
    public var currentFileName: String? {
        let name = result?.filename ?? metadata?.filename
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    public func consume(_ data: Data) throws {
        guard state != .failed, state != .epilogue else { return }
        guard !data.isEmpty else { return }
        buffer.append(data)
        while true {
            let progressed = try step()
            if !progressed { break }
        }
        compactBuffer()
    }

    public func finish() throws -> LANShareMultipartResult {
        defer { closeFile() }
        guard state == .epilogue || state == .marker else {
            cleanupTemp()
            throw LANShareError.invalidRequest
        }
        guard let result else {
            cleanupTemp()
            throw LANShareError.invalidRequest
        }
        return result
    }

    public func cancel() {
        state = .failed
        closeFile()
        cleanupTemp()
    }

    // MARK: 状态推进

    private func step() throws -> Bool {
        switch state {
        case .preamble:
            guard let range = buffer.range(of: firstDelimiter, in: cursor..<buffer.count) else {
                // 预清理：只保留可能构成 boundary 的尾巴
                let keep = firstDelimiter.count - 1
                if buffer.count - cursor > keep {
                    cursor = buffer.count - keep
                }
                return false
            }
            cursor = range.upperBound
            state = .marker
            return true

        case .marker:
            let available = buffer.count - cursor
            guard available >= 2 else { return false }
            let first = buffer[cursor]
            let second = buffer[cursor + 1]
            if first == 45 && second == 45 { // "--" 结束
                cursor += 2
                state = .epilogue
                return true
            }
            if first == 13 && second == 10 { // CRLF，下一部分
                cursor += 2
                partCount += 1
                guard partCount <= LANShareLimits.maxMultipartParts else {
                    throw LANShareError.unsupportedMedia
                }
                state = .headers
                return true
            }
            throw LANShareError.invalidRequest

        case .headers:
            guard let terminator = buffer.range(of: Data([13, 10, 13, 10]), in: cursor..<buffer.count) else {
                if buffer.count - cursor > LANShareLimits.maxPartHeaderBytes {
                    throw LANShareError.unsupportedMedia
                }
                return false
            }
            let headerLength = terminator.lowerBound - cursor
            guard headerLength <= LANShareLimits.maxPartHeaderBytes else {
                throw LANShareError.unsupportedMedia
            }
            let headerData = buffer.subdata(in: cursor..<terminator.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                throw LANShareError.invalidRequest
            }
            metadata = parsePartHeaders(headerText)
            cursor = terminator.upperBound

            if metadata?.isFile == true {
                try openFile()
            }
            state = .body
            return true

        case .body:
            return try stepBody()

        case .epilogue:
            return false

        case .failed:
            return false
        }
    }

    private func stepBody() throws -> Bool {
        let delimiter = Data([13, 10]) + boundaryData // 仅用于查找
        guard let range = buffer.range(of: delimiter, in: cursor..<buffer.count) else {
            let keep = delimiter.count - 1
            let available = buffer.count - cursor
            if available > keep {
                let writeEnd = buffer.count - keep
                try writeBody(buffer.subdata(in: cursor..<writeEnd))
                cursor = writeEnd
            }
            return false
        }

        if range.lowerBound > cursor {
            try writeBody(buffer.subdata(in: cursor..<range.lowerBound))
        }
        cursor = range.upperBound
        finishCurrentPart()
        state = .marker
        return true
    }

    // MARK: Part 处理

    private func parsePartHeaders(_ text: String) -> PartMetadata {
        var name: String?
        var filename: String?
        var contentType: String?

        for line in text.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let headerName = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headerName == "content-disposition" {
                name = quotedValue(in: value, key: "name")
                filename = quotedValue(in: value, key: "filename")
            } else if headerName == "content-type" {
                contentType = value
            }
        }
        let isFile = filename != nil || name == "file"
        return PartMetadata(name: name, filename: filename, contentType: contentType, isFile: isFile)
    }

    private func quotedValue(in value: String, key: String) -> String? {
        let pattern = key + "=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range), match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[matchRange])
    }

    private func openFile() throws {
        guard result == nil, metadata?.isFile == true, let metadata else { return }
        let name = LANSharePathValidator.sanitizeFilename(metadata.filename ?? "未命名文件")
        let url = tempDirectory.appendingPathComponent(UUID().uuidString + ".part")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw LANShareError.internalFailure("无法创建临时文件")
        }
        fileHandle = handle
        tempURL = url
        fileBytes = 0
        self.metadata = PartMetadata(
            name: name,
            filename: name,
            contentType: metadata.contentType,
            isFile: true
        )
    }

    private func writeBody(_ data: Data) throws {
        guard metadata?.isFile == true, let fileHandle else { return }
        guard fileBytes + Int64(data.count) <= LANShareLimits.maxFileBytes else {
            throw LANShareError.fileTooLarge
        }
        do {
            try fileHandle.write(contentsOf: data)
            fileBytes += Int64(data.count)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) {
                throw LANShareError.diskFull
            }
            throw LANShareError.internalFailure("写入临时文件失败")
        }
    }

    private func finishCurrentPart() {
        guard metadata?.isFile == true else {
            metadata = nil
            return
        }
        closeFile()
        if result == nil, let tempURL, let metadata {
            result = LANShareMultipartResult(
                filename: metadata.filename ?? "未命名文件",
                tempURL: tempURL,
                byteCount: fileBytes,
                contentType: metadata.contentType
            )
        } else if result != nil, let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        self.tempURL = nil
        metadata = nil
        fileBytes = 0
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func cleanupTemp() {
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        tempURL = nil
    }

    private func compactBuffer() {
        if cursor >= buffer.count {
            buffer.removeAll(keepingCapacity: false)
            cursor = 0
            return
        }
        if cursor >= 64 * 1024 {
            buffer.removeSubrange(0..<cursor)
            cursor = 0
        }
    }
}
