// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Notchflow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Notchflow", targets: ["Notchflow"]),
    ],
    targets: [
        .executableTarget(
            name: "Notchflow",
            path: "Sources/Notchflow"
        ),
        .testTarget(
            name: "NotchflowTests",
            dependencies: ["Notchflow"],
            path: "Tests/NotchflowTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
