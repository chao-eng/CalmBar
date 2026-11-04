import AppKit
import Combine
import Sparkle

/// Sparkle 封装。
///
/// `SUFeedURL` / EdDSA 公钥放在 Info.plist；这里额外提供两个能力：
/// 1. 手动检查更新前先探测网络，不可达时明确提示用户；
/// 2. 代理开启时把 Sparkle 的更新源指向本地转发服务（`UpdateRelayServer`），
///    让 appcast 与安装包下载都能走 App 内配置的代理。
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    @Published private(set) var canCheck: Bool = true
    @Published private(set) var isChecking: Bool = false

    // 「更新设置」窗口直接绑定这三个字段，改动即时写盘并生效。
    @Published var proxyEnabled: Bool {
        didSet { persistProxySettings() }
    }
    @Published var proxyHost: String {
        didSet { persistProxySettings() }
    }
    @Published var proxyPortText: String {
        didSet { persistProxySettings() }
    }

    private var controller: SPUStandardUpdaterController?
    private var sparkleCanCheck = true
    private var cancellable: AnyCancellable?

    /// 面板与设置页展示用的版本号，例：2.4.0 (1)。
    static var currentVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private override init() {
        let defaults = UserDefaults.standard
        proxyEnabled = defaults.bool(forKey: UpdateProxyConfig.enabledKey)
        proxyHost = defaults.string(forKey: UpdateProxyConfig.hostKey) ?? UpdateProxyConfig.defaultHost
        proxyPortText = defaults.string(forKey: UpdateProxyConfig.portKey) ?? String(UpdateProxyConfig.defaultPort)
        super.init()

        // 本地转发服务常驻（只接受回环连接 + 随机 token）。
        UpdateRelayServer.shared.start()

        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: self,
                                                      userDriverDelegate: self)
        self.controller = controller
        sparkleCanCheck = controller.updater.canCheckForUpdates
        refreshCanCheck()
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.sparkleCanCheck = value
                self.refreshCanCheck()
            }
    }

    /// 手动「检查更新…」入口：先探测网络，不可达时提示用户。
    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        refreshCanCheck()
        Task { @MainActor in
            let probe = await UpdateNetwork.probeReachability()
            self.isChecking = false
            self.refreshCanCheck()
            switch probe {
            case .success:
                self.controller?.checkForUpdates(nil)
            case .failure(let error):
                self.presentUnreachableAlert(error: error)
            }
        }
    }

    /// 供「更新设置」窗口的「测试连接」使用。
    func testConnection() async -> Result<Int, Error> {
        await UpdateNetwork.probeReachability()
    }

    private func refreshCanCheck() {
        canCheck = sparkleCanCheck && !isChecking
    }

    private func persistProxySettings() {
        let defaults = UserDefaults.standard
        defaults.set(proxyEnabled, forKey: UpdateProxyConfig.enabledKey)
        defaults.set(proxyHost, forKey: UpdateProxyConfig.hostKey)
        defaults.set(proxyPortText, forKey: UpdateProxyConfig.portKey)
    }

    private func presentUnreachableAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法连接到更新服务器"
        var text = "当前网络不可达，暂时无法检查更新。\n请检查网络连接"
        if UpdateProxyConfig.current().isValid {
            text += "，或确认「更新设置」中的代理是否可用。"
        } else {
            text += "，或在「更新设置」中配置网络代理。"
        }
        alert.informativeText = text + "\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "打开更新设置…")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            UpdateSettingsWindow.shared.show()
        }
    }
}

extension Updater: SPUUpdaterDelegate {
    /// 代理启用且转发服务就绪时，把 Sparkle 的更新源改为本地转发地址。
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard UpdateProxyConfig.current().isValid else { return nil }
        return UpdateRelayServer.shared.appcastURL
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    /// 「已是新版」弹窗里的「版本历史记录」：还原成原始 GitHub 地址再交给浏览器。
    /// 转发地址只对 Sparkle 进程有效（随机端口 + 进程内 token），浏览器打开必 403。
    /// 显式标注 Objective-C 选择器，确保 Sparkle 的 respondsToSelector 能命中。
    @objc(standardUserDriverShowVersionHistoryForAppcastItem:)
    func standardUserDriverShowVersionHistory(for item: SUAppcastItem) {
        guard let notesURL = item.fullReleaseNotesURL ?? item.releaseNotesURL,
              let target = Self.unwrappedReleaseNotesURL(notesURL) else { return }
        NSWorkspace.shared.open(target)
    }

    /// 把 `http://127.0.0.1:<port>/fetch?token=…&url=…` 还原成被转发的原始地址；
    /// 非转发地址原样返回，转发地址解析失败则返回 nil（宁可不打开也不打开本地地址）。
    private static func unwrappedReleaseNotesURL(_ url: URL) -> URL? {
        let isRelay = url.scheme?.lowercased() == "http"
            && url.host == "127.0.0.1"
            && url.path == "/fetch"
        guard isRelay else { return url }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let original = URL(string: raw),
              let scheme = original.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return original
    }
}
