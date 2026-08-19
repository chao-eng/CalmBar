import Combine
import Foundation

@MainActor
public final class FeatureManager: ObservableObject {
    public static let shared = FeatureManager()

    @Published public private(set) var features: [FeatureID: any CalmFeature] = [:]

    public init() {}

    public func registerDefaultFeatures() {
        register(ThermalFeature())
        register(BatteryFeature())
        register(CaffeineFeature())
        register(ClipboardFeature())
        register(OCRFeature())
        register(CleanerFeature())
        register(ScrollFeature())
        register(NoTunesFeature())
        register(GatekeeperFeature())
        register(MenuBarFeature())
    }

    public func register(_ feature: any CalmFeature) {
        features[feature.id] = feature
    }

    public func unregister(id: FeatureID) {
        features.removeValue(forKey: id)
    }

    public func feature(id: FeatureID) -> (any CalmFeature)? {
        features[id]
    }

    public func allFeatures() -> [any CalmFeature] {
        FeatureID.allCases.compactMap { features[$0] }
    }

    public func features(for category: FeatureCategory) -> [any CalmFeature] {
        allFeatures().filter { $0.category == category }
    }

    public func startAll() {
        for feature in allFeatures() {
            feature.start()
        }
    }

    public func stopAll() {
        for feature in allFeatures() {
            feature.stop()
        }
    }

    public func cleanupAll() {
        for feature in allFeatures() {
            feature.cleanup()
        }
    }
}
