import Foundation
import SwiftUI

public struct FeatureDashboardItem: Identifiable, Sendable {
    public let id: String
    public let featureID: FeatureID
    public let title: String
    public let subtitle: String?
    public let iconName: String
    public let state: FeatureState
    public let isHighlighted: Bool

    public init(
        id: String,
        featureID: FeatureID,
        title: String,
        subtitle: String? = nil,
        iconName: String,
        state: FeatureState = .enabled,
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.featureID = featureID
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.state = state
        self.isHighlighted = isHighlighted
    }
}
