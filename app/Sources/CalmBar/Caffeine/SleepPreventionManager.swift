import AppKit
import Foundation
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system and display sleep using IOKit power management assertions
public final class SleepPreventionManager: @unchecked Sendable {
    public static let shared = SleepPreventionManager()

    private var sleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true
    private let lock = NSLock()

    private init() {
        setupWorkspaceNotifications()
    }

    deinit {
        releaseSleepAssertion()
        assertionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Prevents the system and display from sleeping
    public func preventSleep() {
        lock.lock()
        defer { lock.unlock() }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.assertionTimer?.invalidate()
            self.assertionTimer = Timer.scheduledTimer(
                withTimeInterval: 10.0,
                repeats: true
            ) { [weak self] _ in
                self?.refreshSleepAssertion()
            }
            self.refreshSleepAssertion()
        }
    }

    /// Allows the system to sleep normally
    public func allowSleep() {
        lock.lock()
        defer { lock.unlock() }

        DispatchQueue.main.async { [weak self] in
            self?.assertionTimer?.invalidate()
            self?.assertionTimer = nil
            self?.releaseSleepAssertion()
        }
    }

    public var isHoldingAssertion: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sleepAssertionID != nil
    }

    // MARK: - Private Methods

    private func refreshSleepAssertion() {
        guard isUserSessionActive else { return }

        // Release existing assertion if any
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }

        var assertionID: IOPMAssertionID = 0
        let reason = "CalmBar prevents sleep (Caffeine Mode)" as CFString
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            reason,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            15.0, // Timeout after 15 seconds so fail-safe works if app is hard killed
            nil as CFString?,
            &assertionID
        )

        if result == kIOReturnSuccess {
            self.sleepAssertionID = assertionID
        }
    }

    private func releaseSleepAssertion() {
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }
    }

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func sessionDidResignActive() {
        isUserSessionActive = false
        releaseSleepAssertion()
    }

    @objc private func sessionDidBecomeActive() {
        isUserSessionActive = true
        if assertionTimer != nil {
            refreshSleepAssertion()
        }
    }
}
