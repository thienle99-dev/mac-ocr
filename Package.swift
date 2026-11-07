// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-ocr",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "mac-ocr", targets: ["mac-ocr"]),
    ],
    targets: [
        .executableTarget(name: "mac-ocr"),
    ]
)
