import AppshotsCore
import Luminare
import SwiftUI

/// Trigger-key configuration. The capture trigger is a both-sides modifier
/// chord; users pick a preset (⌥ + ⌥, ⌘ + ⌘) or record their own via "Custom".
/// Laid out as a vertical selectable list, after Loop's Keybinds screen.
struct TriggerKeyConfigurationView: View {
    @Binding private var triggerKey: Set<CGKeyCode>
    private let onRecordingChange: (Bool) -> Void

    /// The user's last custom chord, kept independent of the live `triggerKey`
    /// so switching to a preset and back doesn't lose it.
    @State private var customKeys: Set<CGKeyCode>

    init(triggerKey: Binding<Set<CGKeyCode>>, onRecordingChange: @escaping (Bool) -> Void) {
        self._triggerKey = triggerKey
        self.onRecordingChange = onRecordingChange
        let initial = triggerKey.wrappedValue
        let isPreset = initial == TriggerKeyMode.optionPair || initial == TriggerKeyMode.commandPair
        self._customKeys = State(initialValue: isPreset ? [] : initial)
    }

    /// The preset implied by the current live trigger.
    private var mode: TriggerKeyMode { TriggerKeyMode(triggerKey: triggerKey) }

    /// Binding the custom recorder writes through: it updates the remembered
    /// custom chord *and* makes it the live trigger.
    private var customBinding: Binding<Set<CGKeyCode>> {
        Binding(
            get: { customKeys },
            set: { newValue in
                customKeys = newValue
                triggerKey = newValue
            }
        )
    }

    var body: some View {
        LuminareSection("Trigger Key") {
            VStack(spacing: 4) {
                presetRow(.option)
                presetRow(.command)
                customRow()
            }
            .padding(4)
        }
    }

    // MARK: - Rows

    private func presetRow(_ rowMode: TriggerKeyMode) -> some View {
        Button {
            triggerKey = rowMode.keys
        } label: {
            row(title: rowMode.title, selected: mode == rowMode) {
                keyPair(systemImage: rowMode.glyph)
            }
        }
        .buttonStyle(.plain)
    }

    private func customRow() -> some View {
        row(title: "Custom", selected: mode == .custom) {
            HStack(spacing: 6) {
                TriggerKeycorder(customBinding, onRecordingChange: onRecordingChange)

                if !customKeys.isEmpty {
                    Button {
                        resetCustom()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .frame(width: 28, height: 30)
                    }
                    .buttonStyle(.luminare)
                    .luminareCornerRadius(8)
                    .fixedSize()
                    .help("Clear the custom shortcut and reset to ⌥ + ⌥")
                }
            }
        }
    }

    /// Clears the recorded custom chord and falls back to the default trigger so
    /// capture keeps working.
    private func resetCustom() {
        customKeys = []
        triggerKey = TriggerKeyMode.optionPair
    }

    /// Shared row chrome: a title on the leading edge, trailing content, and a
    /// selection highlight (tinted fill + border) matching `LuminarePicker`.
    private func row(
        title: String,
        selected: Bool,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(selected ? 0.15 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0)
                )
        }
        .contentShape(.rect)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    /// A both-sides modifier shown as two chip boxes joined by "+", e.g. `[⌥] + [⌥]`.
    private func keyPair(systemImage: String) -> some View {
        HStack(spacing: 6) {
            keyChip(systemImage)
            Image(systemName: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
            keyChip(systemImage)
        }
        .fixedSize()
    }

    private func keyChip(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.callout)
            .frame(width: 34, height: 30)
            .luminareSurface()
            .luminareCornerRadius(8)
    }
}

/// The supported trigger presets. `.custom` lets the user record any chord.
enum TriggerKeyMode: CaseIterable, Equatable {
    case option
    case command
    case custom

    static let optionPair: Set<CGKeyCode> = [.kVK_Option, .kVK_RightOption]
    static let commandPair: Set<CGKeyCode> = [.kVK_Command, .kVK_RightCommand]

    /// Derives the preset that matches a stored trigger, falling back to `.custom`.
    init(triggerKey: Set<CGKeyCode>) {
        switch triggerKey {
        case Self.optionPair: self = .option
        case Self.commandPair: self = .command
        default: self = .custom
        }
    }

    var title: String {
        switch self {
        case .option: "Option"
        case .command: "Command"
        case .custom: "Custom"
        }
    }

    /// SF Symbol for the preset's modifier (presets only).
    var glyph: String {
        switch self {
        case .option: "option"
        case .command: "command"
        case .custom: "ellipsis"
        }
    }

    /// The both-sides chord for a preset (empty for `.custom`).
    var keys: Set<CGKeyCode> {
        switch self {
        case .option: Self.optionPair
        case .command: Self.commandPair
        case .custom: []
        }
    }
}
