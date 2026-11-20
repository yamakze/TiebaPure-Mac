// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TiebaPure-Mac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TiebaPureMac", targets: ["TiebaPureMac"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "TiebaPureMac",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "TiebaPureMacTests", dependencies: ["TiebaPureMac"])
    ]
)
