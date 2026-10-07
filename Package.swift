// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// swiftlint:disable explicit_acl explicit_top_level_acl
let swiftSettings: [SwiftSetting] = [
  SwiftSetting.enableExperimentalFeature("AccessLevelOnImport"),
  SwiftSetting.enableExperimentalFeature("BitwiseCopyable"),
  SwiftSetting.enableExperimentalFeature("IsolatedAny"),
  SwiftSetting.enableExperimentalFeature("MoveOnlyPartialConsumption"),
  SwiftSetting.enableExperimentalFeature("NestedProtocols"),
  SwiftSetting.enableExperimentalFeature("NoncopyableGenerics"),
  SwiftSetting.enableExperimentalFeature("TransferringArgsAndResults"),
  SwiftSetting.enableExperimentalFeature("VariadicGenerics"),

  SwiftSetting.enableUpcomingFeature("FullTypedThrows"),
  SwiftSetting.enableUpcomingFeature("InternalImportsByDefault")
]

let package = Package(
  name: "DataThespian",
  platforms: [.iOS(.v17), .macCatalyst(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1), .watchOS(.v10)],
  products: [
    .library(
      name: "DataThespian",
      targets: ["DataThespian"]
    )
  ],
  dependencies: [
    // The fork's fixes are on its trig-fixes branch, which carries no version tag above the
    // upstream 1.0.0. Pin the fixed revision; switch to `from:` once the fork tags a release.
    .package(
      url: "https://github.com/bradwindy/FelinePine.git",
      revision: "611c626d33ae20ab6058f33f8c955938931575be"
    ),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
  ],
  targets: [
    .target(
      name: "DataThespian",
      dependencies: ["FelinePine"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "DataThespianTests",
      dependencies: [
        "DataThespian"
      ]
    )
  ]
)
// swiftlint:enable explicit_acl explicit_top_level_acl
