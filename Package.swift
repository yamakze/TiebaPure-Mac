// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TiebaPure-Mac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TiebaPureMac", targets: ["TiebaPureMac"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1")
    ],
    targets: [
        .executableTarget(
            name: "TiebaPureMac",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .testTarget(name: "TiebaPureMacTests", dependencies: ["TiebaPureMac"])
    ]
)
