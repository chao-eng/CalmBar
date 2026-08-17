import AppKit
import ApplicationServices
import Combine

public enum InputDeviceType: Sendable {
    case trackpad
    case mouse
    case unknown
}

public struct ScrollReverserConfig: Sendable {
    public var isEnabled: Bool = true
    public var reverseMouseVertical: Bool = true
    public var reverseMouseHorizontal: Bool = false
    public var reverseTrackpadVertical: Bool = false
    public var reverseTrackpadHorizontal: Bool = false

    public init(
        isEnabled: Bool = true,
        reverseMouseVertical: Bool = true,
        reverseMouseHorizontal: Bool = false,
        reverseTrackpadVertical: Bool = false,
        reverseTrackpadHorizontal: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.reverseMouseVertical = reverseMouseVertical
        self.reverseMouseHorizontal = reverseMouseHorizontal
        self.reverseTrackpadVertical = reverseTrackpadVertical
        self.reverseTrackpadHorizontal = reverseTrackpadHorizontal
    }
}

// Global thread-safe state store for event tap callback
private final class ScrollEngineState: @unchecked Sendable {
    static let shared = ScrollEngineState()
    private let lock = NSLock()
    private var _config = ScrollReverserConfig()
    private var _tapPort: CFMachPort?

    var config: ScrollReverserConfig {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _config
        }
        set {
            lock.lock()
            _config = newValue
            lock.unlock()
        }
    }

    var tapPort: CFMachPort? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _tapPort
        }
        set {
            lock.lock()
            _tapPort = newValue
            lock.unlock()
        }
    }
}

// C-convention callback for CGEventTap (Exact algorithm from Scroll Reverser MouseTap.m)
private func scrollEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = ScrollEngineState.shared.tapPort {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }

    let config = ScrollEngineState.shared.config
    guard config.isEnabled else {
        return Unmanaged.passUnretained(event)
    }

    // Is continuous scrolling (Trackpad and Magic Mouse are continuous; discrete mouse wheels are NOT continuous)
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
    let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0

    let isTrackpad = isContinuous || phase || momentumPhase

    let shouldReverseY = isTrackpad ? config.reverseTrackpadVertical : config.reverseMouseVertical
    let shouldReverseX = isTrackpad ? config.reverseTrackpadHorizontal : config.reverseMouseHorizontal

    let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let fixedPtAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fixedPtAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

    let vmul: Int64 = shouldReverseY ? -1 : 1
    let hmul: Int64 = shouldReverseX ? -1 : 1

    /* Inverting logic from Scroll Reverser MouseTap.m:
     Must set DeltaAxis first, then set FixedPtDeltaAxis and PointDeltaAxis second.
     This is because setting DeltaAxis causes macOS to internally modify PointDeltaAxis and FixedPtDeltaAxis. */
    if vmul != 1 {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: axis1 * vmul)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedPtAxis1 * Double(vmul))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: pointAxis1 * vmul)
    }

    if hmul != 1 {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: axis2 * hmul)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedPtAxis2 * Double(hmul))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: pointAxis2 * hmul)
    }

    return Unmanaged.passUnretained(event)
}

@MainActor
public final class ScrollReverserManager: ObservableObject {
    public static let shared = ScrollReverserManager()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var hasAccessibilityPermission: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        syncConfig()
        checkPermission()
        startPermissionMonitor()
        setupObservers()

        if AppSettings.shared.scrollReverserEnabled {
            start()
        }
    }

    private func syncConfig() {
        let settings = AppSettings.shared
        ScrollEngineState.shared.config = ScrollReverserConfig(
            isEnabled: settings.scrollReverserEnabled,
            reverseMouseVertical: settings.reverseMouseVertical,
            reverseMouseHorizontal: settings.reverseMouseHorizontal,
            reverseTrackpadVertical: settings.reverseTrackpadVertical,
            reverseTrackpadHorizontal: settings.reverseTrackpadHorizontal
        )
    }

    public func checkPermission() {
        let trusted = AccessibilityHelper.isProcessTrusted || isRunning
        self.hasAccessibilityPermission = trusted
        if AppSettings.shared.scrollReverserEnabled && !isRunning {
            start()
        }
    }

    private func startPermissionMonitor() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
    }

    private func setupObservers() {
        let settings = AppSettings.shared

        Publishers.Merge5(
            settings.$scrollReverserEnabled.map { _ in () },
            settings.$reverseMouseVertical.map { _ in () },
            settings.$reverseMouseHorizontal.map { _ in () },
            settings.$reverseTrackpadVertical.map { _ in () },
            settings.$reverseTrackpadHorizontal.map { _ in () }
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.syncConfig()
                if AppSettings.shared.scrollReverserEnabled && !self.isRunning {
                    self.start()
                } else if !AppSettings.shared.scrollReverserEnabled && self.isRunning {
                    self.stop()
                }
            }
        }
        .store(in: &cancellables)
    }

    public func start() {
        guard !isRunning else { return }
        syncConfig()
        let eventMask = (1 << CGEventType.scrollWheel.rawValue)

        // 1. Try Session Event Tap at tailAppend (matching Scroll Reverser MouseTap.m)
        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: scrollEventCallback,
            userInfo: nil
        )

        // 2. Fallback to Session Event Tap at headInsert
        if tap == nil {
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: scrollEventCallback,
                userInfo: nil
            )
        }

        // 3. Fallback to HID Event Tap
        if tap == nil {
            tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: scrollEventCallback,
                userInfo: nil
            )
        }

        if let validTap = tap {
            self.eventTap = validTap
            ScrollEngineState.shared.tapPort = validTap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            CGEvent.tapEnable(tap: validTap, enable: true)
            self.isRunning = true
            self.hasAccessibilityPermission = true
            NSLog("ScrollReverser: Started successfully")
        } else {
            self.isRunning = false
            self.hasAccessibilityPermission = AccessibilityHelper.isProcessTrusted
            NSLog("ScrollReverser: Failed to create CGEventTap, permission required")
        }
    }

    public func stop() {
        guard isRunning else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            self.runLoopSource = nil
        }
        ScrollEngineState.shared.tapPort = nil
        self.eventTap = nil
        self.isRunning = false
        NSLog("ScrollReverser: Stopped")
    }
}
