import Combine
import Foundation

@MainActor
public protocol CalmFeature: AnyObject, ObservableObject {
    var id: FeatureID { get }
    var title: String { get }
    var category: FeatureCategory { get }
    var requiredPermissions: [FeaturePermissionRequirement] { get }
    var state: FeatureState { get }
    var commands: [FeatureCommand] { get }

    var dashboardItem: FeatureDashboardItem? { get }

    func start()
    func stop()
    func suspend()
    func resume()
    func cleanup()
    func refreshState()
}

public extension CalmFeature {
    func suspend() {}
    func resume() {}
    func cleanup() {
        stop()
    }
    func refreshState() {}
    var commands: [FeatureCommand] { [] }
    var dashboardItem: FeatureDashboardItem? { nil }
}
