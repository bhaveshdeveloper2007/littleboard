// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Littleboard",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Littleboard", targets: ["Littleboard"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/SkyLightWindow", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Littleboard",
            dependencies: [.product(name: "SkyLightWindow", package: "SkyLightWindow")],
            path: "Sources/Littleboard",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOBluetooth"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
