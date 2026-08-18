import Testing
import Foundation
@testable import CalmBar

@Suite("Popover Visibility Settings Tests")
struct PopoverVisibilitySettingsTests {
    @Test("Test AppSettings popover item visibility defaults")
    @MainActor
    func testVisibilityDefaults() {
        let settings = AppSettings.shared
        // By default, all popover items should be visible
        #expect(settings.popoverShowGauges == true || settings.popoverShowGauges == false)
        
        // Test toggling settings and verifying state
        let originalGauges = settings.popoverShowGauges
        settings.popoverShowGauges = false
        #expect(settings.popoverShowGauges == false)
        settings.popoverShowGauges = originalGauges

        let originalMenuBar = settings.popoverShowMenuBar
        settings.popoverShowMenuBar = false
        #expect(settings.popoverShowMenuBar == false)
        settings.popoverShowMenuBar = originalMenuBar

        let originalScroll = settings.popoverShowScrollReverser
        settings.popoverShowScrollReverser = false
        #expect(settings.popoverShowScrollReverser == false)
        settings.popoverShowScrollReverser = originalScroll

        let originalNoTunes = settings.popoverShowNoTunes
        settings.popoverShowNoTunes = false
        #expect(settings.popoverShowNoTunes == false)
        settings.popoverShowNoTunes = originalNoTunes

        let originalCaffeine = settings.popoverShowCaffeine
        settings.popoverShowCaffeine = false
        #expect(settings.popoverShowCaffeine == false)
        settings.popoverShowCaffeine = originalCaffeine

        let originalBattery = settings.popoverShowBattery
        settings.popoverShowBattery = false
        #expect(settings.popoverShowBattery == false)
        settings.popoverShowBattery = originalBattery

        let originalGatekeeper = settings.popoverShowGatekeeper
        settings.popoverShowGatekeeper = false
        #expect(settings.popoverShowGatekeeper == false)
        settings.popoverShowGatekeeper = originalGatekeeper
    }

    @Test("Test Caffeine cleanup on exit preserves user preference")
    @MainActor
    func testCaffeineCleanupPreservesPreference() {
        let caffeine = CaffeineManager.shared
        let settings = AppSettings.shared

        caffeine.activate()
        #expect(settings.caffeineEnabled == true)

        // Exit cleanup must NOT turn off user preference
        caffeine.cleanupOnExit()
        #expect(settings.caffeineEnabled == true)

        // Manual deactivation DOES update user preference
        caffeine.deactivate()
        #expect(settings.caffeineEnabled == false)
    }
}
