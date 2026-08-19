import Foundation

public struct AppCleanerLocations: Sendable {
    public static let shared = AppCleanerLocations()

    public var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Standard scan roots for applications
    public var appScanRoots: [String] {
        let home = homeDirectory
        return [
            "/Applications",
            "/System/Applications",
            "\(home)/Applications",
            "\(home)/Applications/Chrome Apps.localized",
            "\(home)/Library/Application Support/Steam/steamapps/common"
        ]
    }

    /// Subdirectories in ~/Library and /Library to search for associated remnants
    public var librarySearchDirectories: [(type: AssociatedFileType, path: String)] {
        let home = homeDirectory
        return [
            (.appSupport, "\(home)/Library/Application Support"),
            (.caches, "\(home)/Library/Caches"),
            (.containers, "\(home)/Library/Containers"),
            (.groupContainers, "\(home)/Library/Group Containers"),
            (.preferences, "\(home)/Library/Preferences"),
            (.savedState, "\(home)/Library/Saved Application State"),
            (.webKit, "\(home)/Library/HTTPStorages"),
            (.webKit, "\(home)/Library/WebKit"),
            (.logs, "\(home)/Library/Logs"),
            (.logs, "\(home)/Library/Application Support/CrashReporter"),
            (.launchAgents, "\(home)/Library/LaunchAgents"),
            (.preferences, "\(home)/Library/PreferencePanes"),
            (.appSupport, "\(home)/Library/Application Scripts"),
            (.appSupport, "\(home)/Library/Services"),
            (.appSupport, "\(home)/Library/Internet Plug-Ins"),
            
            // System-level (privileged/shared) directories
            (.appSupport, "/Library/Application Support"),
            (.caches, "/Library/Caches"),
            (.preferences, "/Library/Preferences"),
            (.launchAgents, "/Library/LaunchAgents"),
            (.launchAgents, "/Library/LaunchDaemons"),
            (.launchAgents, "/Library/PrivilegedHelperTools"),
            (.appSupport, "/Users/Shared/Library/Application Support")
        ]
    }

    /// Hardcoded system safety exclusions (NEVER flag or delete these folders/files)
    public let systemExclusions: Set<String> = [
        "com.apple.",
        "apple",
        "system",
        "finder",
        "dock",
        "loginwindow",
        "spotlight",
        "siri",
        "safari",
        "preview",
        "textedit",
        "mail",
        "messages",
        "photos",
        "music",
        "tv",
        "podcasts",
        "notes",
        "reminders",
        "calendar",
        "contacts",
        "maps",
        "calmbar",
        "com.chaoeng.CalmBar",
        "com.chao.CalmBar"
    ]
}
