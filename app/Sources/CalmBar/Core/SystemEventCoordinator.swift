import AppKit
import Combine
import Foundation
import CalmBarKit

/// Central system event observer coordinating energy saving, sleep, wake, lock screen, and hardware safety transitions.
@MainActor
public final class SystemEventCoordinator: ObservableObject {
    public static let shared = SystemEventCoordinator()

    @Published public private(set) var isScreenOn: Bool = true
    @Published public private(set) var isSessionActive: Bool = true
    @Published public private(set) var isSystemSleeping: Bool = false

    /// Combined state: true only when screen is on, session is active, and system is awake
    @Published public private(set) var isOperational: Bool = true

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupSystemObservers()
    }

    private func setupSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let dCenter = DistributedNotificationCenter.default()

        // 1. Sleep & Wake Notifications
        wsCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleWillSleep() }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleDidWake() }
            .store(in: &cancellables)

        // 2. Display Sleep & Wake
        wsCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleScreensDidSleep() }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleScreensDidWake() }
            .store(in: &cancellables)

        // 3. User Session Active / Lock Screen
        wsCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleSessionResignActive() }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleSessionBecomeActive() }
            .store(in: &cancellables)

        // 4. macOS Screen Lock & Unlock Distributed Notifications
        dCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenLocked()
            }
        }

        dCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenUnlocked()
            }
        }
    }

    private func updateOperationalState() {
        let newOperational = isScreenOn && isSessionActive && !isSystemSleeping
        if self.isOperational != newOperational {
            self.isOperational = newOperational
        }
    }

    // MARK: - Event Handlers

    private func handleWillSleep() {
        isSystemSleeping = true
        updateOperationalState()

        // Hardware safety: Always restore standard charging and auto fan control before sleeping
        RecoveryCoordinator.shared.performRecovery(reason: .systemSleep)
    }

    private func handleDidWake() {
        isSystemSleeping = false
        updateOperationalState()

        // Re-evaluate policies after waking
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            BatteryChargeManager.shared.evaluateChargingPolicy()
        }
    }

    private func handleScreensDidSleep() {
        isScreenOn = false
        updateOperationalState()
    }

    private func handleScreensDidWake() {
        isScreenOn = true
        updateOperationalState()
    }

    private func handleSessionResignActive() {
        isSessionActive = false
        updateOperationalState()
    }

    private func handleSessionBecomeActive() {
        isSessionActive = true
        updateOperationalState()
    }

    private func handleScreenLocked() {
        isSessionActive = false
        updateOperationalState()
    }

    private func handleScreenUnlocked() {
        isSessionActive = true
        updateOperationalState()
    }
}
