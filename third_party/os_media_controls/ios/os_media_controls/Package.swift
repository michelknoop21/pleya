// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "os_media_controls",
  platforms: [.iOS("12.0"), .tvOS("13.0")],
  products: [.library(name: "os-media-controls", targets: ["os_media_controls"])],
  dependencies: [],
  targets: [.target(name: "os_media_controls", path: "Sources/os_media_controls")]
)
