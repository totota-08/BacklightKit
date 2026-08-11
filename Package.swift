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
        // Examples — run with `swift run example-morse SOS` / `swift run example-typeglow`.
        .executableTarget(
            name: "example-morse",
            dependencies: ["MacKeyboardBacklight"],
            path: "examples/morse"
        ),
        .executableTarget(
            name: "example-typeglow",
            dependencies: ["MacKeyboardBacklight"],
            path: "examples/typeglow"
        ),
        .testTarget(
            name: "MacKeyboardBacklightTests",
            dependencies: ["MacKeyboardBacklight"]
        ),
    ]
)
