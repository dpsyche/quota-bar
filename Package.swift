// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "QuotaBar",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
    .executable(name: "QuotaBar", targets: ["QuotaBar"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.12.0")
  ],
  targets: [
    .target(name: "QuotaBarCore"),
    .executableTarget(
      name: "QuotaBar",
      dependencies: ["QuotaBarCore"]
    ),
    .testTarget(
      name: "QuotaBarCoreTests",
      dependencies: [
        "QuotaBarCore",
        .product(name: "Testing", package: "swift-testing"),
      ],
      resources: [.process("Fixtures")]
    ),
  ]
)
