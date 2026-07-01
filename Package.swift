// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "appshots",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Appshots", targets: ["Appshots"]),
        .executable(name: "appshotsctl", targets: ["AppshotsCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        // Luminare is Loop's design-system package; pinned to the exact revision Loop
        // tracks on `main` for a reproducible, pixel-matching build.
        .package(
            url: "https://github.com/MrKai77/Luminare",
            revision: "25056d7ac24b9a45a4225ea36da90329ea16d9a1"
        ),
    ],
    targets: [
        .target(
            name: "AppshotsCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .executableTarget(
            name: "Appshots",
            dependencies: [
                "AppshotsCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Luminare", package: "Luminare"),
            ],
            exclude: [
                "Configuration",
                "Vendor/PermissionFlow/LICENSE",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "AppshotsCLI",
            dependencies: [
                "AppshotsCore",
            ]
        ),
        .testTarget(
            name: "AppshotsCoreTests",
            dependencies: [
                "AppshotsCore",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
