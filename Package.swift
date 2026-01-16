// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IMFPlayerSwift",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "IMFPlayerSwift",
            targets: ["IMFPlayerSwift"]
        )
    ],
    targets: [
        // C/C++ target that contains dbopl.cpp and a tiny C API wrapper.
        .target(
            name: "DBOPLWrapper",
            path: "Sources/DBOPLWrapper",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include")
            ]
        ),

        .executableTarget(
            name: "IMFPlayerSwift",
            dependencies: ["DBOPLWrapper"],
            path: "Sources/IMFPlayerSwift"
        )
    ]
)
