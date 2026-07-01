import AppshotsCore
import Luminare
import SwiftUI

/// Records the capture trigger, rendered as Loop-style chip boxes joined by "+".
/// The trigger is a modifier chord with an optional regular key, e.g. `[Left ⌥]`
/// `[Right ⌥]`, `[Hyper]`, or `[Hyper] + [S]`. The four-modifier Hyper chord
/// (⌃⌥⇧⌘) collapses into a single `[Hyper]` chip. Click to record; Escape cancels.
struct TriggerKeycorder: View {
    @Binding private var validCurrentKey: Set<CGKeyCode>
    @State private var selectionKey: Set<CGKeyCode>

    @State private var eventMonitor: LocalEventMonitor?
    @State private var shouldShake: Bool = false
    @State private var isActive: Bool = false
    @State private var isHovering: Bool = false

    /// Called with `true` when recording starts and `false` when it ends, so the
    /// caller can pause/resume the global hot-key monitor while recording.
    private let onRecordingChange: (Bool) -> Void

    init(_ key: Binding<Set<CGKeyCode>>, onRecordingChange: @escaping (Bool) -> Void) {
        self._validCurrentKey = key
        self._selectionKey = State(initialValue: key.wrappedValue)
        self.onRecordingChange = onRecordingChange
    }

    /// The ordered chips to render: a Hyper token or individual modifiers first,
    /// then any regular key.
    private var tokens: [Token] {
        var result: [Token] = []
        let modifiers = selectionKey.modifiers
        if !modifiers.isEmpty {
            if selectionKey.isHyper {
                result.append(.hyper)
            } else {
                for key in modifiers.sorted(by: Self.modifierOrder) {
                    result.append(.modifier(key))
                }
            }
        }
        for key in selectionKey.regularKeys.sorted() {
            result.append(.regular(key))
        }
        return result
    }

    var body: some View {
        Button {
            toggleObserving()
        } label: {
            keyBoxes
        }
        .buttonStyle(.plain)
        .modifier(ShakeEffect(shakes: shouldShake ? 2 : 0))
        .animation(Animation.default, value: shouldShake)
        .onHover { isHovering = $0 }
        .onChange(of: validCurrentKey) { _, newValue in
            if selectionKey != newValue {
                selectionKey = newValue
            }
        }
        .onDisappear {
            if isActive { finishedObservingKeys(wasForced: true) }
        }
        .help(isActive ? "Press the trigger keys, or Escape to cancel" : "Click to change the trigger key")
        .fixedSize()
    }

    @ViewBuilder
    private var keyBoxes: some View {
        HStack(spacing: 6) {
            if tokens.isEmpty {
                Text(isActive ? "Set a trigger key…" : "None")
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .luminareSurface(isHovering: isHovering)
            } else {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    if index > 0 {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    chip(for: token)
                }
            }
        }
        .font(.callout)
        .fixedSize()
        .contentShape(.rect)
        .luminareCornerRadius(8)
    }

    @ViewBuilder
    private func chip(for token: Token) -> some View {
        switch token {
        case .hyper:
            chipBackground { Text("Hyper") }
        case let .modifier(key):
            chipBackground {
                let side = key.isModifierOnRightSide ? "Right" : "Left"
                let image = Image(systemName: key.modifierSystemImage ?? "exclamationmark.circle.fill")
                Text("\(side) \(image)")
            }
        case let .regular(key):
            chipBackground { Text(key.humanReadable ?? "?") }
        }
    }

    private func chipBackground(@ViewBuilder _ label: () -> some View) -> some View {
        label()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .fixedSize()
            .luminareSurface(isHovering: isHovering)
    }

    /// Sorts modifiers left-before-right, then by raw code, for stable order.
    private static func modifierOrder(_ lhs: CGKeyCode, _ rhs: CGKeyCode) -> Bool {
        if lhs.isModifierOnRightSide != rhs.isModifierOnRightSide {
            return !lhs.isModifierOnRightSide
        }
        return lhs < rhs
    }

    // MARK: - Recording

    private func toggleObserving() {
        if isActive {
            finishedObservingKeys(wasForced: true)
        } else {
            startObservingKeys()
        }
    }

    private func startObservingKeys() {
        selectionKey = []
        isActive = true
        onRecordingChange(true)

        let monitor = LocalEventMonitor(events: [.keyDown, .flagsChanged]) { event in
            if event.keyCode == CGKeyCode.kVK_Escape {
                finishedObservingKeys(wasForced: true)
                return nil
            }

            if event.type == .keyDown, !event.isARepeat {
                // A regular (non-modifier) key completes the chord immediately:
                // current modifiers + this key.
                let mods = CGEventFlags(cocoaFlags: event.modifierFlags).keyCodes
                selectionKey = mods.union([event.keyCode])
                finishedObservingKeys()
                return nil
            }

            if event.type == .flagsChanged {
                let keycodes = CGEventFlags(cocoaFlags: event.modifierFlags).keyCodes
                selectionKey.formUnion(keycodes)

                // All modifiers released after some were pressed → commit a
                // modifier-only chord (e.g. Hyper on its own, or ⌥ + ⌥).
                if keycodes.isEmpty, !selectionKey.isEmpty {
                    finishedObservingKeys()
                    return nil
                }
            }

            return nil
        }
        monitor.start()
        eventMonitor = monitor
    }

    private func finishedObservingKeys(wasForced: Bool = false) {
        isActive = false

        if !wasForced, !selectionKey.isEmpty {
            validCurrentKey = selectionKey
        } else {
            selectionKey = validCurrentKey
        }

        eventMonitor?.stop()
        eventMonitor = nil
        onRecordingChange(false)
    }
}

private extension TriggerKeycorder {
    /// One rendered chip in the recorder.
    enum Token: Hashable {
        case hyper
        case modifier(CGKeyCode)
        case regular(CGKeyCode)
    }
}
