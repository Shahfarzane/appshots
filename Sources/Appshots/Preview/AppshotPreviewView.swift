import AppKit
import AppshotsCore
import SwiftUI

/// A Codex-style "Inspect image" overlay for a single capture: a large dark
/// surface showing the full-resolution screenshot with a zoom control, a
/// "View text" toggle that reveals the captured accessibility tree as
/// monospace plaintext, and copy / save / close actions.
struct AppshotPreviewView: View {
    enum Mode {
        case image
        case text
    }

    let record: AppshotRecord
    let model: AppshotsModel
    var onClose: () -> Void = {}

    @State private var mode: Mode = .image
    @State private var image: NSImage?
    @State private var text: String = ""
    @State private var zoom: CGFloat = 1.0
    /// Bumping this asks the scroll view to re-fit the image to the viewport.
    @State private var fitToken = 0
    @State private var copied = false
    @State private var saved = false

    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 6.0
    private let zoomStep: CGFloat = 0.25

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                content
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .task(id: record.id) { await load() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .foregroundStyle(.white.opacity(0.7))
            Text("Inspect image")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            if mode == .image {
                zoomControl.padding(.leading, 8)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = (mode == .image) ? .text : .image
                }
            } label: {
                Text(mode == .image ? "View text" : "View image")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(mode == .text ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(mode == .text
                            ? Color(red: 0.97, green: 0.78, blue: 0.81)
                            : Color.white.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .help(mode == .image ? "View accessibility text" : "View image")

            circleButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") { copy() }
            circleButton(saved ? "checkmark" : "arrow.down.to.line", help: "Save to Downloads") { saveImage() }
            circleButton("xmark", help: "Close") { onClose() }
        }
        .padding(.leading, 80) // clear the traffic-light controls
        .padding(.trailing, 16)
        .padding(.vertical, 12)
    }

    private func circleButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .image:
            imageView
        case .text:
            textView
        }
    }

    private var imageView: some View {
        Group {
            if let image {
                ZoomableImageView(
                    image: image,
                    magnification: $zoom,
                    fitToken: fitToken,
                    minMagnification: minZoom,
                    maxMagnification: maxZoom
                )
            } else if record.screenshotURL == nil {
                // Text-only captures (no screenshot artifact) have nothing to
                // load; a spinner here would spin forever.
                Text("No screenshot captured")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(zoomShortcuts)
    }

    /// Zero-size, invisible buttons that give the preview standard zoom key
    /// equivalents (⌘+/⌘=/⌘- zoom, ⌘0 fit, ⌘1 actual size).
    private var zoomShortcuts: some View {
        ZStack {
            Button("") { setZoom(zoom + zoomStep) }.keyboardShortcut("+", modifiers: .command)
            Button("") { setZoom(zoom + zoomStep) }.keyboardShortcut("=", modifiers: .command)
            Button("") { setZoom(zoom - zoomStep) }.keyboardShortcut("-", modifiers: .command)
            Button("") { fit() }.keyboardShortcut("0", modifiers: .command)
            Button("") { setZoom(1.0) }.keyboardShortcut("1", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var textView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("plaintext")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Text(text.isEmpty ? "No accessibility text captured." : text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(22)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var zoomControl: some View {
        HStack(spacing: 10) {
            Button { setZoom(zoom - zoomStep) } label: {
                Image(systemName: "minus")
            }
            .disabled(zoom <= minZoom)

            Button { fit() } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44)
            }
            .help("Fit to window")

            Button { setZoom(zoom + zoomStep) } label: {
                Image(systemName: "plus")
            }
            .disabled(zoom >= maxZoom)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }

    // MARK: - Actions

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, minZoom), maxZoom)
    }

    /// Requests a re-fit of the image to the current viewport.
    private func fit() {
        fitToken += 1
    }

    private func copy() {
        switch mode {
        case .image:
            model.copyAppshotMarkup(for: record)
        case .text:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }

    private func saveImage() {
        guard let source = record.screenshotURL,
              let data = try? Data(contentsOf: source) else { return }

        let fileManager = FileManager.default
        let downloads = (try? fileManager.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        let destination = uniqueURL(in: downloads, fileName: suggestedFileName)
        do {
            try data.write(to: destination)
            saved = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                saved = false
            }
        } catch {
        }
    }

    private func uniqueURL(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private var suggestedFileName: String {
        let base = record.appName.isEmpty ? "Appshot" : record.appName
        let safe = base.replacingOccurrences(of: "/", with: "-")
        return "\(safe) appshot.png"
    }

    private func load() async {
        if let url = record.screenshotURL {
            image = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
        } else {
            // Nothing to inspect in image mode; open on the text the capture
            // actually has.
            mode = .text
        }
        let axURL = record.axTextURL
        text = await Task.detached(priority: .utility) {
            (try? String(contentsOf: axURL, encoding: .utf8)) ?? ""
        }.value
    }
}

// MARK: - Zoomable image (real NSScrollView magnification)

/// An `NSScrollView`-backed image view with native magnification: pinch-to-zoom,
/// scroll-to-pan, smart-magnify (double-tap), and programmatic zoom driven by the
/// `magnification` binding (the +/- buttons and ⌘± shortcuts). `magnification`
/// is the true scale where `1.0` == the image's natural size (100%). The image
/// is centered when it is smaller than the viewport, and fit to the viewport on
/// first appearance and whenever `fitToken` changes (the ⌘0 / "%" affordance).
///
/// This replaces the previous viewport-relative `.frame` math, which produced a
/// fictional percentage and never actually magnified the pixels.
private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var magnification: CGFloat
    let fitToken: Int
    let minMagnification: CGFloat
    let maxMagnification: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let clipView = CenteringClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minMagnification
        scrollView.maxMagnification = maxMagnification
        scrollView.usesPredominantAxisScrolling = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.image = image
        imageView.setFrameSize(image.size)
        scrollView.documentView = imageView

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.liveMagnifyEnded(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        // Fit once the scroll view has a real size.
        DispatchQueue.main.async { context.coordinator.fitToViewport() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        let coordinator = context.coordinator
        if let imageView = coordinator.imageView, imageView.image !== image {
            imageView.image = image
            imageView.setFrameSize(image.size)
            DispatchQueue.main.async { coordinator.fitToViewport() }
        }

        // A re-fit was requested (⌘0 / tapping the percentage).
        if fitToken != coordinator.lastFitToken {
            coordinator.lastFitToken = fitToken
            DispatchQueue.main.async { coordinator.fitToViewport() }
            return
        }

        // Apply an externally-driven magnification (buttons / ⌘±) without echoing
        // it back through the binding.
        if abs(scrollView.magnification - magnification) > 0.001 {
            coordinator.apply(magnification: magnification, centeredAtImageMidpoint: true)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ZoomableImageView
        weak var scrollView: NSScrollView?
        weak var imageView: NSImageView?
        var lastFitToken: Int
        private var fitAttempts = 0

        init(_ parent: ZoomableImageView) {
            self.parent = parent
            lastFitToken = parent.fitToken
        }

        /// Reflects a user pinch back into the SwiftUI binding once it settles.
        @objc func liveMagnifyEnded(_ notification: Notification) {
            guard let scrollView else { return }
            syncBinding(scrollView.magnification)
        }

        /// Fits the whole image inside the viewport (never above 100%), centering
        /// it. Retries a bounded number of times if the scroll view has not been
        /// laid out yet (zero bounds) when first called.
        func fitToViewport() {
            guard let scrollView, let imageView, let image = imageView.image else { return }
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let viewport = scrollView.bounds.size
            guard viewport.width > 0, viewport.height > 0 else {
                guard fitAttempts < 10 else { return }
                fitAttempts += 1
                DispatchQueue.main.async { [weak self] in self?.fitToViewport() }
                return
            }
            fitAttempts = 0

            let fit = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
            apply(magnification: min(fit, 1.0), centeredAtImageMidpoint: true)
        }

        /// Sets the magnification (clamped), centered on the image, and syncs the binding.
        func apply(magnification: CGFloat, centeredAtImageMidpoint: Bool) {
            guard let scrollView, let imageView else { return }
            let clamped = min(max(magnification, parent.minMagnification), parent.maxMagnification)
            if centeredAtImageMidpoint {
                let center = NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
                scrollView.setMagnification(clamped, centeredAt: center)
            } else {
                scrollView.magnification = clamped
            }
            syncBinding(clamped)
        }

        /// Writes the value into the binding on the next runloop tick, so it never
        /// mutates SwiftUI state during a view update.
        private func syncBinding(_ value: CGFloat) {
            guard abs(parent.magnification - value) > 0.0001 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.magnification = value
            }
        }
    }
}

/// A clip view that keeps its document view centered when it is smaller than the
/// viewport (instead of pinning it to a corner), across all magnifications.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }

        let docFrame = documentView.frame
        if docFrame.width < rect.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if docFrame.height < rect.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }
        return rect
    }
}
