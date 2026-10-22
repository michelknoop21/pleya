// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "cupertino_http",
  platforms: [.iOS("13.0"), .macOS("10.15")],
  products: [.library(name: "cupertino-http", targets: ["cupertino_http"])],
  dependencies: [],
  targets: [.target(name: "cupertino_http", path: "Sources/cupertino_http", cSettings: [.unsafeFlags(["-fobjc-arc"])])]
)
