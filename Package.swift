// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "KeyCanvas",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "AK47InspectorCore",
      targets: ["AK47InspectorCore"]
    ),
    .executable(
      name: "ak47-inspect",
      targets: ["AK47InspectorCLI"]
    ),
    .executable(
      name: "keycanvas",
      targets: ["AK47StudioApp"]
    ),
  ],
  targets: [
    .target(
      name: "AK47InspectorCore"
    ),
    .executableTarget(
      name: "AK47InspectorCLI",
      dependencies: ["AK47InspectorCore"]
    ),
    .executableTarget(
      name: "AK47StudioApp",
      dependencies: ["AK47InspectorCore"]
    ),
    .testTarget(
      name: "AK47InspectorCoreTests",
      dependencies: ["AK47InspectorCore"]
    ),
  ]
)
