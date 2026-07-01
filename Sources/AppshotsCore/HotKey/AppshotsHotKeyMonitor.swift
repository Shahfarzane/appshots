import AppKit

@MainActor
public final class AppshotsHotKeyMonitor {
    private var triggerKey: Set<CGKeyCode>
    private let onTrigger: @MainActor () -> Void
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var triggeredWhileModifierPairDown = false

    public init(
        triggerKey: Set<CGKeyCode>,
        onTrigger: @escaping @MainActor () -> Void
    ) {
        self.triggerKey = triggerKey
        self.onTrigger = onTrigger
    }

    public func updateTriggerKey(_ triggerKey: Set<CGKeyCode>) {
        guard self.triggerKey != triggerKey else { return }
        self.triggerKey = triggerKey
        triggeredWhileModifierPairDown = false
    }

    public func start() {
        guard globalFlagsMonitor == nil, localFlagsMonitor == nil else { return }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }

        // A trigger with a regular key (e.g. Hyper + S) fires on key-down.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    public func stop() {
        for monitor in [globalFlagsMonitor, localFlagsMonitor, globalKeyMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
    }

    /// The modifier portion of the trigger.
    private var modifierTrigger: Set<CGKeyCode> { triggerKey.modifiers }

    /// The single regular key in the trigger, if any.
    private var keyTrigger: CGKeyCode? { triggerKey.regularKeys.first }

    private func handleFlags(_ event: NSEvent) {
        // Only modifier-only triggers fire from flag changes; chords with a
        // regular key are handled in `handleKeyDown`.
        guard keyTrigger == nil else { return }

        let pressed = CGEventFlags(cocoaFlags: event.modifierFlags).keyCodes
        // Fire once when exactly the trigger modifiers (e.g. both Option keys)
        // are held, and reset when they are released.
        let isDown = !triggerKey.isEmpty && pressed == triggerKey
        if isDown, triggeredWhileModifierPairDown == false {
            triggeredWhileModifierPairDown = true
            onTrigger()
        } else if isDown == false {
            triggeredWhileModifierPairDown = false
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let keyTrigger, !event.isARepeat else { return }

        let pressed = CGEventFlags(cocoaFlags: event.modifierFlags).keyCodes
        if event.keyCode == keyTrigger, pressed == modifierTrigger {
            onTrigger()
        }
    }
}
