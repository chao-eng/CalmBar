import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Simulates subtle user activity when the system has been idle for too long.
/// This prevents corporate communication apps (e.g. Teams, Slack, Feishu, DingTalk) from switching status to "Away".
@MainActor
public final class ActivitySimulator {
    public static let shared = ActivitySimulator()

    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 30 // Check every 30 seconds

    private init() {}

    // MARK: - Public Methods

    /// Starts monitoring system idle time and simulating activity when needed
    public func startMonitoring() {
        stopMonitoring()

        checkTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAndSimulateIfNeeded()
            }
        }
    }

    /// Stops monitoring and simulating activity
    public func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Triggers the Accessibility permission prompt by posting a CGEvent
    public func requestPermission() {
        simulateActivity()
    }

    /// Returns current system idle time in seconds
    public func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }

        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }

        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &unmanagedDict,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
            let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
            let idleTime = dict["HIDIdleTime"] as? Int64 else { return 0 }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleTime) / 1_000_000_000
    }

    // MARK: - Private Methods

    @MainActor
    private func checkAndSimulateIfNeeded() {
        let threshold = AppSettings.shared.caffeineIdleThreshold
        guard getSystemIdleTime() >= threshold else { return }
        simulateActivity()
    }

    @MainActor
    private func simulateActivity() {
        // Get current mouse position in AppKit coordinates
        let currentPos = NSEvent.mouseLocation

        // Convert from bottom-left origin (NSEvent) to top-left origin (CGEvent)
        guard let screenHeight = NSScreen.main?.frame.height else { return }
        let cgPoint = CGPoint(x: currentPos.x, y: screenHeight - currentPos.y)

        // CGEvent generates actual HID events that reset the system idle timer
        if let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) {
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}
