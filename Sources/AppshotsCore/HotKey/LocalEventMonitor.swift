import AppKit

// Adapted from Loop (github.com/MrKai77/Loop) — Loop/Utilities/Event Monitoring/
// LocalEventMonitor.swift. Stripped of Loop's Scribe logging / EventMonitorProtocol.
@MainActor
public final class LocalEventMonitor {
    private var localEventMonitor: Any?
    private let eventTypeMask: NSEvent.EventTypeMask
    private let eventHandler: (NSEvent) -> (NSEvent?)

    private(set) var isEnabled: Bool = false

    /// - Parameters:
    ///   - events: the events to capture.
    ///   - handler: how to handle the event. Return `nil` if processed, or the event itself to
    ///     let it continue through other monitors.
    public init(
        events: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> (NSEvent?)
    ) {
        self.eventTypeMask = events
        self.eventHandler = handler
    }

    public func start() {
        guard !isEnabled else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventTypeMask,
            handler: { [weak self] event in
                self?.eventHandler(event)
            }
        )

        isEnabled = true
    }

    public func stop() {
        guard isEnabled else { return }

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        isEnabled = false
    }
}
