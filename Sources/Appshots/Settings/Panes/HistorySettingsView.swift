import AppKit
import AppshotsCore
import Luminare
import SwiftUI

/// History pane: every captured appshot as a Loop-style grid of screenshot
/// thumbnails. Tapping a tile opens the Preview window; a corner checkbox (and
/// selection ring) drives multi-select for bulk delete, and each tile keeps a
/// context menu (open, copy, reveal, delete). App/window/time show on hover and
/// in the Preview. Lives in the fixed-width settings pane, so switching here never
/// resizes the window. Reuses `AppshotsModel`'s store-backed list/delete/clear.
struct HistorySettingsView: View {
    @Environment(AppshotsModel.self) private var model

    @State private var captures: [AppshotRecord] = []
    @State private var selection: Set<String> = []
    @State private var showClearAllConfirmation = false

    /// Fixed-size tiles, laid out as many-per-row as the fixed-width pane fits.
    private let gridColumns = [
        GridItem(.adaptive(minimum: HistoryTile.tileWidth, maximum: HistoryTile.tileWidth),
                 spacing: AppshotsTheme.Spacing.sm),
    ]

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
                LazyVGrid(columns: gridColumns, spacing: AppshotsTheme.Spacing.sm) {
                    ForEach(captures) { record in
                        HistoryTile(
                            record: record,
                            isSelected: selection.contains(record.id),
                            hasSelection: selection.isEmpty == false,
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

/// A single screenshot tile in the History grid. Tap opens the Preview; the
/// corner checkbox toggles multi-selection (shown on hover, while selected, or
/// whenever a selection is active) and a selection ring mirrors the state. The
/// app / window / time live in the hover tooltip and the context menu's actions.
private struct HistoryTile: View {
    var record: AppshotRecord
    var isSelected: Bool
    var hasSelection: Bool
    var toggle: () -> Void
    var open: () -> Void
    var copy: () -> Void
    var reveal: () -> Void
    var delete: () -> Void

    @State private var isHovering = false

    static let tileWidth: CGFloat = 108
    static let tileHeight: CGFloat = 68
    private let cornerRadius: CGFloat = AppshotsTheme.Radius.card

    var body: some View {
        Button(action: open) {
            CaptureThumbnail(
                url: record.screenshotURL,
                maxPixelSize: 320,
                width: Self.tileWidth,
                height: Self.tileHeight,
                cornerRadius: cornerRadius,
                placeholderFontSize: 20,
                showsBackground: true,
                showsBorder: false
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.appBorderSubtle,
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if isSelected || isHovering || hasSelection {
                checkbox.padding(5)
            }
        }
        .onHover { isHovering = $0 }
        .help(tooltip)
        .contextMenu {
            Button("Open Preview", action: open)
            Button("Copy Appshot", action: copy)
            Button("Reveal in Finder", action: reveal)
            Divider()
            Button(isSelected ? "Deselect" : "Select", action: toggle)
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var checkbox: some View {
        Button(action: toggle) {
            Group {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.white)
                }
            }
            .font(.system(size: 17))
            .shadow(color: .black.opacity(0.45), radius: 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Deselect" : "Select")
    }

    private var tooltip: String {
        let title = record.windowTitle.isEmpty
            ? record.appName
            : "\(record.appName) — \(record.windowTitle)"
        return "\(title)\n\(record.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
