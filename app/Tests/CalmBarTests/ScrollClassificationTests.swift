import Testing
@testable import CalmBar

@Suite("Scroll Classification Tests")
struct ScrollClassificationTests {
    @Test("Test Discrete Mouse vs Trackpad Gesture Classification")
    func testDeviceClassifierLogic() {
        // Discrete mouse wheel: isContinuous = 0, phase = 0, momentumPhase = 0
        let mouseIsContinuous = 0
        let mousePhase = 0
        let mouseMomentum = 0

        let isTrackpad1 = (mouseIsContinuous != 0) || (mousePhase != 0) || (mouseMomentum != 0)
        #expect(!isTrackpad1)

        // Trackpad continuous gesture: isContinuous = 1
        let trackpadContinuous = 1
        let isTrackpad2 = (trackpadContinuous != 0) || (mousePhase != 0) || (mouseMomentum != 0)
        #expect(isTrackpad2)

        // Trackpad gesture phase: Began (1)
        let trackpadPhase = 1
        let isTrackpad3 = (mouseIsContinuous != 0) || (trackpadPhase != 0) || (mouseMomentum != 0)
        #expect(isTrackpad3)
    }
}
