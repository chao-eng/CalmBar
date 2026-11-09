import Foundation

// MARK: - 分享列表与设置持久化

public final class LANShareStore: @unchecked Sendable {
    private struct PersistedState: Codable {
        var version: Int
        var settings: LANShareSettings
        var items: [LANShareItem]
    }

    private let lock = NSLock()
    private let stateURL: URL
    private var settings: LANShareSettings
    private var items: [LANShareItem]
    private var revisionValue: Int = 0
    private var onChange: (@Sendable () -> Void)?

    public init(stateDirectory: URL) {
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        stateURL = stateDirectory.appendingPathComponent("state.json")

        if let data = try? Data(contentsOf: stateURL),
           let persisted = try? JSONDecoder().decode(PersistedState.self, from: data) {
            settings = persisted.settings
            items = persisted.items
        } else {
            settings = .default
            items = []
        }
        refreshValidity()
    }

    public func setChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }

    public var currentSettings: LANShareSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    public var currentItems: [LANShareItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    public var revision: Int {
        lock.lock()
        defer { lock.unlock() }
        return revisionValue
    }

    public func updateSettings(_ newSettings: LANShareSettings) {
        lock.lock()
        settings = newSettings
        lock.unlock()
        persistAndNotify()
    }

    /// 返回实际新增的条目（已存在同一路径时忽略）。
    @discardableResult
    public func add(_ newItems: [LANShareItem]) -> [LANShareItem] {
        guard !newItems.isEmpty else { return [] }
        lock.lock()
        var added: [LANShareItem] = []
        for item in newItems {
            if let path = item.path, items.contains(where: { $0.path == path }) {
                continue
            }
            items.append(item)
            added.append(item)
        }
        let result = added
        lock.unlock()
        if !result.isEmpty { persistAndNotify() }
        return result
    }

    public func remove(id: String) -> Bool {
        lock.lock()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return false
        }
        items.remove(at: index)
        lock.unlock()
        persistAndNotify()
        return true
    }

    public func removeAll() {
        lock.lock()
        items.removeAll()
        lock.unlock()
        persistAndNotify()
    }

    public func item(id: String) -> LANShareItem? {
        lock.lock()
        defer { lock.unlock() }
        return items.first { $0.id == id }
    }

    /// 取消所有进行中的远程上传占位（仅在文件已完整落盘后调用）。
    public func markInvalid(id: String, reason: String) {
        lock.lock()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        items[index].isValid = false
        items[index].invalidReason = reason
        lock.unlock()
        persistAndNotify()
    }

    /// 重新校验文件/文件夹是否仍然存在，供窗口打开时刷新。
    public func revalidate() {
        lock.lock()
        refreshValidity()
        lock.unlock()
        persistAndNotify()
    }

    public func updateSize(id: String, size: Int64) {
        lock.lock()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        items[index].size = size
        lock.unlock()
        persistAndNotify()
    }

    private func refreshValidity() {
        let fileManager = FileManager.default
        for index in items.indices {
            guard items[index].kind != .text else { continue }
            guard let path = items[index].path else {
                items[index].isValid = false
                items[index].invalidReason = "路径缺失"
                continue
            }
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let expectedDirectory = items[index].kind == .folder
            if !exists || (expectedDirectory && !isDirectory.boolValue) {
                items[index].isValid = false
                items[index].invalidReason = "文件已被移动或删除"
            } else {
                items[index].isValid = true
                items[index].invalidReason = nil
            }
        }
    }

    private func persistAndNotify() {
        lock.lock()
        revisionValue += 1
        let state = PersistedState(version: 1, settings: settings, items: items)
        let handler = onChange
        lock.unlock()

        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
        handler?()
    }
}
