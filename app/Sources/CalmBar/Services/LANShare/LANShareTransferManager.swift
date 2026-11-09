import Foundation

// MARK: - 传输任务跟踪

public final class LANShareTransferManager: @unchecked Sendable {
    private struct Entry {
        var task: LANShareTransferTask
        var lastSampleAt: Date
        var lastBytes: Int64
        var cancel: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var lastNotifyAt = Date.distantPast
    private var onUpdate: (@Sendable () -> Void)?

    public init() {}

    public func setUpdateHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onUpdate = handler
        lock.unlock()
    }

    public var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.filter { $0.task.state == .waiting || $0.task.state == .transferring }.count
    }

    public func snapshot() -> [LANShareTransferTask] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { entries[$0]?.task }
    }

    @discardableResult
    public func begin(
        itemID: String?,
        fileName: String,
        peerIP: String,
        direction: LANShareTransferDirection,
        totalBytes: Int64,
        cancel: (@Sendable () -> Void)? = nil
    ) -> String {
        let task = LANShareTransferTask(
            itemID: itemID,
            fileName: fileName,
            peerIP: peerIP,
            direction: direction,
            totalBytes: totalBytes,
            state: .transferring
        )
        lock.lock()
        entries[task.id] = Entry(task: task, lastSampleAt: Date(), lastBytes: 0, cancel: cancel)
        order.append(task.id)
        trimFinishedLocked()
        lock.unlock()
        notify(force: true)
        return task.id
    }

    /// 文件名解析出来晚于任务创建，这里补写真实文件名。
    public func updateFileName(id: String, fileName: String) {
        lock.lock()
        guard var entry = entries[id], !fileName.isEmpty, entry.task.fileName != fileName else {
            lock.unlock()
            return
        }
        entry.task.fileName = fileName
        entries[id] = entry
        lock.unlock()
        notify(force: true)
    }

    public func update(id: String, transferredBytes: Int64, totalBytes: Int64? = nil) {
        lock.lock()
        guard var entry = entries[id] else {
            lock.unlock()
            return
        }
        let now = Date()
        entry.task.transferredBytes = transferredBytes
        if let totalBytes { entry.task.totalBytes = totalBytes }
        let elapsed = now.timeIntervalSince(entry.lastSampleAt)
        if elapsed >= 0.5 {
            let delta = transferredBytes - entry.lastBytes
            let instantaneous = elapsed > 0 ? Double(delta) / elapsed : 0
            entry.task.bytesPerSecond = entry.task.bytesPerSecond == 0
                ? instantaneous
                : entry.task.bytesPerSecond * 0.7 + instantaneous * 0.3
            entry.lastSampleAt = now
            entry.lastBytes = transferredBytes
        }
        entries[id] = entry
        lock.unlock()
        notify(force: false)
    }

    public func finish(id: String, state: LANShareTransferState, errorMessage: String? = nil) {
        lock.lock()
        guard var entry = entries[id] else {
            lock.unlock()
            return
        }
        entry.task.state = state
        entry.task.errorMessage = errorMessage
        entry.task.bytesPerSecond = 0
        if state == .completed { entry.task.transferredBytes = entry.task.totalBytes }
        entry.cancel = nil
        entries[id] = entry
        trimFinishedLocked()
        lock.unlock()
        notify(force: true)
    }

    public func cancel(id: String) {
        lock.lock()
        let cancel = entries[id]?.cancel
        lock.unlock()
        cancel?()
        finish(id: id, state: .cancelled)
    }

    public func cancelAll() {
        lock.lock()
        let cancels = entries.values.compactMap(\.cancel)
        let ids = entries.keys.filter { id in
            guard let task = entries[id]?.task else { return false }
            return task.state == .waiting || task.state == .transferring
        }
        lock.unlock()
        for cancel in cancels { cancel() }
        for id in ids { finish(id: id, state: .cancelled) }
    }

    public func clearFinished() {
        lock.lock()
        order.removeAll { id in
            guard let state = entries[id]?.task.state else { return true }
            return state != .waiting && state != .transferring
        }
        entries = entries.filter { entry in
            entry.value.task.state == .waiting || entry.value.task.state == .transferring
        }
        lock.unlock()
        notify(force: true)
    }

    private func trimFinishedLocked() {
        guard entries.count > 50 else { return }
        let finished = order.filter { id in
            guard let state = entries[id]?.task.state else { return true }
            return state != .waiting && state != .transferring
        }
        for id in finished.prefix(finished.count - 20) {
            entries.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
    }

    private func notify(force: Bool) {
        let now = Date()
        lock.lock()
        guard force || now.timeIntervalSince(lastNotifyAt) >= 0.1 else {
            lock.unlock()
            return
        }
        lastNotifyAt = now
        let handler = onUpdate
        lock.unlock()
        handler?()
    }
}
