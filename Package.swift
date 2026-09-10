// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BITTyping",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "BITTyping", targets: ["BITTyping"]),
    ],
    targets: [
        .executableTarget(
            name: "BITTyping",
            resources: [
                .copy("Resources/courses"),
                .copy("Resources/lang"),
                .copy("Resources/keyboards"),
                .copy("Resources/sounds"),
                .copy("Resources/favico.png"),
            ]
        ),
    ]
)
