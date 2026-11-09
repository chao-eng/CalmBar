import AppKit
import Combine
import Foundation

// MARK: - 局域网互传服务门面

@MainActor
public final class LANShareService: ObservableObject {
    public static let shared = LANShareService()

    // MARK: 对外状态

    @Published public private(set) var status: LANShareStatus = .stopped
    @Published public private(set) var settings: LANShareSettings = .default
    @Published public private(set) var items: [LANShareItem] = []
    @Published public private(set) var transfers: [LANShareTransferTask] = []
    @Published public private(set) var shareURL: String?
    @Published public private(set) var networkAddress: String?
    @Published public private(set) var networkPrefix: String?
    @Published public private(set) var sessionCount: Int = 0
    @Published public private(set) var connectionCount: Int = 0
    @Published public private(set) var lastError: LANShareError?
    /// 仅在自动生成口令时展示一次，关闭提示后由 UI 清空。
    @Published public private(set) var passcodeToShowOnce: String?
    @Published public private(set) var hasPasscode: Bool = false
    @Published public private(set) var availableAddresses: [LANShareNetworkAddress] = []
    @Published public private(set) var activityLog: [String] = []

    // MARK: 内部依赖

    private let store: LANShareStore
    private let passcodeStore: LANSharePasscodeStore
    private let sessions: LANShareSessionManager
    private let transferManager = LANShareTransferManager()
    private let zipper = LANShareZipper()
    private let networkMonitor = LANShareNetworkMonitor()
    private let webRoot: URL

    private var server: LANShareHTTPServer?
    private var refreshTimer: Timer?
    private var currentPort: Int?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let stateDirectory = support.appendingPathComponent("CalmBar/LANShare", isDirectory: true)

        store = LANShareStore(stateDirectory: stateDirectory)
        passcodeStore = LANSharePasscodeStore(stateDirectory: stateDirectory)
        sessions = LANShareSessionManager(
            passcodeStore: passcodeStore,
            passcodeEnabled: store.currentSettings.passcodeEnabled
        )
        webRoot = Self.resolveWebRoot()

        settings = store.currentSettings
        // 旧版本可能把 VPN/隧道网卡写入设置，这里统一回退为自动选择。
        if let selected = settings.selectedInterface,
           LANShareNetworkInterfaces.isVirtualInterface(selected) {
            var cleaned = settings
            cleaned.selectedInterface = nil
            store.updateSettings(cleaned)
            settings = cleaned
        }
        items = store.currentItems
        hasPasscode = passcodeStore.hasPasscode
        availableAddresses = LANShareNetworkInterfaces.availableAddresses()

