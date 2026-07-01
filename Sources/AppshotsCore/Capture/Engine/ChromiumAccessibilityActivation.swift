import ApplicationServices
import Foundation

private let chromiumAXObserverNoopCallback: AXObserverCallbackWithInfo = { _, _, _, _, _ in }

final class ChromiumAccessibilityActivation: @unchecked Sendable {
    static let shared = ChromiumAccessibilityActivation()

    private typealias AddNotificationAndCheckRemoteFn = @convention(c) (
        AXObserver,
        AXUIElement,
        CFString,
        UnsafeMutableRawPointer?
    ) -> AXError

    private static let addNotificationAndCheckRemote: AddNotificationAndCheckRemoteFn? = {
        _ = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            RTLD_LAZY
        )

        for name in [
            "_AXObserverAddNotificationAndCheckRemote",
            "AXObserverAddNotificationAndCheckRemote",
        ] {
            if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
                return unsafeBitCast(symbol, to: AddNotificationAndCheckRemoteFn.self)
            }
        }
        return nil
    }()

    private var activatedPIDs = Set<pid_t>()
    private var observers: [pid_t: AXObserver] = [:]

    func activateIfNeeded(pid: pid_t, root: AXUIElement) {
        // Only AXManualAccessibility acceptance is a genuine Chromium/Electron signal. Native
        // AppKit apps (Mail, System Settings, …) also accept AXEnhancedUserInterface, so the old
        // "either attribute" gate treated them as Chromium and paid a needless 0.5s activation
        // stall (plus a behaviour-mutating observer) on the first capture of every app.
        guard applyActivationAttributes(root: root) else {
            return
        }

        guard activatedPIDs.insert(pid).inserted else {
            return
        }

        registerObserver(pid: pid, root: root)
        waitForActivation(duration: 0.5)
    }

    /// Applies the accessibility-activation attributes (best effort) and returns whether this is a
    /// Chromium/Electron target — i.e. whether it accepted the Chromium-specific
    /// `AXManualAccessibility` attribute. Only Chromium targets need the observer + activation wait.
    private func applyActivationAttributes(root: AXUIElement) -> Bool {
        // Best-effort: enables richer accessibility on apps that honour it; harmless if rejected.
        _ = AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        // Chromium/Electron-specific; native AppKit apps reject this. Acceptance => Chromium.
        return AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
    }

    private func registerObserver(pid: pid_t, root: AXUIElement) {
        var observer: AXObserver?
        guard AXObserverCreateWithInfoCallback(
            pid,
            chromiumAXObserverNoopCallback,
            &observer
        ) == .success, let observer else {
            return
        }

        if let source = AXObserverGetRunLoopSource(observer) as CFRunLoopSource? {
            CoreRunLoopThread.shared.addSource(source, mode: CFRunLoopMode.defaultMode)
        }

        for notification in notifications {
            _ = addNotification(observer: observer, element: root, notification: notification)
        }

        observers[pid] = observer
    }

    private func addNotification(
        observer: AXObserver,
        element: AXUIElement,
        notification: CFString
    ) -> AXError {
        if let fn = Self.addNotificationAndCheckRemote {
            return fn(observer, element, notification, nil)
        }
        return AXObserverAddNotification(observer, element, notification, nil)
    }

    private func waitForActivation(duration: TimeInterval) {
        Thread.sleep(forTimeInterval: duration)
    }

    private let notifications: [CFString] = [
        kAXFocusedUIElementChangedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXApplicationActivatedNotification as CFString,
        kAXApplicationDeactivatedNotification as CFString,
        kAXApplicationHiddenNotification as CFString,
        kAXApplicationShownNotification as CFString,
        kAXWindowCreatedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString,
        kAXValueChangedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXSelectedChildrenChangedNotification as CFString,
        kAXLayoutChangedNotification as CFString,
    ]
}

final class CoreRunLoopThread: @unchecked Sendable {
    static let shared = CoreRunLoopThread()

    private final class RunLoopBox: @unchecked Sendable {
        var runLoop: CFRunLoop?
    }

    private let runLoop: CFRunLoop

    private init() {
        let ready = DispatchSemaphore(value: 0)
        let box = RunLoopBox()
        let thread = Thread {
            let timer = Timer(timeInterval: 3600, repeats: true) { _ in }
            RunLoop.current.add(timer, forMode: .common)
            box.runLoop = CFRunLoopGetCurrent()
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "com.appshots.capture-engine.run-loop"
        thread.start()
        ready.wait()
        runLoop = box.runLoop!
    }

    func addSource(_ source: CFRunLoopSource, mode: CFRunLoopMode = .commonModes) {
        CFRunLoopAddSource(runLoop, source, mode)
        CFRunLoopWakeUp(runLoop)
    }
}
