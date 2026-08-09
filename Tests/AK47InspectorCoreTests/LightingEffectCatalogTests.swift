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

  func testHydratingLightingEditorPreservesExactUnrepresentableProfileValues() {
    let fallbackAccent = AK47InspectorCore.RGBColor(red: 153, green: 107, blue: 245)
    let baseline = LightingProfile(
      enabled: true,
      effectIdentifier: "windows-raw-mode-16",
      brightnessPercent: 72,
      speedPercent: 38,
      direction: 7,
      colorful: true,
      baseColor: AK47InspectorCore.RGBColor(red: 17, green: 93, blue: 201),
      accentColor: nil,
      perKey: [
        PerKeyLighting(
          position: 1,
          color: AK47InspectorCore.RGBColor(red: 9, green: 8, blue: 7),
          intensityPercent: 61
        )
      ]
    )
    let projected = AK47LightingDraftValues.projecting(
      baseline,
      fallbackAccentColor: fallbackAccent
    )
    var editingState = AK47LightingProfileEditingState(baseline: baseline)

    for field: AK47LightingProfileField in [
      .enabled, .effect, .brightness, .speed, .direction, .colorful, .baseColor,
      .accentColor, .perKey,
    ] {
      XCTAssertFalse(
        editingState.observe(
          field,
          values: projected,
          fallbackAccentColor: fallbackAccent
        ),
        "Hydration must not count as an edit to \(field)"
      )
    }

    XCTAssertTrue(editingState.editedFields.isEmpty)
    XCTAssertEqual(editingState.composing(values: projected), baseline)
  }

  func testEditingBrightnessChangesOnlyBrightnessAndPreservesNilAccent() {
    let fallbackAccent = AK47InspectorCore.RGBColor(red: 153, green: 107, blue: 245)
    let baseline = LightingProfile(
      enabled: true,
      effectIdentifier: "windows-raw-mode-16",
      brightnessPercent: 72,
      speedPercent: 38,
      direction: 1,
      colorful: true,
      baseColor: AK47InspectorCore.RGBColor(red: 17, green: 93, blue: 201),
      accentColor: nil,
      perKey: [
        PerKeyLighting(
          position: 19,
          color: AK47InspectorCore.RGBColor(red: 3, green: 4, blue: 5),
          intensityPercent: 67
        )
      ]
    )
    var values = AK47LightingDraftValues.projecting(
      baseline,
      fallbackAccentColor: fallbackAccent
    )
    values.brightnessLevel = 5
    var editingState = AK47LightingProfileEditingState(baseline: baseline)

    XCTAssertTrue(
      editingState.observe(
        .brightness,
        values: values,
        fallbackAccentColor: fallbackAccent
      )
    )

    let composed = editingState.composing(values: values)
    var expected = baseline
    expected.brightnessPercent = 100
    XCTAssertEqual(composed, expected)
  }

  func testPerKeyApplyValuesTreatMissingSlotsAsBlack() {
    let paintedColor = AK47InspectorCore.RGBColor(red: 12, green: 34, blue: 56)
    let paintedLightIndex = AK47PhysicalLayout.keys[3].lightIndex
    let draft = AK47PerKeyLightingDraft(
      entries: [
        PerKeyLighting(position: paintedLightIndex, color: paintedColor),
        PerKeyLighting(
          position: 999,
          color: AK47InspectorCore.RGBColor(red: 200, green: 201, blue: 202)
        ),
      ]
    )

    let values = AK47PerKeyLightingApplyValues.composing(from: draft)

    XCTAssertEqual(values.count, AK47PhysicalLayout.keys.count)
    XCTAssertEqual(values.map(\.lightIndex), AK47PhysicalLayout.keys.map(\.lightIndex))
    XCTAssertFalse(values.contains { $0.lightIndex == 999 })
    XCTAssertEqual(values.first { $0.lightIndex == paintedLightIndex }?.color, paintedColor)
    XCTAssertTrue(
      values
        .filter { $0.lightIndex != paintedLightIndex }
        .allSatisfy { $0.color == AK47InspectorCore.RGBColor(red: 0, green: 0, blue: 0) }
    )
  }

  func testInitialPerKeyBrushNeverUsesMaterializedOffColor() {
    let off = AK47InspectorCore.RGBColor(red: 0, green: 0, blue: 0)
    let base = AK47InspectorCore.RGBColor(red: 10, green: 20, blue: 30)
    let fallback = AK47InspectorCore.RGBColor(red: 40, green: 50, blue: 60)
    let painted = AK47InspectorCore.RGBColor(red: 70, green: 80, blue: 90)

    XCTAssertEqual(
      AK47PerKeyLightingApplyValues.initialBrushColor(
        selectedColor: painted,
        baseColor: base,
        fallbackColor: fallback
      ),
      painted
    )
    XCTAssertEqual(
      AK47PerKeyLightingApplyValues.initialBrushColor(
        selectedColor: off,
        baseColor: base,
        fallbackColor: fallback
      ),
      base
    )
    XCTAssertEqual(
      AK47PerKeyLightingApplyValues.initialBrushColor(
        selectedColor: off,
        baseColor: off,
        fallbackColor: fallback
      ),
      fallback
    )

    let paintedLightIndex = AK47PhysicalLayout.keys[5].lightIndex
    XCTAssertEqual(
      AK47PerKeyLightingApplyValues.initialSelectedLightIndex(
        from: AK47PerKeyLightingDraft(
          entries: [PerKeyLighting(position: paintedLightIndex, color: painted)]
        )
      ),
      paintedLightIndex
    )
    XCTAssertEqual(
      AK47PerKeyLightingApplyValues.initialSelectedLightIndex(
        from: AK47PerKeyLightingDraft()
      ),
      AK47PhysicalLayout.keys.first?.lightIndex
    )
  }

  func testExplicitModeSelectionCanReplaceMigratedIdentifier() {
    let fallbackAccent = AK47InspectorCore.RGBColor(red: 153, green: 107, blue: 245)
    let baseline = LightingProfile(
      enabled: true,
      effectIdentifier: "windows-raw-mode-0",
      brightnessPercent: 72,
      speedPercent: 38,
      accentColor: nil
    )
    var values = AK47LightingDraftValues.projecting(
      baseline,
      fallbackAccentColor: fallbackAccent
    )
    values.isEnabled = true
    values.effect = AK47OnboardLightingEffect.staticMode
    var editingState = AK47LightingProfileEditingState(baseline: baseline)
    editingState.markEdited([.enabled, .effect])

    let composed = editingState.composing(values: values)
    XCTAssertTrue(composed.enabled)
    XCTAssertEqual(composed.effectIdentifier, "ak47-onboard-1")
    XCTAssertEqual(composed.brightnessPercent, 72)
    XCTAssertEqual(composed.speedPercent, 38)
    XCTAssertNil(composed.accentColor)
  }
}
