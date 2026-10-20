// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FlowPaste",
    platforms: [.iOS(.v17)],
    products: [.library(name: "FlowPasteCore", targets: ["FlowPasteCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Modules/CSQLite"),
        .target(name: "FlowPasteCore", dependencies: ["CSQLite"], path: "Sources/Core"),
        .testTarget(name: "FlowPasteTests", dependencies: ["FlowPasteCore"], path: "Tests")
    ]
)
