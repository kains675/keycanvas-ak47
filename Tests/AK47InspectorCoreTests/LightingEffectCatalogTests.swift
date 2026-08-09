import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class LightingEffectCatalogTests: XCTestCase {
  func testCatalogHasExactStableModeOrderAndIdentifiers() {
    let effects = AK47OnboardLightingEffect.allCases

    XCTAssertEqual(effects.map(\.rawValue), Array(1...19))
    XCTAssertEqual(
      effects.map(\.effectIdentifier),
      (1...19).map { "ak47-onboard-\($0)" }
    )
    XCTAssertEqual(
      effects.map(\.resourceName),
      [
        "Static", "SingleOn", "SingleOff", "Glittering", "Falling", "Colourful",
        "Breath", "Spectrum", "Outward", "Scrolling", "Rolling", "Rotating", "Explode",
        "Launch", "Ripples", "Flowing", "Pulsating", "Tilt", "Shuttle",
      ]
    )
    XCTAssertEqual(AK47OnboardLightingEffect.offResourceName, "LED Off")
  }

  func testVerifiedConfigurationCapabilitiesMatchEveryMode() {
    XCTAssertEqual(
      AK47OnboardLightingEffect.allCases.map(\.configurationCapabilities.rawValue),
      [
        0x31, 0x33, 0x33, 0x33, 0x33, 0x03, 0x33, 0x03, 0x33, 0x3B, 0x37, 0x37,
        0x33, 0x33, 0x33, 0x37, 0x33, 0x37, 0x33,
      ]
    )
  }

  func testLegacySceneIdentifiersUseKnownFallbacks() {
    XCTAssertEqual(AK47OnboardLightingEffect.resolve(identifier: "flow"), .flowing)
    XCTAssertEqual(AK47OnboardLightingEffect.resolve(identifier: "flow-preview"), .flowing)
    XCTAssertEqual(AK47OnboardLightingEffect.resolve(identifier: "breath"), .breath)
    XCTAssertEqual(AK47OnboardLightingEffect.resolve(identifier: "still"), .staticMode)
    XCTAssertEqual(AK47OnboardLightingEffect.resolve(identifier: "static"), .staticMode)
  }

  func testWindowsRawModesMigrateToStableCatalog() {
    for rawValue in 1...19 {
      let profile = LightingProfile(
        effectIdentifier: "windows-raw-mode-\(rawValue)"
      )
      let selection = AK47LightingProfileSelection.migrate(profile)

      XCTAssertTrue(selection.isEnabled)
      XCTAssertEqual(selection.effect.rawValue, rawValue)
      XCTAssertEqual(selection.effect.effectIdentifier, "ak47-onboard-\(rawValue)")
    }
  }

  func testModeZeroMigratesToSeparateDisabledState() {
    let selection = AK47LightingProfileSelection.migrate(
      LightingProfile(enabled: true, effectIdentifier: "windows-raw-mode-0")
    )

    XCTAssertFalse(selection.isEnabled)
    XCTAssertEqual(selection.effect, .staticMode)
    XCTAssertNotEqual(selection.effect.effectIdentifier, "ak47-onboard-0")
  }

  func testUnknownIdentifierFallsBackWithoutChangingEnabledState() {
    let selection = AK47LightingProfileSelection.migrate(
      LightingProfile(enabled: false, effectIdentifier: "future-local-effect")
    )

    XCTAssertFalse(selection.isEnabled)
    XCTAssertEqual(selection.effect, .staticMode)
  }
}
