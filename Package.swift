// swift-tools-version: 6.0
import PackageDescription

// The code shared by the host app and the extension, built as a package so that its unit tests run with
// `swift test`, without Xcode or signing. The Xcode project compiles the same Shared/ folder into both its targets.
let package = Package(
    name: "NextcloudAppleMail",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "NextcloudAppleMailShared", path: "Shared"),
        .testTarget(
            name: "NextcloudAppleMailSharedTests",
            dependencies: ["NextcloudAppleMailShared"],
            path: "tests/NextcloudAppleMailSharedTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
