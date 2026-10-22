// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "pleya_aware",
  platforms: [.iOS("15.0")],
  products: [.library(name: "pleya-aware", targets: ["pleya_aware"])],
  dependencies: [],
  targets: [.target(name: "pleya_aware", path: "Sources/pleya_aware")]
)
