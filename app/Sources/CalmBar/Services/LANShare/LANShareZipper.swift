import CoreServices
import CryptoKit
import Foundation

// MARK: - 文件夹打包

public final class LANShareZipper: @unchecked Sendable {
    public struct ZipResult: Sendable {
        public let url: URL
        public let fileName: String
    }

    private struct CacheEntry {
        let url: URL
        let createdAt: Date
        let fileName: String
    }

    private let lock = NSLock()
    private let watchLock = NSLock()
    private let queue = DispatchQueue(label: "com.calmbar.lanshare.zip", qos: .utility, attributes: .concurrent)
    private let eventQueue = DispatchQueue(label: "com.calmbar.lanshare.zip.events")
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: [@Sendable (Result<ZipResult, LANShareError>) -> Void]] = [:]
    private var processes: [ObjectIdentifier: Process] = [:]
    private var stopped = false
    private var eventStream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private var fingerprintCache: [String: String] = [:]
    private var fingerprintGeneration = 0

    public init() {}

    deinit {
        stopWatching()
    }

    public func zip(
        folderPath: String,
        displayName: String,
        tempDirectory: URL,
        completion: @escaping @Sendable (Result<ZipResult, LANShareError>) -> Void
    ) {
        // 指纹需要遍历目录，放到打包队列执行，避免阻塞 LANShare 的请求队列。
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let cancelled = self.stopped
            self.lock.unlock()
            guard !cancelled else {
                completion(.failure(.serverFailed("服务已停止")))
                return
            }

            let key = self.cacheKey(folderPath: folderPath)

            self.lock.lock()
            if self.stopped {
                self.lock.unlock()
                completion(.failure(.serverFailed("服务已停止")))
                return
            }
            if let entry = self.cache[key], FileManager.default.fileExists(atPath: entry.url.path) {
                self.lock.unlock()
                completion(.success(ZipResult(url: entry.url, fileName: entry.fileName)))
                return
            }
            if self.inFlight[key] != nil {
                self.inFlight[key]?.append(completion)
                self.lock.unlock()
                return
            }
            self.inFlight[key] = [completion]
            self.lock.unlock()

            let result = self.makeZip(
                folderPath: folderPath,
                displayName: displayName,
                tempDirectory: tempDirectory
            )

            self.lock.lock()
            let waiters = self.inFlight.removeValue(forKey: key) ?? []
            if case .success(let value) = result,
               self.watchedPaths.contains(folderPath) {
                self.cache[key] = CacheEntry(url: value.url, createdAt: Date(), fileName: value.fileName)
                self.trimCacheLocked()
            }
            self.lock.unlock()
            for waiter in waiters { waiter(result) }
        }
    }

    public func cancelAll() {
        stopWatching()
        lock.lock()
        stopped = true
        fingerprintCache.removeAll()
        fingerprintGeneration &+= 1
        let running = Array(processes.values)
        processes.removeAll()
        for entry in cache.values {
            try? FileManager.default.removeItem(at: entry.url)
        }
        cache.removeAll()
        let waiters = inFlight.values.flatMap { $0 }
        inFlight.removeAll()
        lock.unlock()

        for process in running where process.isRunning {
            process.terminate()
        }
        for waiter in waiters {
            waiter(.failure(.serverFailed("服务已停止")))
        }
    }

    private func makeZip(folderPath: String, displayName: String, tempDirectory: URL) -> Result<ZipResult, LANShareError> {
        let safeName = LANSharePathValidator.sanitizeFilename(displayName)
        let target = tempDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // bsdtar 直接生成 zip：支持 Unicode/换行文件名，且 --exclude 可以在
        // 不生成 BOM 的情况下排除 `.calmbar-*` 临时目录。
        // stderr 不能直接挂 Pipe 后再 waitUntilExit：输出较多警告时写满管道
        // 会阻塞，导致 zip 请求永久挂起。改用临时文件承接诊断信息。
        let errorURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".tarerr")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try? FileHandle(forWritingTo: errorURL)
        defer {
            try? errorHandle?.close()
            try? FileManager.default.removeItem(at: errorURL)
        }

        // 传顶层条目而不是 "."，避免 zip 内出现 ./ 前缀；顶层条目作为独立
        // 参数传入，文件名里的换行/引号不会被 shell 或行式列表破坏。
        let topLevel = (try? FileManager.default.contentsOfDirectory(atPath: folderPath))?
            .filter { !$0.hasPrefix(".calmbar-") }
            .sorted() ?? []
        let sources = topLevel.isEmpty ? ["."] : ["--"] + topLevel

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--format", "zip", "-cf", target.path, "--exclude", ".calmbar-*"] + sources
        process.currentDirectoryURL = URL(fileURLWithPath: folderPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorHandle ?? FileHandle.nullDevice

        let identifier = ObjectIdentifier(process)
        lock.lock()
        if stopped {
            lock.unlock()
            return .failure(.serverFailed("服务已停止"))
        }
        processes[identifier] = process
        lock.unlock()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            lock.lock()
            processes.removeValue(forKey: identifier)
            lock.unlock()
            try? FileManager.default.removeItem(at: target)
            return .failure(.internalFailure("打包文件夹失败"))
        }

        lock.lock()
        processes.removeValue(forKey: identifier)
        let wasStopped = stopped
        lock.unlock()

        if wasStopped {
            try? FileManager.default.removeItem(at: target)
            return .failure(.serverFailed("服务已停止"))
        }
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: target.path) else {
            try? errorHandle?.close()
            let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
            let errorText = String(decoding: errorData, as: UTF8.self)
            NSLog("LANShareZipper: tar 打包失败 status=\(process.terminationStatus) error=\(errorText)")
            try? FileManager.default.removeItem(at: target)
            return .failure(.internalFailure("打包文件夹失败"))
        }
        return .success(ZipResult(url: target, fileName: safeName + ".zip"))
    }

    // MARK: 目录指纹

    /// 缓存键包含目录内每个条目的相对路径、类型、大小与修改时间；
    /// 仅用目录自身 mtime 会漏掉深层文件的内容/大小变化。
    private func cacheKey(folderPath: String) -> String {
        // FSEvents 能在目录内容变化时立即失效指纹，因此缓存命中时
        // 不需要再递归扫描整个目录。
        let watching = ensureWatching(folderPath: folderPath)

        lock.lock()
        // 没有可用 watcher 时不能复用旧指纹，否则文件变化后可能永久返回旧 zip。
        if watching, let cached = fingerprintCache[folderPath] {
            lock.unlock()
            return "\(folderPath)|\(cached)"
        }
        let generation = fingerprintGeneration
        lock.unlock()

        let fingerprint = computeFingerprint(folderPath: folderPath)
        if watching {
            lock.lock()
            if generation == fingerprintGeneration {
                fingerprintCache[folderPath] = fingerprint
            }
            lock.unlock()
        }
        return "\(folderPath)|\(fingerprint)"
    }

    private func computeFingerprint(folderPath: String) -> String {
        let baseURL = URL(fileURLWithPath: folderPath)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        // enumerator(atPath:) 直接返回相对路径，避免 /var 与 /private/var 之类
        // 的路径表示差异导致相对路径计算失败。
        guard let enumerator = FileManager.default.enumerator(atPath: folderPath) else {
            // 无法枚举时不复用旧缓存，交给本次打包返回真实错误。
            return "unreadable-\(UUID().uuidString)"
        }

        var hasher = SHA256()
        for case let relative as String in enumerator {
            if shouldSkip(relativePath: relative) {
                let url = baseURL.appendingPathComponent(relative)
                if isDirectory(url, keys: keys) {
                    enumerator.skipDescendants()
                }
                continue
            }
            let url = baseURL.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: keys)
            let kind = values?.isDirectory == true ? "d" : "f"
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            hasher.update(data: Data("\(relative)|\(kind)|\(size)|\(modified)\n".utf8))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func ensureWatching(folderPath: String) -> Bool {
        watchLock.lock()
        defer { watchLock.unlock() }

        lock.lock()
        if watchedPaths.contains(folderPath) {
            let watching = eventStream != nil
            lock.unlock()
            return watching
        }
        watchedPaths.append(folderPath)
        var evictedFiles: [URL] = []
        if watchedPaths.count > 8 {
            watchedPaths.removeFirst()
            // 被移出监听范围的目录不再有失效通知，必须同时清掉它的指纹与缓存。
            fingerprintCache.removeAll()
            evictedFiles = cache.values.map(\.url)
            cache.removeAll()
        }
        let paths = watchedPaths
        let previous = eventStream
        eventStream = nil
        lock.unlock()
        for url in evictedFiles {
            try? FileManager.default.removeItem(at: url)
        }

        stop(stream: previous)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let zipper = Unmanaged<LANShareZipper>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            // 自己写入 .calmbar-tmp 的 zip/上传分片不应让缓存失效。
            if paths.allSatisfy({ zipper.isTemporaryPath($0) }) { return }
            zipper.handleFolderChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as NSArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes
            )
        ) else {
            NSLog("LANShareZipper: FSEvents 创建失败，回退到每次扫描")
            lock.lock()
            watchedPaths.removeAll()
            fingerprintCache.removeAll()
            cache.removeAll()
            lock.unlock()
            return false
        }
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            NSLog("LANShareZipper: FSEvents 启动失败，回退到每次扫描")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            lock.lock()
            watchedPaths.removeAll()
            fingerprintCache.removeAll()
            cache.removeAll()
            lock.unlock()
            return false
        }

        lock.lock()
        eventStream = stream
        lock.unlock()
        return true
    }

    private func isTemporaryPath(_ path: String) -> Bool {
        path
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { $0.hasPrefix(".calmbar-") }
    }

    private func handleFolderChange() {
        lock.lock()
        fingerprintGeneration &+= 1
        fingerprintCache.removeAll()
        let entries = cache
        cache.removeAll()
        lock.unlock()

        for entry in entries.values {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    private func stopWatching() {
        watchLock.lock()
        lock.lock()
        let stream = eventStream
        eventStream = nil
        watchedPaths.removeAll()
        fingerprintCache.removeAll()
        fingerprintGeneration &+= 1
        lock.unlock()
        watchLock.unlock()
        stop(stream: stream)
        // 等待可能已经排队的回调结束，避免回调在 self 释放后访问对象。
        eventQueue.sync {}
    }

    private func stop(stream: FSEventStreamRef?) {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    // MARK: 路径工具

    private func shouldSkip(relativePath: String) -> Bool {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { $0.hasPrefix(".calmbar-") }
    }

    private func isDirectory(_ url: URL, keys: Set<URLResourceKey>) -> Bool {
        (try? url.resourceValues(forKeys: keys))?.isDirectory == true
    }

    private func trimCacheLocked() {
        guard cache.count > 3 else { return }
        let sorted = cache.sorted { $0.value.createdAt < $1.value.createdAt }
        for entry in sorted.prefix(cache.count - 2) {
            try? FileManager.default.removeItem(at: entry.value.url)
            cache.removeValue(forKey: entry.key)
        }
    }
}
