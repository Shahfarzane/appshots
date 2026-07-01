import AppKit
import AppshotsCore
import Luminare
import SwiftUI

/// History pane: every captured appshot as a rich, selectable row — the same
/// information the menu-bar popover shows (thumbnail, app, window title, time)
/// plus per-item actions (open, copy, reveal, delete) and bulk select/clear.
/// Lives in the fixed-width settings pane, so switching here never resizes the
/// window. Reuses `AppshotsModel`'s store-backed list/delete/clear logic.
struct HistorySettingsView: View {
    @Environment(AppshotsModel.self) private var model

    @State private var captures: [AppshotRecord] = []
    @State private var selection: Set<String> = []
    @State private var showClearAllConfirmation = false

    var body: some View {
        LuminareForm {
            LuminareSection {
                LuminareButtonRow {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected {
                            selection.removeAll()
                        } else {
                            selection = Set(captures.map(\.id))
                        }
                    }
                    .disabled(captures.isEmpty)

                    Button("Delete (\(selection.count))") {
                        model.deleteSelected(selection)
                        selection.removeAll()
                    }
                    .disabled(selection.isEmpty)

                    Button("Clear All", role: .destructive) {
                        showClearAllConfirmation = true
                    }
                    .disabled(captures.isEmpty)
                }
            }

            if captures.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: AppshotsTheme.Spacing.sm) {
                    ForEach(captures) { record in
                        HistoryRow(
                            record: record,
                            isSelected: selection.contains(record.id),
                            toggle: { toggleSelection(record.id) },
                            open: { model.openPreview?(record) },
                            copy: { model.copyAppshotMarkup(for: record) },
                            reveal: { reveal(record) },
                            delete: {
                                model.deleteSelected([record.id])
                                selection.remove(record.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, AppshotsTheme.Spacing.xs)
                .padding(.vertical, AppshotsTheme.Spacing.sm)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: model.historyVersion) { _, _ in reload() }
        .alert("Clear All History?", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                model.clearAllHistory()
                selection.removeAll()
            }
        } message: {
            Text("This permanently deletes every saved appshot. This cannot be undone.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppshotsTheme.Spacing.sm) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No appshots yet")
                .fontWeight(.medium)
            Text("Captured appshots will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var allSelected: Bool {
        captures.isEmpty == false && selection.count == captures.count
    }

    private func reload() {
        captures = model.allCaptures()
        selection = selection.intersection(Set(captures.map(\.id)))
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Reveals the capture's screenshot (or its folder) in Finder.
    private func reveal(_ record: AppshotRecord) {
        let url = record.screenshotURL ?? URL(fileURLWithPath: record.directoryPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// A rich history row: selection checkbox, thumbnail, app/window/time metadata,
/// and trailing per-item actions. Clicking the body opens the Preview window.
private struct HistoryRow: View {
    var record: AppshotRecord
    var isSelected: Bool
    var toggle: () -> Void
    var open: () -> Void
    var copy: () -> Void
    var reveal: () -> Void
    var delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Deselect" : "Select")

            Button(action: open) {
                HStack(spacing: 12) {
                    CaptureThumbnail(
                        url: record.screenshotURL,
                        maxPixelSize: 240,
                        width: 92,
                        height: 60,
                        cornerRadius: AppshotsTheme.Radius.thumbnail,
                        placeholderFontSize: 20,
                        showsBackground: true,
                        showsBorder: false
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.appName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(record.windowTitle.isEmpty ? "Untitled window" : record.windowTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open preview")

            menu
                .opacity(isHovering ? 1 : 0.6)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.appSurfaceSelected : Color.appSurfaceSubtle)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Color.appBorderSelected : Color.appBorderSubtle,
                            lineWidth: 1
                        )
                }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Preview", action: open)
            Button("Copy Appshot", action: copy)
            Button("Reveal in Finder", action: reveal)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var menu: some View {
        Menu {
            Button("Open Preview", systemImage: "arrow.up.left.and.arrow.down.right", action: open)
            Button("Copy Appshot", systemImage: "doc.on.doc", action: copy)
            Button("Reveal in Finder", systemImage: "folder", action: reveal)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("More actions")
    }
}
