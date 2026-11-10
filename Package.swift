// swift-tools-version:5.9
import PackageDescription

// Depo kökü (`nafrucom/nafru-email-sdks`): Swift kaynakları `swift/` altında. Modül ve istemci tipi `NafruEmail`.
let package = Package(
    name: "nafru-email",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [.library(name: "NafruEmail", targets: ["NafruEmail"])],
    targets: [
        .target(name: "NafruEmail", path: "swift/Sources/NafruEmail"),
        .testTarget(name: "NafruEmailTests", dependencies: ["NafruEmail"], path: "swift/Tests/NafruEmailTests")
    ]
)
