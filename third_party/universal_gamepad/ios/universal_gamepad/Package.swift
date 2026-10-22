// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "universal_gamepad",
  platforms: [.iOS("14.0"), .tvOS("14.0")],
  products: [.library(name: "universal-gamepad", targets: ["universal_gamepad"])],
  dependencies: [],
  targets: [.target(name: "universal_gamepad", path: "Sources/universal_gamepad")]
)
