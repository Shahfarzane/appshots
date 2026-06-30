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
    @State private var copied = false
    @State private var saved = false

    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0
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
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        ProgressView().controlSize(.large)
                    }
                }
                // Size the image to the zoom level (so zoom-out shrinks it),
                // then keep the scroll content at least the viewport size so the
                // shrunk image stays centered.
                .frame(width: geo.size.width * zoom, height: geo.size.height * zoom)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Text("\(Int((zoom * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 40)

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
        }
        let axURL = record.axTextURL
        text = await Task.detached(priority: .utility) {
            (try? String(contentsOf: axURL, encoding: .utf8)) ?? ""
        }.value
    }
}
