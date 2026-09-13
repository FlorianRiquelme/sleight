// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sleight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "sleight",
            path: "Sources/sleight",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/sleight/Info.plist"])
            ]
        ),
        .testTarget(name: "sleightTests", dependencies: ["sleight"], path: "Tests/sleightTests")
    ]
)
