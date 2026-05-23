// swift-tools-version: 5.9

import PackageDescription

let syphonFrameworkPath = "../Syphon-Framework/build/Release"

let package = Package(
    name: "syphon-mixer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SyphonMixer", targets: ["SyphonMixer"]),
        .library(name: "SyphonMixerCore", targets: ["SyphonMixerCore"])
    ],
    targets: [
        .target(
            name: "SyphonMixerCore"
        ),
        .executableTarget(
            name: "SyphonMixer",
            dependencies: ["SyphonMixerCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Syphon"),
                .unsafeFlags([
                    "-F\(syphonFrameworkPath)",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", syphonFrameworkPath
                ])
            ]
        ),
        .testTarget(
            name: "SyphonMixerCoreTests",
            dependencies: ["SyphonMixerCore"]
        )
    ]
)
