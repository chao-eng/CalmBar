import Foundation

// MARK: - 文件夹打包

public final class LANShareZipper: @unchecked Sendable {
    public struct ZipResult {
        public let url: URL
        public let fileName: String
    }

    private struct CacheEntry {
        let url: URL
        let createdAt: Date
        let fileName: String
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.calmbar.lanshare.zip", qos: .utility, attributes: .concurrent)
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: [(Result<ZipResult, LANShareError>) -> Void]] = [:]
    private var processes: [ObjectIdentifier: Process] = [:]
    private var stopped = false

    public init() {}

    public func zip(
        folderPath: String,
        displayName: String,
        tempDirectory: URL,
        completion: @escaping (Result<ZipResult, LANShareError>) -> Void
    ) {
        let key = cacheKey(folderPath: folderPath)
        lock.lock()
        if stopped {
            lock.unlock()
            completion(.failure(.serverFailed("服务已停止")))
            return
        }
        if let entry = cache[key], FileManager.default.fileExists(atPath: entry.url.path) {
            lock.unlock()
            completion(.success(ZipResult(url: entry.url, fileName: entry.fileName)))
            return
        }
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[key] = [completion]
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let result = self.makeZip(folderPath: folderPath, displayName: displayName, tempDirectory: tempDirectory)
            self.lock.lock()
            let waiters = self.inFlight.removeValue(forKey: key) ?? []
            if case .success(let value) = result {
                self.cache[key] = CacheEntry(url: value.url, createdAt: Date(), fileName: value.fileName)
                self.trimCacheLocked()
            }
            self.lock.unlock()
            for waiter in waiters { waiter(result) }
        }
    }

    public func cancelAll() {
        lock.lock()
        stopped = true
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", folderPath, target.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

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
            try? FileManager.default.removeItem(at: target)
            return .failure(.internalFailure("打包文件夹失败"))
        }
        return .success(ZipResult(url: target, fileName: safeName + ".zip"))
    }

    private func cacheKey(folderPath: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: folderPath)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(folderPath)|\(Int(modified))"
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
