import AppshotsCore
import Luminare
import SwiftUI

/// Trigger-key configuration, after Loop's Keybinds screen: the current chord is
/// shown as key-cap chips, and a "Change" button opens a Loop-style searchable
/// dropdown of trigger configurations (Option / Command / Shift / Control, plus
/// "Custom…" to record any chord). The chip display and dropdown are faithful
/// ports of Loop's `TriggerKeycorder` and `DirectionPickerView`.
struct TriggerKeyConfigurationView: View {
    @Binding private var triggerKey: Set<CGKeyCode>
    private let onRecordingChange: (Bool) -> Void

    @State private var showPicker = false
    /// Bumped to start the chip recorder when "Custom…" is chosen.
    @State private var recordToken = 0

    init(triggerKey: Binding<Set<CGKeyCode>>, onRecordingChange: @escaping (Bool) -> Void) {
        self._triggerKey = triggerKey
        self.onRecordingChange = onRecordingChange
    }

    private var currentConfig: TriggerConfig { TriggerConfig(triggerKey: triggerKey) }

    var body: some View {
        LuminareSection("Trigger Key") {
            TriggerKeycorder(
                $triggerKey,
                recordTrigger: recordToken,
                onRequestPicker: { showPicker = true },
                onRecordingChange: onRecordingChange
            )
            .luminareBorderedStates(.normal)
            .luminarePopover(isPresented: $showPicker, arrowEdge: .bottom, shouldHideAnchor: true) {
                TriggerConfigPickerView(current: currentConfig, onSelect: apply)
            }
        }
        .luminareBorderedStates(.none)
    }

    /// Applies a chosen configuration: presets write their chord directly; the
    /// "Custom…" entry starts the chip recorder.
    private func apply(_ config: TriggerConfig) {
        if let keys = config.keys {
            triggerKey = keys
        } else {
            recordToken += 1
        }
    }
}

// MARK: - Trigger configurations

/// The trigger configurations offered by the "Change" dropdown. Presets are
/// both-sides modifier chords; `.custom` records any chord.
enum TriggerConfig: String, CaseIterable, Identifiable, Hashable {
    case option
    case command
    case shift
    case control
    case custom

    var id: String { rawValue }

    static let optionPair: Set<CGKeyCode> = [.kVK_Option, .kVK_RightOption]
    static let commandPair: Set<CGKeyCode> = [.kVK_Command, .kVK_RightCommand]
    static let shiftPair: Set<CGKeyCode> = [.kVK_Shift, .kVK_RightShift]
    static let controlPair: Set<CGKeyCode> = [.kVK_Control, .kVK_RightControl]

    /// The configuration matching a stored trigger, falling back to `.custom`.
    init(triggerKey: Set<CGKeyCode>) {
        switch triggerKey {
        case Self.optionPair: self = .option
        case Self.commandPair: self = .command
        case Self.shiftPair: self = .shift
        case Self.controlPair: self = .control
        default: self = .custom
        }
    }

    var title: String {
        switch self {
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        case .control: "Control"
        case .custom: "Custom…"
        }
    }

    /// SF Symbol shown beside the title in the dropdown.
    var icon: String {
        switch self {
        case .option: "option"
        case .command: "command"
        case .shift: "shift"
        case .control: "control"
        case .custom: "slider.horizontal.3"
        }
    }

    /// The both-sides chord for a preset, or `nil` for `.custom` (record your own).
    var keys: Set<CGKeyCode>? {
        switch self {
        case .option: Self.optionPair
        case .command: Self.commandPair
        case .shift: Self.shiftPair
        case .control: Self.controlPair
        case .custom: nil
        }
    }
}

/// The searchable trigger-config dropdown, ported from Loop's `DirectionPickerView`
/// (a search field + a `PickerList` of sectioned, icon+label rows). Selecting a row
/// commits it and dismisses the popover.
private struct TriggerConfigPickerView: View {
    let current: TriggerConfig
    let onSelect: (TriggerConfig) -> Void

    @State private var searchText = ""
    @State private var searchResults: [TriggerConfig] = []
    @FocusState private var isSearchFocused: Bool

    private var sections: [PickerSection<TriggerConfig>] {
        [PickerSection("General", [.option, .command, .shift, .control, .custom])]
    }

    private var sectionItems: [TriggerConfig] {
        sections.flatMap(\.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    PickerList(
                        selection: Binding(get: { current }, set: { onSelect($0) }),
                        searchResults: $searchResults,
                        proxy: proxy,
                        sections: sections
                    ) { config in
                        HStack(spacing: 8) {
                            Image(systemName: config.icon)
                                .frame(width: 20)
                            Text(config.title)
                        }
                        .padding(.horizontal, 6)
                    }
                    .padding(8)
                    .luminareCornerRadius(12)
                }
            }
        }
        .frame(width: 260, height: 290)
        .onAppear {
            searchText = ""
            computeSearchResults()
            Task { @MainActor in isSearchFocused = true }
        }
        .onChange(of: searchText) { _, _ in computeSearchResults() }
    }

    private func computeSearchResults() {
        guard searchText.isEmpty == false else {
            searchResults = []
            return
        }
        let key = searchText.lowercased()
        searchResults = sectionItems
            .compactMap { item -> (TriggerConfig, Int)? in
                fuzzyScore(item.title, key).map { (item, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Fuzzy match score (0 = prefix, 1 = substring, 2 = subsequence), ported from
    /// Loop's `DirectionPickerView.fuzzyScore`.
    private func fuzzyScore(_ text: String, _ pattern: String) -> Int? {
        let text = text.lowercased()
        let pattern = pattern.lowercased()

        if text.hasPrefix(pattern) { return 0 }
        if text.contains(pattern) { return 1 }

        var tIndex = text.startIndex
        var pIndex = pattern.startIndex
        while tIndex < text.endIndex, pIndex < pattern.endIndex {
            if text[tIndex] == pattern[pIndex] {
                pIndex = pattern.index(after: pIndex)
            }
            tIndex = text.index(after: tIndex)
        }
        return pIndex == pattern.endIndex ? 2 : nil
    }
}
