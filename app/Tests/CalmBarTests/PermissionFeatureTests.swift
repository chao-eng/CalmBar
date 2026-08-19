import Foundation
import Testing
@testable import CalmBar

@Suite("Permission and Feature Mapping Tests")
struct PermissionFeatureTests {

    @Test("Test Permission to Feature mappings")
    @MainActor
    func testPermissionFeatureMapping() {
        let pm = PermissionManager.shared

        let accessibilityFeatures = pm.affectedFeatures(for: .accessibility)
        #expect(accessibilityFeatures.contains(.scroll))
        #expect(accessibilityFeatures.contains(.caffeine))

        let helperFeatures = pm.affectedFeatures(for: .privilegedHelper)
        #expect(helperFeatures.contains(.thermal))
        #expect(helperFeatures.contains(.battery))
        #expect(helperFeatures.contains(.gatekeeper))

        let screenFeatures = pm.affectedFeatures(for: .screenRecording)
        #expect(screenFeatures.contains(.ocr))

        let diskFeatures = pm.affectedFeatures(for: .fullDiskAccess)
        #expect(diskFeatures.contains(.cleaner))
    }

    @Test("Test Feature Permission Requirements and Usability check")
    @MainActor
    func testRequirementsAndUsability() {
        let pm = PermissionManager.shared

        let scrollReqs = pm.requirements(for: .scroll)
        #expect(scrollReqs.count == 1)
        #expect(scrollReqs.first?.type == .accessibility)
        #expect(scrollReqs.first?.level == .required)

        let ocrReqs = pm.requirements(for: .ocr)
        #expect(ocrReqs.contains(where: { $0.type == .screenRecording && $0.level == .required }))

        let clipboardReqs = pm.requirements(for: .clipboard)
        #expect(clipboardReqs.isEmpty)

        // Clipboard should always be usable as it has no required permissions
        #expect(pm.isFeatureUsable(.clipboard) == true)
    }
}
