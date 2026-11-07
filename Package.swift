// swift-tools-version: 6.0
import PackageDescription

// The code shared by the host app and the extension, built as a package so that its unit tests run with
// `swift test`, without Xcode or signing. The Xcode project compiles the same Shared/ folder into both its targets.
let package = Package(
    name: "NextcloudMailExtension",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "NextcloudMailExtensionShared", path: "Shared"),
        .testTarget(
            name: "NextcloudMailExtensionSharedTests",
            dependencies: ["NextcloudMailExtensionShared"],
            path: "tests/NextcloudMailExtensionSharedTests",
            resources: [.copy("Fixtures")]
        ),
        // Run against the test server in .env by scripts/test-nextcloud.sh, and skipped without it.
        .testTarget(
            name: "NextcloudServerTests",
            dependencies: ["NextcloudMailExtensionShared"],
            path: "tests/NextcloudServerTests"
        ),
        // The command-line tool for running Nextcloud requests by hand, through scripts/nextcloud.sh.
        .executableTarget(
            name: "ncme-nextcloud",
            dependencies: ["NextcloudMailExtensionShared"],
            path: "tools/ncme-nextcloud"
        ),
    ],
    swiftLanguageModes: [.v5]
)
