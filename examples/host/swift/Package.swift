// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftHost",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/WasmKit.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftHost",
            dependencies: [
                .product(name: "WasmKit", package: "WasmKit"),
            ],
            path: "Sources/SwiftHost"
        ),
    ]
)
