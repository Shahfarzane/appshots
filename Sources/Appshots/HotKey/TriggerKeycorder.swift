import AppshotsCore
import Luminare
import SwiftUI

/// The trigger-key chip display + "Change" button, ported faithfully from Loop's
/// `TriggerKeycorder` (github.com/MrKai77/Loop): a `ZStack` of the chip indicator
/// and the "Change" button — both under `.buttonStyle(.luminare(overrideUseMainStyle:))`
/// — with width measurement that hides "Change" when the chips would overlap it.
///
/// Behavior is adapted for Appshots: tapping the chips or "Change" opens the
/// trigger-config dropdown (rather than recording directly, as Loop does). A
/// `recordTrigger` bump (from the dropdown's "Custom…") starts recording any
/// chord; Escape or the window resigning active cancels.
struct TriggerKeycorder: View {
    @Environment(\.appearsActive) private var appearsActive

    let keyLimit = 5

    @Binding private var validCurrentKey: Set<CGKeyCode>
    @State private var selectionKey: Set<CGKeyCode>

    @State private var eventMonitor: LocalEventMonitor?
    @State private var shouldShake = false
    @State private var isActive = false

    @State private var totalWidth: CGFloat = 0
    @State private var triggerKeyIndicatorWidth: CGFloat = 0
    @State private var changeButtonWidth: CGFloat = 0

    /// Opens the trigger-config dropdown (tap on the chips / "Change").
    private let onRequestPicker: () -> Void
    /// Called with `true` while recording, so the caller can pause the global
    /// hot-key monitor.
    private let onRecordingChange: (Bool) -> Void
    /// Bumped to begin recording (from the dropdown's "Custom…" entry).
    private let recordTrigger: Int

    private var sortedKeys: [CGKeyCode] { selectionKey.sorted() }

    /// True when the chips would overlap the "Change" button, so it should hide.
    private var shouldHideChangeButton: Bool {
        let totalLeadingWidth = triggerKeyIndicatorWidth + 4.0
        return (totalWidth - totalLeadingWidth) < changeButtonWidth
    }

    init(
        _ key: Binding<Set<CGKeyCode>>,
        recordTrigger: Int = 0,
        onRequestPicker: @escaping () -> Void,
        onRecordingChange: @escaping (Bool) -> Void
    ) {
        self._validCurrentKey = key
        self._selectionKey = State(initialValue: key.wrappedValue)
        self.recordTrigger = recordTrigger
        self.onRequestPicker = onRequestPicker
        self.onRecordingChange = onRecordingChange
    }

    var body: some View {
        ZStack {
            triggerKeyIndicator
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { triggerKeyIndicatorWidth = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)

            changeButton
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { changeButtonWidth = $0 }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(shouldHideChangeButton ? 0 : 1)
        }
        .buttonStyle(.luminare(overrideUseMainStyle: true))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { totalWidth = $0 }
        .onChange(of: recordTrigger) { _, _ in
            if !isActive { startObservingKeys() }
        }
    }

    private var triggerKeyIndicator: some View {
        Button(action: primaryAction) {
            if selectionKey.isEmpty {
                Text(isActive ? "Set a trigger key…" : "None")
                    .frame(height: 32)
                    .padding(.horizontal, 12)
            } else {
                HStack(spacing: 12) {
                    ForEach(sortedKeys, id: \.self) { key in
                        TriggerKeycorderKeyView(key: key)

                        if key != sortedKeys.last {
                            Divider()
                                .padding(.vertical, 1)
                        }
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, 12)
            }
        }
        .modifier(ShakeEffect(shakes: shouldShake ? 2 : 0))
        .animation(Animation.default, value: shouldShake)
        .onChange(of: appearsActive) { _, active in
            if !active, isActive { finishedObservingKeys(wasForced: true) }
        }
        .onDisappear {
            // Stop recording if the view is torn down mid-record (e.g. switching
            // settings tabs); otherwise the LocalEventMonitor leaks and silently
            // swallows all keyboard input. `appearsActive` only covers the window
            // going inactive, not view removal.
            if isActive { finishedObservingKeys(wasForced: true) }
        }
        .onChange(of: validCurrentKey) { _, newValue in
            if selectionKey != newValue { selectionKey = newValue }
        }
        .fixedSize()
    }

    private var changeButton: some View {
        Button(action: primaryAction) {
            Text("Change")
                .frame(height: 32)
                .padding(.horizontal, 12)
        }
        .fixedSize()
    }

    /// While recording, a tap cancels; otherwise it opens the config dropdown.
    private func primaryAction() {
        if isActive {
            finishedObservingKeys(wasForced: true)
        } else {
            onRequestPicker()
        }
    }

    // MARK: - Recording

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
                // A regular (non-modifier) key completes the chord immediately.
                let mods = CGEventFlags(cocoaFlags: event.modifierFlags).keyCodes
                selectionKey = mods.union([event.keyCode])
                finishedObservingKeys()
                return nil
            }

            if event.type == .flagsChanged {
                let keycodes = CGEventFlags(cocoaFlags: event.modifierFlags).keyCodes
                selectionKey.formUnion(keycodes)

                // All modifiers released after some were pressed → commit.
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
        var willSet = !wasForced

        if selectionKey.count > keyLimit {
            willSet = false
            shake()
        }

        isActive = false

        if willSet, !selectionKey.isEmpty {
            validCurrentKey = selectionKey
        } else {
            selectionKey = validCurrentKey
        }

        eventMonitor?.stop()
        eventMonitor = nil
        onRecordingChange(false)
    }

    private func shake() {
        shouldShake.toggle()
    }
}

/// A single key-cap chip, ported from Loop's `TriggerKeycorderKeyView`. Modifier
/// keys render as `Left ⌥` / `Right ⌥`; a regular key renders its glyph.
struct TriggerKeycorderKeyView: View {
    let key: CGKeyCode

    private static let defaultIconName = "exclamationmark.circle.fill"

    var body: some View {
        HStack(spacing: 4) {
            if let modifierImage = key.modifierSystemImage {
                let side = key.isModifierOnRightSide ? "Right" : "Left"
                let keyImage = Image(systemName: modifierImage)
                Text("\(side) \(keyImage)")
            } else {
                Text(key.humanReadable ?? "?")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
    }
}
