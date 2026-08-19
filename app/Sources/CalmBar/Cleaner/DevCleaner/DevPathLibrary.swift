import Foundation

public struct DevPathLibrary {
    public static func getCategories() -> [DevCategory] {
        return [
            DevCategory(name: "Xcode & Apple", iconName: "hammer.fill", paths: [
                "~/Library/Developer/Xcode/DerivedData/",
                "~/Library/Developer/Xcode/Archives/",
                "~/Library/Developer/CoreSimulator/Devices/",
                "~/Library/Developer/Xcode/iOS DeviceSupport/",
                "~/Library/Developer/Xcode/watchOS DeviceSupport/",
                "~/Library/Developer/Xcode/tvOS DeviceSupport/",
                "~/Library/Developer/Xcode/macOS DeviceSupport/",
                "~/Library/Developer/Xcode/DocumentationCache/",
                "~/Library/Developer/Xcode/UserData/",
                "~/Library/Caches/com.apple.dt.xcodebuild/",
                "~/Library/Caches/com.apple.dt.Xcode.sourcecontrol.Git/",
                "~/Library/Caches/CocoaPods/",
                "~/.cocoapods/repos/",
                "~/.swiftpm/",
                "~/Carthage/",
                "~/Library/Caches/org.carthage.CarthageKit/"
            ]),
            DevCategory(name: "VS Code & Cursor & Zed", iconName: "chevron.left.forwardslash.chevron.right", paths: [
                "~/Library/Application Support/Code/Cache",
                "~/Library/Application Support/Code/GPUCache",
                "~/Library/Application Support/Code/CachedConfigurations",
                "~/Library/Application Support/Code/CachedData",
                "~/Library/Application Support/Code/CachedExtensionVSIXs",
                "~/Library/Application Support/Code/CachedExtensions",
                "~/Library/Application Support/Code/CachedProfilesData",
                "~/Library/Application Support/Code/Code Cache",
                "~/.vscode/extensions/",
                "~/.vscode/cli/",
                "~/Library/Application Support/Cursor/Cache",
                "~/Library/Application Support/Cursor/GPUCache",
                "~/Library/Application Support/Cursor/CachedConfigurations",
                "~/Library/Application Support/Cursor/CachedData",
                "~/Library/Application Support/Cursor/CachedExtensionVSIXs",
                "~/Library/Application Support/Cursor/CachedExtensions",
                "~/Library/Application Support/Cursor/CachedProfilesData",
                "~/Library/Application Support/Cursor/Code Cache",
                "~/.cursor/extensions/",
                "~/Library/Caches/Zed/",
                "~/Library/Application Support/Zed/node/cache/"
            ]),
            DevCategory(name: "Node.js & JavaScript", iconName: "shippingbox.fill", paths: [
                "~/.npm/",
                "~/.nvm/versions/node/*/",
                "~/.nvm/.cache/",
                "~/Library/pnpm/store",
                "~/.cache/yarn/",
                "~/.yarn-cache/",
                "~/.bun/install/cache",
                "~/Library/Caches/deno",
                "/usr/local/lib/node_modules/"
            ]),
            DevCategory(name: "Python & AI", iconName: "terminal.fill", paths: [
                "~/Library/Caches/pip/",
                "~/Library/Caches/pypoetry/",
                "~/Library/Application Support/pypoetry/",
                "~/.cache/uv/",
                "~/.local/share/uv/",
                "~/.conda/",
                "~/anaconda3/",
                "~/miniconda3/",
                "~/.pyenv/cache/"
            ]),
            DevCategory(name: "Rust & Go", iconName: "gearshape.2.fill", paths: [
                "~/.cargo/git/",
                "~/.cargo/registry/",
                "~/go/pkg/mod/",
                "~/go/bin/"
            ]),
            DevCategory(name: "Android & JetBrains", iconName: "macwindow", paths: [
                "~/.android/",
                "~/Library/Application Support/Google/AndroidStudio*/",
                "~/Library/Caches/Google/AndroidStudio*/",
                "~/Library/Logs/AndroidStudio/",
                "~/Library/Caches/JetBrains/",
                "~/Library/Logs/JetBrains/"
            ]),
            DevCategory(name: "Java & Other Toolchains", iconName: "cube.fill", paths: [
                "~/.gradle/caches/",
                "~/.gradle/wrapper/",
                "~/.m2/",
                "~/.pub-cache/",
                "~/Library/Caches/flutter_engine/",
                "~/.gem/",
                "~/.composer/cache/",
                "~/.cache/nix/",
                "~/.stack/"
            ])
        ]
    }
}
