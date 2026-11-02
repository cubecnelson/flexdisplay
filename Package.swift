// swift-tools-version: 5.9
// Alternative entry if you prefer Swift Package Manager executable.
// Menu-bar apps are smoother as an .app via XcodeGen / Xcode; this Package
// is mainly for compiling sources in isolation (`swift build` on macOS).
import PackageDescription

let package = Package(
    name: "FlexDisplay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FlexDisplay", targets: ["FlexDisplay"])
    ],
    targets: [
        .executableTarget(
            name: "FlexDisplay",
            path: "Sources/FlexDisplay"
        )
    ]
)
