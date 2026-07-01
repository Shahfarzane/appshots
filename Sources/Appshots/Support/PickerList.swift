import AppKit
import AppshotsCore
import Luminare
import SwiftUI

// Ported from Loop (github.com/MrKai77/Loop) — Loop/Utilities/PickerList.swift and
// Loop/Utilities/PickerListEventMonitorManager.swift. Stripped of Loop's `Scribe`
// logging and `Defaults`; the keyboard-navigation monitor uses Appshots'
// `LocalEventMonitor`. Used inside a `luminarePopover` to present a searchable,
// sectioned list of selectable items (rows transparent by default, filled on
// hover / selection) — Loop's action-picker look.

struct PickerList<Content, V>: View where Content: View, V: Hashable, V: Identifiable {
    @Environment(\.luminareDismiss) private var dismiss

    @Binding var selection: V
    @Binding var searchResults: [V]

    @State private var arrowSelection: V?
    /// Per-instance key so multiple picker lists never clobber each other's
    /// keyboard-navigation monitor.
    @State private var monitorID = UUID()

    private let proxy: ScrollViewProxy
    private let sections: [PickerSection<V>]
    private let content: (V) -> Content

    init(
        selection: Binding<V>,
        searchResults: Binding<[V]>,
        proxy: ScrollViewProxy,
        sections: [PickerSection<V>],
        @ViewBuilder content: @escaping (V) -> Content
    ) {
        self._selection = selection
        self._searchResults = searchResults
        self.sections = sections
        self.proxy = proxy
        self.content = content
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            if searchResults.isEmpty {
                sectionsView
            } else {
                searchResultsView
            }
        }
        .onChange(of: searchResults) { _, _ in arrowSelection = nil }
        .onAppear { setupEventMonitor(reader: proxy) }
        .onDisappear { PickerListEventMonitorManager.shared.removeMonitor(for: monitorID) }
    }

    private var sectionsView: some View {
        ForEach(sections) { section in
            Section {
                ForEach(section.items, id: \.self) { item in
                    PopoverPickerItem(
                        selection: $selection,
                        arrowSelection: arrowSelection,
                        item: item,
                        content: content
                    )
                    .id(item)
                }
            } header: {
                Text(section.title)
                    .foregroundStyle(.secondary)
                    .padding([.top, .horizontal], 6)
            }
        }
    }

    private var searchResultsView: some View {
        ForEach(searchResults) { item in
            PopoverPickerItem(
                selection: $selection,
                arrowSelection: arrowSelection,
                item: item,
                content: content
            )
            .id(item)
        }
    }

    private func setupEventMonitor(reader: ScrollViewProxy) {
        PickerListEventMonitorManager.shared.addMonitor(for: monitorID, matching: [.keyDown]) { event in
            switch event.keyCode {
            case .kVK_DownArrow:
                updateArrowSelection(increment: true, reader: reader)
            case .kVK_UpArrow:
                updateArrowSelection(increment: false, reader: reader)
            case .kVK_Return:
                if let arrowSelection {
                    selection = arrowSelection
                    dismiss()
                }
            case .kVK_Escape:
                dismiss()
            default:
                return event
            }
            return nil
        }
    }

    private func updateArrowSelection(increment: Bool, reader: ScrollViewProxy) {
        let items = searchResults.isEmpty ? sections.flatMap(\.items) : searchResults
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex(where: { $0 == arrowSelection }) ?? (increment ? -1 : items.count)
        let nextIndex = currentIndex + (increment ? 1 : -1)
        guard nextIndex >= 0, nextIndex < items.count else { return }

        let newSelection = items[nextIndex]
        arrowSelection = newSelection
        reader.scrollTo(newSelection, anchor: .center)
    }
}

struct PopoverPickerItem<Content, V>: View where Content: View, V: Hashable {
    @Environment(\.luminareDismiss) private var dismiss

    @Binding var selection: V
    let arrowSelection: V?
    let item: V
    let content: (V) -> Content

    private var isSelected: Bool {
        selection == item || arrowSelection == item
    }

    var body: some View {
        Button {
            selection = item
            dismiss()
        } label: {
            content(item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.luminare(overrideIsHovering: isSelected))
        .luminareFilledStates([.hovering, .pressed])
        .luminareBorderedStates(.hovering)
    }
}

struct PickerSection<V>: Identifiable, Hashable where V: Hashable, V: Identifiable {
    var id: String { title }

    let title: String
    let items: [V]

    init(_ title: String, _ items: [V]) {
        self.title = title
        self.items = items
    }
}

/// Owns the keyboard-navigation `LocalEventMonitor`(s) for open picker lists. Torn
/// down on the list's `onDisappear` (Loop's documented leak gotcha).
@MainActor
final class PickerListEventMonitorManager {
    static let shared = PickerListEventMonitorManager()
    private var monitors: [AnyHashable: LocalEventMonitor] = [:]

    func addMonitor(
        for id: AnyHashable,
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) {
        removeMonitor(for: id)
        let monitor = LocalEventMonitor(events: mask, handler: handler)
        monitor.start()
        monitors[id] = monitor
    }

    func removeMonitor(for id: AnyHashable) {
        guard let monitor = monitors.removeValue(forKey: id) else { return }
        monitor.stop()
    }

    func removeAllMonitors() {
        monitors.forEach { $0.value.stop() }
        monitors.removeAll()
    }
}
