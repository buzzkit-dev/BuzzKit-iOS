// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuzzKit",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
    ],
    products: [
        .library(name: "BuzzKit", targets: ["BuzzKit"]),
        .library(name: "BuzzKitUI", targets: ["BuzzKitUI"]),
        .library(
            name: "BuzzKitNotificationServiceExtension",
            targets: ["BuzzKitNotificationServiceExtension"]
        ),
    ],
    targets: [
        .target(
            name: "BuzzKit",
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "BuzzKitUI",
            dependencies: ["BuzzKit"],
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "BuzzKitNotificationServiceExtension",
            dependencies: ["BuzzKit"],
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "BuzzKitTests",
            dependencies: ["BuzzKit", "BuzzKitNotificationServiceExtension"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
