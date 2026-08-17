import AppKit
import Combine
import Foundation
import SwiftUI

/// Top-level coordinator for Caffeine (Sleep prevention and Activity simulation) in CalmBar
@MainActor
public final class CaffeineManager: ObservableObject {
    public static let shared = CaffeineManager()

    @Published public var isActive: Bool = false
    @Published public var timeRemaining: TimeInterval?
    @Published public var totalDuration: TimeInterval?

    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()

        if AppSettings.shared.caffeineEnabled || AppSettings.shared.caffeineActivateAtLaunch {
            let defaultMinutes = AppSettings.shared.caffeineDefaultDuration
            let duration: TimeInterval? = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
            activate(withTimeout: duration)
        }
    }

    // MARK: - Public Methods

    /// Toggles the active state of Caffeine
    public func toggle() {
        if isActive {
            deactivate()
        } else {
            let defaultMinutes = AppSettings.shared.caffeineDefaultDuration
            let duration: TimeInterval? = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
            activate(withTimeout: duration)
        }
    }

    /// Activates Caffeine with an optional timeout in seconds (nil or 0 means indefinite)
    public func activate(withTimeout timeout: TimeInterval? = nil) {
        cancelTimers()

        let duration: TimeInterval?
        if let timeout {
            duration = timeout > 0 ? timeout : nil
        } else {
            let defaultMinutes = AppSettings.shared.caffeineDefaultDuration
            duration = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
        }

        self.totalDuration = duration

        if let duration {
            self.timeRemaining = duration

            self.timeoutTimer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.deactivate()
                }
            }

            self.displayTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let timeoutTimer = self.timeoutTimer else {
                        self?.displayTimer?.invalidate()
                        return
                    }

                    let remaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
                    self.timeRemaining = remaining
                    if remaining <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            self.timeRemaining = nil
        }

        self.isActive = true
        AppSettings.shared.caffeineEnabled = true
        SleepPreventionManager.shared.preventSleep()

        if AppSettings.shared.caffeineKeepAppsActive {
            ActivitySimulator.shared.startMonitoring()
        }
    }

    /// Deactivates Caffeine
    public func deactivate() {
        cancelTimers()
        self.timeRemaining = nil
        self.totalDuration = nil
        self.isActive = false
        AppSettings.shared.caffeineEnabled = false
        SleepPreventionManager.shared.allowSleep()
        ActivitySimulator.shared.stopMonitoring()
    }

    /// Updates activity simulation monitoring based on preference
    public func updateActivitySimulation(enabled: Bool) {
        if enabled {
            ActivitySimulator.shared.requestPermission()
        }

        if enabled && isActive {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    /// Returns a user-friendly formatted string of the remaining time
    public func formattedTimeRemaining() -> String {
        guard isActive else {
            return "已停用"
        }

        guard let remaining = timeRemaining, remaining > 0 else {
            return "无限期保持清醒"
        }

        let seconds = Int(remaining)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    public var progressFraction: Double {
        guard isActive else { return 0.0 }
        guard let total = totalDuration, total > 0, let remaining = timeRemaining else {
            return 1.0 // Indefinite is full
        }
        return max(0.0, min(1.0, remaining / total))
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Observe workspace sleep notification
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if AppSettings.shared.caffeineDeactivateOnManualSleep {
                        self?.deactivate()
                    }
                }
            }
            .store(in: &cancellables)

        // On wake, check if timeout timer elapsed during sleep
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let timeoutTimer = self.timeoutTimer else { return }
                    if timeoutTimer.fireDate.timeIntervalSinceNow <= 0 {
                        self.deactivate()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func cancelTimers() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
    }
}
