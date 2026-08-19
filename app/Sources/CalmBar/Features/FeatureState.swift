import Foundation

public enum FeatureState: Equatable, Sendable {
    case unavailable
    case disabled
    case enabled
    case running
    case suspended
    case needsPermission
    case degraded
    case failed(String)
}
