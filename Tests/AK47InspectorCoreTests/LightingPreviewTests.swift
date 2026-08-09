import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class LightingPreviewTests: XCTestCase {
  private let base = AK47LightingPreviewRGB(red: 0.1, green: 0.8, blue: 0.6)
  private let accent = AK47LightingPreviewRGB(red: 0.7, green: 0.25, blue: 1)

  func testPhysicalLayoutHasExactUnique84KeyTopology() {
    let keys = AK47PhysicalLayout.keys

    XCTAssertEqual(keys.count, 84)
    XCTAssertEqual(Set(keys.map(\.id)).count, 84)
    XCTAssertEqual(Set(keys.map(\.lightIndex)), Set(AK47PerKeyRGBQueryProtocol.lightIndices))
    for key in keys {
      XCTAssertGreaterThan(key.width, 0)
      XCTAssertGreaterThan(key.height, 0)
      XCTAssertGreaterThanOrEqual(key.x, 0)
      XCTAssertGreaterThanOrEqual(key.y, 0)
      XCTAssertLessThanOrEqual(key.x + key.width, AK47PhysicalLayout.canvasSize.width)
      XCTAssertLessThanOrEqual(key.y + key.height, AK47PhysicalLayout.canvasSize.height)
    }
  }

  func testPhysicalOrdinalAndFirmwareLightIndexRemainExplicitlyDistinct() {
    let expected: [String: Int] = [
      "Esc": 1, "F12": 13,
      "Grave": 19, "Equal": 31,
      "Backspace": 103,
      "Insert": 116, "Home": 117, "Page Up": 118,
      "Tab": 37, "Right Bracket": 49,
      "Backslash": 67,
      "Delete": 119, "End": 120, "Page Down": 121,
      "Caps Lock": 55, "Quote": 66,
      "Return": 85,
      "Left Shift": 73, "Right Shift": 84,
      "Up": 101,
      "Left Control": 91, "Right Control": 98,
      "Left": 99, "Down": 100, "Right": 102,
    ]

    for (keyID, lightIndex) in expected {
      XCTAssertEqual(
        AK47PhysicalLayout.keys.first(where: { $0.id == keyID })?.lightIndex,
        lightIndex,
        keyID
      )
    }
  }

  func testLocalProfilePositionsRemainCompatibleWithOriginalDraftSchema() {
    XCTAssertEqual(AK47PhysicalLayout.profileKeyIDs.count, 84)
    XCTAssertEqual(Set(AK47PhysicalLayout.profileKeyIDs), Set(AK47PhysicalLayout.keyIDs))
    XCTAssertEqual(AK47PhysicalLayout.profilePosition(for: "Menu"), 13)
    XCTAssertEqual(AK47PhysicalLayout.profilePosition(for: "Delete"), 14)
    XCTAssertEqual(AK47PhysicalLayout.profilePosition(for: "Home"), 15)
    XCTAssertEqual(AK47PhysicalLayout.profilePosition(for: "Grave"), 16)
    XCTAssertEqual(AK47PhysicalLayout.profilePosition(for: "Insert"), 59)
    XCTAssertEqual(AK47PhysicalLayout.profilePosition(for: "Right"), 83)
  }

  func testEveryEffectProducesOneFiniteBoundedSamplePerKey() {
    for effect in AK47OnboardLightingEffect.allCases {
      let frame = makeFrame(effect: effect, time: 0.73)

      XCTAssertEqual(frame.count, 84, effect.resourceName)
      for sample in frame.values {
        XCTAssertTrue(sample.color.red.isFinite)
        XCTAssertTrue(sample.color.green.isFinite)
        XCTAssertTrue(sample.color.blue.isFinite)
        XCTAssertTrue(sample.intensity.isFinite)
        XCTAssertTrue((0...1).contains(sample.color.red))
        XCTAssertTrue((0...1).contains(sample.color.green))
        XCTAssertTrue((0...1).contains(sample.color.blue))
        XCTAssertTrue((0...1).contains(sample.intensity))
      }
    }
  }

  func testStaticModeIsTimeInvariantAndMovingModesChangeFrames() {
    XCTAssertEqual(
      makeFrame(effect: .staticMode, time: 0),
      makeFrame(effect: .staticMode, time: 1.237)
    )

    for effect in AK47OnboardLightingEffect.allCases
    where effect != .staticMode && !effect.isReactive {
      XCTAssertNotEqual(
        makeFrame(effect: effect, time: 0),
        makeFrame(effect: effect, time: 1.237),
        effect.resourceName
      )
    }
  }

  func testReactiveEffectsHaveVerifiedIdlePolarityWithoutSimulatedInput() {
    for effect in [
      AK47OnboardLightingEffect.singleOn, .explode, .launch, .ripples,
    ] {
      XCTAssertTrue(makeFrame(effect: effect, time: 0).values.allSatisfy { $0.intensity == 0 })
    }
    XCTAssertTrue(
      makeFrame(effect: .singleOff, time: 0).values.allSatisfy { $0.intensity == 0.8 }
    )
  }

  func testMode14LaunchRespondsToManualAndSimulatedKeyPresses() throws {
    let space = try XCTUnwrap(AK47PhysicalLayout.keys.first(where: { $0.id == "Space" }))
    let press = AK47LightingPreviewEngine.press(for: space, at: 0)
    let manualFrame = makeFrame(effect: .launch, time: 0.35, presses: [press])
    let simulatedFrame = AK47LightingPreviewEngine.frame(
      effect: .launch,
      time: 0.35,
      speedLevel: 3,
      brightnessLevel: 4,
      baseColor: base,
      accentColor: accent,
      includesSimulatedInput: true
    )

    XCTAssertGreaterThan(manualFrame.values.map(\.intensity).max() ?? 0, 0.1)
    XCTAssertGreaterThan(simulatedFrame.values.map(\.intensity).max() ?? 0, 0.1)
  }

  func testZeroBrightnessTurnsEveryPreviewLEDOff() {
    let frame = AK47LightingPreviewEngine.frame(
      effect: .colourful,
      time: 0.45,
      speedLevel: 3,
      brightnessLevel: 0,
      baseColor: base,
      accentColor: accent
    )

    XCTAssertTrue(frame.values.allSatisfy { $0.intensity == 0 })
  }

  func testDirectionReversesOnlyEffectsWithVerifiedDirectionControl() {
    let forward = AK47LightingPreviewEngine.frame(
      effect: .flowing,
      time: 0.63,
      speedLevel: 3,
      brightnessLevel: 4,
      direction: 0,
      baseColor: base,
      accentColor: accent
    )
    let reverse = AK47LightingPreviewEngine.frame(
      effect: .flowing,
      time: 0.63,
      speedLevel: 3,
      brightnessLevel: 4,
      direction: 1,
      baseColor: base,
      accentColor: accent
    )
    XCTAssertNotEqual(forward, reverse)

    let breathA = AK47LightingPreviewEngine.frame(
      effect: .breath,
      time: 0.63,
      speedLevel: 3,
      brightnessLevel: 4,
      direction: 0,
      baseColor: base,
      accentColor: accent
    )
    let breathB = AK47LightingPreviewEngine.frame(
      effect: .breath,
      time: 0.63,
      speedLevel: 3,
      brightnessLevel: 4,
      direction: 1,
      baseColor: base,
      accentColor: accent
    )
    XCTAssertEqual(breathA, breathB)
  }

  private func makeFrame(
    effect: AK47OnboardLightingEffect,
    time: TimeInterval,
    presses: [AK47LightingPreviewPress] = []
  ) -> [String: AK47LightingPreviewSample] {
    AK47LightingPreviewEngine.frame(
      effect: effect,
      time: time,
      speedLevel: 3,
      brightnessLevel: 4,
      baseColor: base,
      accentColor: accent,
      manualPresses: presses,
      includesSimulatedInput: false
    )
  }
}
