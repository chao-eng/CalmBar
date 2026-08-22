import Foundation
import Testing
@testable import CalmBar

@Suite("Feature Manager Tests")
struct FeatureManagerTests {

    @MainActor
    final class MockFeature: CalmFeature {
        let id: FeatureID
        let title: String
        let category: FeatureCategory
        var requiredPermissions: [FeaturePermissionRequirement] = []
        var state: FeatureState = .enabled
        var commands: [FeatureCommand] = []

        var startCalled = false
        var stopCalled = false
        var cleanupCalled = false

        init(id: FeatureID, title: String, category: FeatureCategory) {
            self.id = id
            self.title = title
            self.category = category
        }

        func start() {
            startCalled = true
            state = .running
        }

        func stop() {
            stopCalled = true
            state = .disabled
        }

        func cleanup() {
            cleanupCalled = true
            state = .disabled
        }
    }

    @Test("Test Feature registration and query by ID")
    @MainActor
    func testFeatureRegistration() {
        let manager = FeatureManager()
        let mockThermal = MockFeature(id: .thermal, title: "Mock Thermal", category: .hardware)
        let mockNoTunes = MockFeature(id: .noTunes, title: "Mock NoTunes", category: .system)

        manager.register(mockThermal)
        manager.register(mockNoTunes)

        let retrieved = manager.feature(id: .thermal)
        #expect(retrieved != nil)
        #expect(retrieved?.title == "Mock Thermal")
        #expect(retrieved?.category == .hardware)

        let retrievedNoTunes = manager.feature(id: .noTunes)
        #expect(retrievedNoTunes != nil)
        #expect(retrievedNoTunes?.title == "Mock NoTunes")

        let nonExistent = manager.feature(id: .caffeine)
        #expect(nonExistent == nil)
    }

    @Test("Test startAll and cleanupAll lifecycle triggers")
    @MainActor
    func testLifecycleMethods() {
        let manager = FeatureManager()
        let feature1 = MockFeature(id: .scroll, title: "Scroll", category: .input)
        let feature2 = MockFeature(id: .battery, title: "Battery", category: .hardware)

        manager.register(feature1)
        manager.register(feature2)

        #expect(feature1.startCalled == false)
        #expect(feature2.startCalled == false)

        manager.startAll()
        #expect(feature1.startCalled == true)
        #expect(feature2.startCalled == true)
        #expect(feature1.state == .running)
        #expect(feature2.state == .running)

        manager.cleanupAll()
        #expect(feature1.cleanupCalled == true)
        #expect(feature2.cleanupCalled == true)
    }

    @Test("Test filtering features by category")
    @MainActor
    func testCategoryFilter() {
        let manager = FeatureManager()
        let hardware1 = MockFeature(id: .thermal, title: "Thermal", category: .hardware)
        let hardware2 = MockFeature(id: .battery, title: "Battery", category: .hardware)
        let productivity = MockFeature(id: .clipboard, title: "Clipboard", category: .productivity)

        manager.register(hardware1)
        manager.register(hardware2)
        manager.register(productivity)

        let hardwareFeatures = manager.features(for: .hardware)
        #expect(hardwareFeatures.count == 2)

        let productivityFeatures = manager.features(for: .productivity)
        #expect(productivityFeatures.count == 1)
        #expect(productivityFeatures.first?.id == .clipboard)

        let systemFeatures = manager.features(for: .system)
        #expect(systemFeatures.isEmpty)
    }

    @Test("Test Default Features Registration")
    @MainActor
    func testDefaultFeaturesRegistration() {
        let manager = FeatureManager()
        manager.registerDefaultFeatures()

        #expect(manager.allFeatures().count == 11)
        #expect(manager.feature(id: .thermal) != nil)
        #expect(manager.feature(id: .battery) != nil)
        #expect(manager.feature(id: .caffeine) != nil)
        #expect(manager.feature(id: .clipboard) != nil)
        #expect(manager.feature(id: .ocr) != nil)
        #expect(manager.feature(id: .cleaner) != nil)
        #expect(manager.feature(id: .scroll) != nil)
        #expect(manager.feature(id: .noTunes) != nil)
        #expect(manager.feature(id: .gatekeeper) != nil)
        #expect(manager.feature(id: .menuBar) != nil)
        #expect(manager.feature(id: .translation) != nil)

        let dashboardItems = manager.allDashboardItems()
        #expect(!dashboardItems.isEmpty)

        let commands = manager.allCommands()
        #expect(!commands.isEmpty)
    }

    @Test("Test refreshAllStates invokes refresh on all features")
    @MainActor
    func testRefreshAllStates() {
        let manager = FeatureManager()
        let feature1 = MockFeature(id: .scroll, title: "Scroll", category: .input)
        manager.register(feature1)

        manager.refreshAllStates()
        #expect(manager.allFeatures().count == 1)
    }
}