        store.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refreshFromStore() }
        }
        sessions.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refreshSessionCount() }
        }
        transferManager.setUpdateHandler { [weak self] in
            Task { @MainActor in self?.refreshTransfers() }
        }
        networkMonitor.setChangeHandler { [weak self] in
            Task { @MainActor in self?.handleNetworkChange() }
        }
        networkMonitor.start()

        AppSettings.shared.$lanShareEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor in self?.handleEnabledChange(enabled) }
            }
            .store(in: &cancellables)

        refreshShareURL()
    }

    // MARK: 生命周期

    public func start() {
        guard status != .starting, status != .running else { return }
        lastError = nil

        let current = store.currentSettings
        guard validate(settings: current) else {
            status = .failed
            return
        }
        settings = current

        if current.passcodeEnabled, !passcodeStore.hasPasscode {
            if let generated = try? passcodeStore.setPasscode(nil) {
                passcodeToShowOnce = generated
            }
        }
        hasPasscode = passcodeStore.hasPasscode

        guard let network = LANShareNetworkInterfaces.bestAddress(preferredInterface: current.selectedInterface) else {
            lastError = .noLocalNetwork
            status = .restricted
            shareURL = nil
            return
        }

        availableAddresses = LANShareNetworkInterfaces.availableAddresses()
        networkAddress = network.displayAddress
        networkPrefix = network.prefixText
        sessions.configure(passcodeEnabled: current.passcodeEnabled, rotateToken: true)
        status = .starting

        let server = LANShareHTTPServer(
            store: store,
            sessions: sessions,
            transfers: transferManager,
            zipper: zipper,
            settings: current,
            network: network,
            webRoot: webRoot,
            callbacks: LANShareHTTPServer.Callbacks(
                onReady: { [weak self] port in
                    Task { @MainActor in self?.handleReady(port: port) }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in self?.handleFailure(error) }
                },
                onConnectionCountChanged: { [weak self] count in
                    Task { @MainActor in self?.connectionCount = count }
                },
                onItemAdded: { [weak self] item in
                    Task { @MainActor in
                        self?.appendLog("收到来自 \(formattedPeerIP(item.uploaderIP ?? "")) 的\(item.kind == .text ? "文本" : "文件")：\(item.name)")
                    }
                },
                onLog: { [weak self] line in
                    Task { @MainActor in self?.appendLog(line) }
                }
            )
        )
        self.server = server
        server.start()
        startRefreshTimer()
    }

    public func stop() {
        server?.stop()
        server = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        currentPort = nil
        sessions.revokeAll()
        transferManager.cancelAll()
        transfers = []
        status = .stopped
        shareURL = nil
        connectionCount = 0
        sessionCount = 0
    }

    public func restart() {
        stop()
        start()
    }

    /// 对外统一入口：开关变化时自动启停。
    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: 设置

    @discardableResult
    public func updateSettings(_ newSettings: LANShareSettings) -> LANShareError? {
        var sanitized = newSettings
        sanitized.serverName = sanitized.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.serverName.isEmpty {
            sanitized.serverName = LANShareSettings.defaultServerName
        }
        sanitized.receiveDirectory = (sanitized.receiveDirectory as NSString).expandingTildeInPath

        guard validate(settings: sanitized) else { return lastError }
        guard validateDirectory(sanitized.receiveDirectory) else {
            lastError = .directoryNotWritable(sanitized.receiveDirectory)
            return lastError
        }

        let wasRunning = status == .running || status == .starting
        store.updateSettings(sanitized)
        settings = sanitized

        if sanitized.passcodeEnabled, !passcodeStore.hasPasscode,
           let generated = try? passcodeStore.setPasscode(nil) {
            passcodeToShowOnce = generated
        }
        hasPasscode = passcodeStore.hasPasscode

        if wasRunning {
            restart()
        } else {
            refreshShareURL()
        }
        return nil
    }

    public func setPasscodeEnabled(_ enabled: Bool) {
        var updated = settings
        updated.passcodeEnabled = enabled
        updateSettings(updated)
    }

    /// 传入 nil 表示自动生成 6 位口令，成功后写入 passcodeToShowOnce。
    @discardableResult
    public func setPasscode(_ code: String?) -> LANShareError? {
        do {
            let value = try passcodeStore.setPasscode(code)
            passcodeToShowOnce = value
            hasPasscode = true
            sessions.configure(passcodeEnabled: settings.passcodeEnabled, rotateToken: true)
            refreshShareURL()
            return nil
        } catch {
            lastError = .invalidRequest
            return .invalidRequest
        }
    }

    public func clearPasscode() {
        passcodeStore.clear()
        hasPasscode = false
        passcodeToShowOnce = nil
        sessions.configure(passcodeEnabled: settings.passcodeEnabled, rotateToken: true)
        refreshShareURL()
    }

    public func dismissPasscodeHint() {
        passcodeToShowOnce = nil
    }

    // MARK: 分享内容

    public func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var newItems: [LANShareItem] = []
        for url in urls {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory ?? false
            let size = isDirectory ? nil : Self.fileSize(atPath: path)
            newItems.append(LANShareItem(
                kind: isDirectory ? .folder : .file,
                name: url.lastPathComponent,
                path: path,
                size: size
            ))
        }
        _ = store.add(newItems)
    }

    @discardableResult
    public func addText(_ text: String, intro: String? = nil) -> LANShareError? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidRequest }
        guard trimmed.count <= LANShareLimits.maxTextCharacters else { return .fileTooLarge }

        let item = LANShareItem(
            kind: .text,
            name: LANShareTextTitle.make(from: trimmed),
            text: trimmed,
            intro: intro?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        _ = store.add([item])
        return nil
    }

    public func removeItem(id: String) {
        _ = store.remove(id: id)
    }

    public func removeAllItems() {
        store.removeAll()
        // 清空分享内容时一并中止并清除正在传输的任务。
        transferManager.cancelAll()
        transferManager.clearFinished()
        transfers = []
    }

    public func revalidateItems() {
        store.revalidate()
    }

    // MARK: 链接与交互

    public var isRunning: Bool { status == .running }

    public func copyShareLink() {
        guard let shareURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareURL, forType: .string)
    }

    public func openReceiveDirectory() {
        let directory = settings.receiveDirectory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
    }

    public func clearActivityLog() {
        activityLog.removeAll()
    }

    // MARK: 服务回调

    private func handleReady(port: Int) {
        currentPort = port
        status = .running
        lastError = nil
        settings.port = port
        refreshShareURL()
        sessionCount = sessions.activeSessionCount
        appendLog("局域网互传已启动，端口 \(port)")
    }

    private func handleFailure(_ error: LANShareError) {
        lastError = error
        status = .failed
        shareURL = nil
        appendLog("启动失败：\(error.userMessage)")
    }

    private func handleNetworkChange() {
        availableAddresses = LANShareNetworkInterfaces.availableAddresses()
        guard let network = LANShareNetworkInterfaces.bestAddress(preferredInterface: settings.selectedInterface) else {
            networkAddress = nil
            networkPrefix = nil
            if status == .running {
                lastError = .noLocalNetwork
                status = .restricted
            }
            shareURL = nil
            return
        }

        networkAddress = network.displayAddress
        networkPrefix = network.prefixText
        if server != nil {
            server?.refreshAllowedHosts()
            if status == .restricted || status == .failed {
                lastError = nil
                status = .running
            }
        }
        refreshShareURL()
    }

    private func refreshFromStore() {
        items = store.currentItems
        settings = store.currentSettings
    }

    private func refreshSessionCount() {
        sessionCount = sessions.activeSessionCount
    }

    private func refreshTransfers() {
        transfers = transferManager.snapshot()
    }

    private func refreshShareURL() {
        guard let port = currentPort ?? optionalPort(),
              let address = networkAddress else {
            shareURL = nil
            return
        }
        let path = "http://\(address):\(port)/"
        if settings.passcodeEnabled {
            shareURL = path
        } else {
            shareURL = path + "#t=" + sessions.currentLinkToken
        }
    }

    private func optionalPort() -> Int? {
        status == .running ? settings.port : nil
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sessionCount = self?.sessions.activeSessionCount ?? 0
            }
        }
    }

    // MARK: 校验

    private func validate(settings: LANShareSettings) -> Bool {
        guard settings.port >= LANShareLimits.minPort, settings.port <= LANShareLimits.maxPort else {
            lastError = .invalidPort
            return false
        }
        return true
    }

    private func validateDirectory(_ path: String) -> Bool {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        return fileManager.isWritableFile(atPath: path)
    }

    // MARK: 工具

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        activityLog.append("\(formatter.string(from: Date())) \(line)")
        if activityLog.count > 200 {
            activityLog.removeFirst(activityLog.count - 200)
        }
    }

    private static func fileSize(atPath path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    /// 资源目录：优先 App Bundle，其次开发环境的 Resources 目录。
    private static func resolveWebRoot() -> URL {
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("LANShareWeb", isDirectory: true))
        }
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/LANShareWeb", isDirectory: true)
        candidates.append(sourceRoot)
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path)
        } ?? candidates[0]
    }
}
