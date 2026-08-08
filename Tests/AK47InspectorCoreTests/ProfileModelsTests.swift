import XCTest

@testable import AK47InspectorCore

final class ProfileModelsTests: XCTestCase {
  func testValidProfileRoundTripsThroughJSON() throws {
    let profile = makeValidProfile()

    let json = try ProfileJSONCodec.encodeString(profile)
    let decoded = try ProfileJSONCodec.decode(json)

    XCTAssertEqual(decoded, profile)
    XCTAssertTrue(decoded.validationIssues().isEmpty)
    XCTAssertTrue(json.contains("\"key-code\""))
    XCTAssertTrue(json.contains("\"key-down\""))
  }

  func testJSONEncodingIsDeterministic() throws {
    let profile = makeValidProfile()
    XCTAssertEqual(
      try ProfileJSONCodec.encode(profile),
      try ProfileJSONCodec.encode(profile)
    )
  }

  func testValidationCollectsIssuesAcrossAllDomains() {
    let invalid = DeviceProfile(
      schemaVersion: 99,
      identifier: " ",
      name: "",
      keymap: KeymapProfile(assignments: [
        KeyAssignment(layer: -1, position: -1, action: .macro(identifier: "missing")),
        KeyAssignment(layer: -1, position: -1, action: .keyCode(0)),
      ]),
      lighting: LightingProfile(
        effectIdentifier: " ",
        brightnessPercent: 101,
        speedPercent: -1,
        perKey: [
          PerKeyLighting(
            position: -1, color: RGBColor(red: 0, green: 0, blue: 0), intensityPercent: 101)
        ]
      ),
      macros: [
        MacroDefinition(
          identifier: "dup",
          name: "One",
          repeatCount: 0,
          events: [.keyUp(4), .delay(milliseconds: 0)]
        ),
        MacroDefinition(identifier: "dup", name: "Two"),
      ],
      tft: TFTProfile(
        enabled: true,
        canvasWidth: 0,
        canvasHeight: 9_000,
        frameRate: 0,
        assets: [
          DisplayAssetReference(
            identifier: "asset",
            resourceName: "../outside.bin",
            width: 0,
            height: 1,
            frameCount: 0
          )
        ],
        playlist: ["missing"],
        themeIdentifier: " ",
        message: String(repeating: "x", count: 129)
      ),
      settings: DeviceSettings(
        sleepTimeoutSeconds: -1,
        debounceMilliseconds: -1,
        reportRateHz: 0
      )
    )

    let codes = Set(invalid.validationIssues().map(\.code))

    XCTAssertTrue(codes.contains("unsupported-schema"))
    XCTAssertTrue(codes.contains("invalid-identifier"))
    XCTAssertTrue(codes.contains("invalid-name"))
    XCTAssertTrue(codes.contains("duplicate-assignment"))
    XCTAssertTrue(codes.contains("unknown-macro"))
    XCTAssertTrue(codes.contains("invalid-action"))
    XCTAssertTrue(codes.contains("invalid-effect"))
    XCTAssertTrue(codes.contains("invalid-percentage"))
    XCTAssertTrue(codes.contains("duplicate-macro"))
    XCTAssertTrue(codes.contains("invalid-repeat-count"))
    XCTAssertTrue(codes.contains("unmatched-key-up"))
    XCTAssertTrue(codes.contains("invalid-delay"))
    XCTAssertTrue(codes.contains("unsafe-resource-name"))
    XCTAssertTrue(codes.contains("unknown-asset"))
    XCTAssertTrue(codes.contains("invalid-theme"))
    XCTAssertTrue(codes.contains("message-too-long"))
    XCTAssertTrue(codes.contains("invalid-sleep-timeout"))
    XCTAssertTrue(codes.contains("invalid-debounce"))
    XCTAssertTrue(codes.contains("invalid-report-rate"))
  }

  func testMacroValidationRequiresBalancedKeyState() {
    var profile = makeValidProfile()
    profile.macros[0].events = [.keyDown(4), .keyDown(4)]

    let codes = profile.validationIssues().map(\.code)

    XCTAssertTrue(codes.contains("duplicate-key-down"))
    XCTAssertTrue(codes.contains("unreleased-keys"))
  }

  func testProfileEncoderRefusesInvalidProfile() {
    let profile = DeviceProfile(identifier: "", name: "")

    XCTAssertThrowsError(try ProfileJSONCodec.encode(profile)) { error in
      guard let validation = error as? ProfileValidationError else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertGreaterThanOrEqual(validation.issues.count, 2)
    }
  }

  func testDecoderValidatesByDefaultButCanImportForRepair() throws {
    let invalid = DeviceProfile(identifier: "", name: "")
    let rawData = try JSONEncoder().encode(invalid)

    XCTAssertThrowsError(try ProfileJSONCodec.decode(rawData))
    XCTAssertEqual(
      try ProfileJSONCodec.decode(rawData, validate: false),
      invalid
    )
  }

  func testResourceNameValidationRejectsAbsoluteAndURLReferences() {
    var profile = makeValidProfile()

    for resourceName in ["/tmp/picture.bin", "https://example.invalid/picture.bin", "~/.hidden"] {
      profile.tft.assets[0].resourceName = resourceName
      XCTAssertTrue(profile.validationIssues().contains { $0.code == "unsafe-resource-name" })
    }
  }

  func testKeyActionCodableShapeRoundTripsEveryCase() throws {
    let actions: [KeyAction] = [
      .keyCode(4),
      .consumerControl(1),
      .macro(identifier: "macro-1"),
      .disabled,
    ]

    let data = try JSONEncoder().encode(actions)

    XCTAssertEqual(try JSONDecoder().decode([KeyAction].self, from: data), actions)
  }

  private func makeValidProfile() -> DeviceProfile {
    DeviceProfile(
      identifier: "profile-1",
      name: "Work",
      keymap: KeymapProfile(assignments: [
        KeyAssignment(layer: 0, position: 0, action: .keyCode(4)),
        KeyAssignment(layer: 1, position: 0, action: .macro(identifier: "macro-1")),
      ]),
      lighting: LightingProfile(
        enabled: true,
        effectIdentifier: "static",
        brightnessPercent: 80,
        speedPercent: 50,
        baseColor: RGBColor(red: 10, green: 20, blue: 30),
        accentColor: RGBColor(red: 40, green: 50, blue: 60),
        perKey: [
          PerKeyLighting(
            position: 0,
            color: RGBColor(red: 255, green: 0, blue: 0),
            intensityPercent: 90
          )
        ]
      ),
      macros: [
        MacroDefinition(
          identifier: "macro-1",
          name: "Example",
          events: [.keyDown(4), .delay(milliseconds: 10), .keyUp(4)]
        )
      ],
      tft: TFTProfile(
        enabled: true,
        canvasWidth: 320,
        canvasHeight: 180,
        frameRate: 30,
        assets: [
          DisplayAssetReference(
            identifier: "asset-1",
            resourceName: "preview.bin",
            width: 320,
            height: 180,
            frameCount: 10
          )
        ],
        playlist: ["asset-1"],
        themeIdentifier: "orbit",
        message: "HELLO, MAC",
        accentColor: RGBColor(red: 12, green: 200, blue: 170),
        showsClock: true,
        showsBattery: false
      ),
      settings: DeviceSettings(
        sleepTimeoutSeconds: 300,
        debounceMilliseconds: 5,
        reportRateHz: 1_000,
        functionLayerEnabled: true
      )
    )
  }
}
