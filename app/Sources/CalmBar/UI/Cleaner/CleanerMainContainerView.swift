import SwiftUI
import AppKit

public enum CleanerActiveTab: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case dev = "Developer"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .apps: return "软件卸载"
        case .dev: return "开发者清理"
        }
    }

    public var icon: String {
        switch self {
        case .apps: return "app.badge.fill"
        case .dev: return "hammer.fill"
        }
    }
}

public struct CleanerMainContainerView: View {
    @State private var activeTab: CleanerActiveTab = .apps
    @ObservedObject private var manager = CleanerManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Window Header / Tab Selector
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("CalmBar 清理中心")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Picker("", selection: $activeTab) {
                    ForEach(CleanerActiveTab.allCases) { tab in
                        Label(tab.titleZH, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                Button {
                    CleanerWindowController.shared.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Main Content Area
            Group {
                switch activeTab {
                case .apps:
                    AppCleanerTabView()
                case .dev:
                    DevCleanerTabView()
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .background(.background)
    }
}
