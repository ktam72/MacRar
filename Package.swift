// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "appMacRar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "appMacRar",
            dependencies: [],
            cSettings: [
                .headerSearchPath("Libs/unrar"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
                .define("RAR_SMP"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("unrar", .when(platforms: [.macOS])),
                .unsafeFlags(["-L", "Libs/unrar"], .when(platforms: [.macOS])),
            ]
        )
    ]
)
