// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "gesturecam",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "gesturecam",
            path: "Sources/gesturecam",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/gesturecam/Info.plist"])
            ]
        )
    ]
)
