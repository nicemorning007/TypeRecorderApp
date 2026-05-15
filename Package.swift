// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TypeRecorder",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "TypeRecorder", targets: ["TypeRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "TypeRecorder",
            linkerSettings: [
                // Xcode 直接运行 SwiftPM executable 时不会自动生成 .app 主 bundle。
                // 把 Info.plist 嵌进 Mach-O 后，Bundle.main 可以读到 CFBundleIdentifier，
                // 避免运行时报 “missing main bundle identifier”。
                .unsafeFlags([
                    "-Xlinker",
                    "-sectcreate",
                    "-Xlinker",
                    "__TEXT",
                    "-Xlinker",
                    "__info_plist",
                    "-Xlinker",
                    "Packaging/Info.plist"
                ])
            ]
        )
    ]
)
