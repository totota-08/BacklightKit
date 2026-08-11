// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacKeyboardBacklight",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "MacKeyboardBacklight", targets: ["MacKeyboardBacklight"]),
        .executable(name: "kbdlight", targets: ["kbdlight"]),
    ],
    targets: [
        .target(name: "MacKeyboardBacklight"),
        .executableTarget(
            name: "kbdlight",
            dependencies: ["MacKeyboardBacklight"]
        ),
    ]
)
