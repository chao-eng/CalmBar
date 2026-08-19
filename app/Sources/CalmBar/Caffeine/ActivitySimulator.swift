import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit

/// Simulates subtle user HID activity when the system has been idle for too long.
/// This resets the macOS IOHIDSystem idle timer, helping prevent apps that rely on system idle time from switching to Away status.
/// Note: This targets OS-level idle time; apps with proprietary server heartbeats or active keystroke hooks may behave differently.
@MainActor
public final class ActivitySimulator {
    public static let shared = ActivitySimulator()

    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 30 // Check every 30 seconds
    private var isMonitoringActive: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe system operational state (display sleep, lock, wake)
        SystemEventCoordinator.shared.$isOperational
            .receive(on: RunLoop.main)
            .sink { [weak self] operational in
                guard let self = self else { return }
                if self.isMonitoringActive {
                    if operational {
                        self.startTimer()
                    } else {
                        self.stopTimer()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Starts monitoring system idle time and simulating activity when needed
    public func startMonitoring() {
        self.isMonitoringActive = true
        if SystemEventCoordinator.shared.isOperational {
            startTimer()
        }
    }

    /// Stops monitoring and simulating activity
    public func stopMonitoring() {
        self.isMonitoringActive = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAndSimulateIfNeeded()
            }
        }
    }

    private func stopTimer() {
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
        guard SystemEventCoordinator.shared.isOperational else { return }
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

