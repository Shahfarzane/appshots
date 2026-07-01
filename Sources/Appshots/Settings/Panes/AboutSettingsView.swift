import AppKit
import Luminare
import SwiftUI

/// About + Updates pane, modeled on Loop's `AboutConfigurationView`: an icon
/// header, a full-width update button row, and a links row.
struct AboutSettingsView: View {
    @Environment(\.openURL) private var openURL

    private let updateManager = AppshotsUpdateManager.shared
    private let repositoryURL = URL(string: "https://github.com/Shahfarzane/appshots")!

    var body: some View {
        LuminareForm {
            LuminareSection {
                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appName)
                            .fontWeight(.medium)
                        Text("Version \(versionString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.trailing, 8)
                .padding(4)
            }

            LuminareSection("Updates") {
                LuminareButtonRow {
                    Button(updateButtonTitle) {
                        updateManager.runPrimaryAction()
                    }
                    .disabled(updateManager.updateState == .downloadingUpdate)
                }
                .luminareRoundingBehavior(top: true)

                Text(updateManager.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            LuminareSection("Links") {
                LuminareButtonRow {
                    Button("GitHub Repository") {
                        openURL(repositoryURL)
                    }
                }
            }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Appshots"
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    private var updateButtonTitle: String {
        switch updateManager.updateState {
        case .checkForUpdate: "Check for Updates"
        case .downloadingUpdate: "Downloading…"
        case .installUpdate: "Install Update"
        }
    }
}
