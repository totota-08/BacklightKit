// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BacklightKit",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "BacklightKit", targets: ["BacklightKit"]),
        .executable(name: "backlit", targets: ["backlit"]),
    ],
    targets: [
        .target(name: "BacklightKit"),
        .executableTarget(
            name: "backlit",
            dependencies: ["BacklightKit"]
        ),
        // Examples — run with `swift run example-morse SOS` / `swift run example-typeglow`.
        .executableTarget(
            name: "example-morse",
            dependencies: ["BacklightKit"],
            path: "examples/morse"
        ),
        .executableTarget(
            name: "example-typeglow",
            dependencies: ["BacklightKit"],
            path: "examples/typeglow"
        ),
        .testTarget(
            name: "BacklightKitTests",
            dependencies: ["BacklightKit"]
        ),
    ]
)
