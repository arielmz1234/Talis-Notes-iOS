// swift-tools-version: 6.0
import PackageDescription

// The app's logic that needs no screen: geometry, page layout, the library model, storage and the
// backup format. Kept apart from the app so its tests run quickly with `swift test`.
let package = Package(
  name: "TaliCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "TaliCore", targets: ["TaliCore"])],
  targets: [
    .target(name: "TaliCore"),
    .testTarget(name: "TaliCoreTests", dependencies: ["TaliCore"]),
  ]
)
