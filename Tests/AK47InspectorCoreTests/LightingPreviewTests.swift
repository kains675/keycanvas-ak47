import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class LightingPreviewTests: XCTestCase {
  private let base = AK47LightingPreviewRGB(red: 0.1, green: 0.8, blue: 0.6)

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

  func testPhysicalOrdinalAndHardwareLightIndexRemainExplicitlyDistinct() {
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

  func testProjectAuthoredPresentationPacingIsPositiveAndMonotonicallyFaster() {
    for effect in AK47OnboardLightingEffect.allCases {
      let periods = (UInt8(1)...UInt8(5)).map {
        effect.presentationStepPeriod(speedLevel: $0)
      }
      XCTAssertTrue(periods.allSatisfy { $0 > 0 }, effect.resourceName)
      for pair in zip(periods, periods.dropFirst()) {
        XCTAssertGreaterThan(pair.0, pair.1, effect.resourceName)
      }
    }
  }

  func testEveryModeProducesExactly84IntegerPixelsAndIsDeterministic() {
    for effect in AK47OnboardLightingEffect.allCases {
      var first = makeEngine(effect: effect, colorful: true)
      var second = makeEngine(effect: effect, colorful: true)
      if effect.isReactive, let key = AK47LightingPreviewKeyIndex(rawValue: 40) {
        first.enqueue(event(.down, key: key, tick: 0, sequence: 0))
        second.enqueue(event(.down, key: key, tick: 0, sequence: 0))
      }
      first.advance(to: 2_000)
      second.advance(to: 2_000)

      XCTAssertEqual(first.frame(), second.frame(), effect.resourceName)
      XCTAssertEqual(first.frame().pixelsByPhysicalKey.count, 84)
    }
  }

  func testStaticModeIsAOneShotHold() {
    var engine = makeEngine(effect: .staticMode)
    let initial = engine.frame().pixelsByPhysicalKey

    engine.advance(to: 50_000)

    XCTAssertEqual(engine.frame().pixelsByPhysicalKey, initial)
    XCTAssertEqual(engine.completedStepCount, 0)
    XCTAssertEqual(engine.logicalTick, 50_000)
  }

  func testProjectAuthoredBrightnessCurveIsMonotonicAndColorNeutral() {
    let color = AK47LightingPreviewRGB(redByte: 255, greenByte: 128, blueByte: 64)
    var prior = AK47LightingPreviewPixel.off

    for brightness in 0...5 {
      let engine = AK47LightingPreviewEngine(
        configuration: configuration(
          effect: .staticMode,
          brightness: brightness,
          baseColor: color
        )
      )
      let pixel = engine.frame().pixelsByPhysicalKey[0]
      XCTAssertGreaterThanOrEqual(pixel.red, prior.red)
      XCTAssertGreaterThanOrEqual(pixel.green, prior.green)
      XCTAssertGreaterThanOrEqual(pixel.blue, prior.blue)
      prior = pixel
    }
    XCTAssertEqual(prior, AK47LightingPreviewPixel(red: 255, green: 128, blue: 64))
  }

  func testSingleOnAndSingleOffConsumeOrderedDownAndUpEvents() throws {
    let key = try XCTUnwrap(AK47LightingPreviewKeyIndex(rawValue: 10))
    var singleOn = makeEngine(effect: .singleOn)
    singleOn.enqueue(event(.down, key: key, tick: 5, sequence: 0))
    singleOn.enqueue(event(.up, key: key, tick: 5, sequence: 1))
    singleOn.advance(to: 5)
    let releasedOn = singleOn.frame()[key].normalizedIntensity

    var heldOn = makeEngine(effect: .singleOn)
    heldOn.enqueue(event(.up, key: key, tick: 5, sequence: 0))
    heldOn.enqueue(event(.down, key: key, tick: 5, sequence: 1))
    heldOn.advance(to: 5)

    XCTAssertGreaterThan(heldOn.frame()[key].normalizedIntensity, releasedOn)

    var singleOff = makeEngine(effect: .singleOff)
    let idleOff = singleOff.frame()[key].normalizedIntensity
    singleOff.enqueue(event(.down, key: key, tick: 0, sequence: 0))
    XCTAssertEqual(singleOff.frame()[key], .off)
    singleOff.enqueue(event(.up, key: key, tick: 0, sequence: 1))
    advanceOneStep(&singleOff)
    XCTAssertGreaterThan(singleOff.frame()[key].normalizedIntensity, 0)
    XCTAssertLessThan(singleOff.frame()[key].normalizedIntensity, idleOff)
  }

  func testExplodeLaunchAndRipplesReactToDownButNotUp() throws {
    let key = try XCTUnwrap(AK47LightingPreviewKeyIndex(rawValue: 45))
    for effect in [
      AK47OnboardLightingEffect.explode, .launch, .ripples,
    ] {
      var engine = makeEngine(effect: effect)
      engine.enqueue(event(.down, key: key, tick: 0, sequence: 0))
      let afterDown = engine.frame()
      engine.enqueue(event(.up, key: key, tick: 0, sequence: 1))

      XCTAssertEqual(engine.frame(), afterDown, effect.resourceName)
      XCTAssertGreaterThan(afterDown[key].normalizedIntensity, 0, effect.resourceName)
    }
  }

  func testDirectionAndColorChangesApplyFromNowWithoutResettingState() {
    var forward = makeEngine(effect: .flowing, direction: 0)
    advanceOneStep(&forward)
    let tick = forward.logicalTick
    let steps = forward.completedStepCount

    var recolored = forward
    recolored.reconfigure(
      configuration(
        effect: .flowing,
        direction: 0,
        baseColor: AK47LightingPreviewRGB(redByte: 240, greenByte: 20, blueByte: 30)
      )
    )
    XCTAssertEqual(recolored.logicalTick, tick)
    XCTAssertEqual(recolored.completedStepCount, steps)
    XCTAssertNotEqual(recolored.frame(), forward.frame())

    var colorful = forward
    colorful.reconfigure(configuration(effect: .flowing, direction: 0, colorful: true))
    XCTAssertEqual(colorful.logicalTick, tick)
    XCTAssertEqual(colorful.completedStepCount, steps)
    XCTAssertNotEqual(colorful.frame(), forward.frame())

    var reverse = forward
    reverse.reconfigure(configuration(effect: .flowing, direction: 1))
    XCTAssertEqual(reverse.frame(), forward.frame())
    XCTAssertEqual(reverse.logicalTick, tick)
    for _ in 0..<2 {
      advanceOneStep(&forward)
      advanceOneStep(&reverse)
    }
    XCTAssertNotEqual(reverse.frame(), forward.frame())
  }

  func testSpeedChangeSchedulesAWholeNewPeriodWithoutRetroactivePhaseJump() {
    var engine = makeEngine(effect: .rolling, speed: 1)
    engine.advance(to: 17)
    let before = engine.frame()
    let stepCount = engine.completedStepCount
    let faster = configuration(effect: .rolling, speed: 5)
    engine.reconfigure(faster)

    XCTAssertEqual(engine.frame(), before)
    XCTAssertEqual(engine.completedStepCount, stepCount)
    engine.advance(
      to: engine.logicalTick + faster.effect.presentationStepPeriod(speedLevel: 5) - 1
    )
    XCTAssertEqual(engine.completedStepCount, stepCount)
    engine.advance(to: engine.logicalTick + 1)
    XCTAssertEqual(engine.completedStepCount, stepCount + 1)
  }

  func testDirectionRulesCoverPaletteAndFreshFlowingTiltSelections() {
    for effect in [
      AK47OnboardLightingEffect.scrolling, .rolling, .rotating, .flowing, .tilt,
    ] {
      for colorful in [false, true] {
        var forward = makeEngine(effect: effect, direction: 0, colorful: colorful)
        var reverse = makeEngine(effect: effect, direction: 1, colorful: colorful)
        for _ in 0..<2 {
          advanceOneStep(&forward)
          advanceOneStep(&reverse)
        }
        XCTAssertNotEqual(
          forward.frame(),
          reverse.frame(),
          "\(effect.resourceName), colorful=\(colorful)"
        )
      }
    }

    for effect in AK47OnboardLightingEffect.allCases
    where effect.configurationCapabilities.intersection([
      .horizontalDirection, .verticalDirection,
    ]).isEmpty {
      XCTAssertEqual(configuration(effect: effect, direction: 1).direction, 0, effect.resourceName)
    }
  }

  func testScrollingBroadcastsRowPhasesAndMovesDownOrUp() {
    var down = makeEngine(effect: .scrolling, direction: 0)
    var up = makeEngine(effect: .scrolling, direction: 1)
    let rowGroups = Dictionary(grouping: AK47PhysicalLayout.keys.indices) {
      AK47PhysicalLayout.keys[$0].y
    }.sorted { $0.key < $1.key }.map(\.value)

    let initial = down.frame()
    let initialLevels = rowGroups.map { group -> UInt8 in
      let pixels = group.map { initial.pixelsByPhysicalKey[$0] }
      XCTAssertEqual(Set(pixels).count, 1)
      return pixels[0].green
    }
    for pair in zip(initialLevels, initialLevels.dropFirst()) {
      XCTAssertGreaterThan(pair.0, pair.1)
    }

    for _ in 0..<2 {
      advanceOneStep(&down)
      advanceOneStep(&up)
    }
    XCTAssertGreaterThan(
      brightestGroup(in: down.frame(), groups: rowGroups),
      brightestGroup(in: up.frame(), groups: rowGroups))
  }

  func testRollingBroadcastsColumnPhasesAndMovesRightOrLeft() {
    var right = makeEngine(effect: .rolling, direction: 0)
    var left = makeEngine(effect: .rolling, direction: 1)
    let columnGroups = Dictionary(grouping: AK47PhysicalLayout.keys.indices) { index in
      min(
        16,
        max(
          0,
          Int(
            Double(AK47PhysicalLayout.keys[index].center.x)
              / Double(AK47PhysicalLayout.canvasSize.width) * 17
          )
        )
      )
    }.sorted { $0.key < $1.key }.map(\.value)

    let initial = right.frame()
    let initialLevels = columnGroups.map { group -> UInt8 in
      let pixels = group.map { initial.pixelsByPhysicalKey[$0] }
      XCTAssertEqual(Set(pixels).count, 1)
      return pixels[0].green
    }
    for pair in zip(initialLevels, initialLevels.dropFirst()) {
      XCTAssertGreaterThan(pair.0, pair.1)
    }

    for _ in 0..<2 {
      advanceOneStep(&right)
      advanceOneStep(&left)
    }
    XCTAssertGreaterThan(
      brightestGroup(in: right.frame(), groups: columnGroups),
      brightestGroup(in: left.frame(), groups: columnGroups))
  }

  func testRotatingColorfulKeepsEveryKeyLitWhileAngularColorsRotate() {
    var engine = makeEngine(effect: .rotating, colorful: true)
    let initial = engine.frame()
    let centerX = Double(AK47PhysicalLayout.canvasSize.width) / 2
    let centerY = Double(AK47PhysicalLayout.canvasSize.height) / 2
    let angularGroups = Dictionary(grouping: AK47PhysicalLayout.keys.indices) { index in
      let key = AK47PhysicalLayout.keys[index]
      let angle = atan2(Double(key.center.y) - centerY, Double(key.center.x) - centerX)
      return Int(((angle + .pi) / (.pi * 2) * 16).rounded(.down)) % 16
    }

    XCTAssertTrue(
      initial.pixelsByPhysicalKey.allSatisfy { $0.normalizedIntensity > 0.99 }
    )
    XCTAssertGreaterThan(Set(initial.pixelsByPhysicalKey).count, 8)
    for indices in angularGroups.values {
      XCTAssertEqual(
        Set(indices.map { initial.pixelsByPhysicalKey[$0] }).count,
        1
      )
    }

    advanceOneStep(&engine)
    let rotated = engine.frame()
    XCTAssertTrue(
      rotated.pixelsByPhysicalKey.allSatisfy { $0.normalizedIntensity > 0.99 }
    )
    XCTAssertNotEqual(rotated.pixelsByPhysicalKey, initial.pixelsByPhysicalKey)
  }

  func testColourfulAndSpectrumIgnoreColorfulFlag() {
    for effect in [AK47OnboardLightingEffect.colourful, .spectrum] {
      var single = makeEngine(effect: effect, colorful: false)
      var colorful = makeEngine(effect: effect, colorful: true)
      single.advance(to: 2_000)
      colorful.advance(to: 2_000)
      XCTAssertEqual(single.frame(), colorful.frame(), effect.resourceName)
    }
  }

  func testPulsatingExpandsAndContractsWithoutAnAllDimPhase() {
    var engine = makeEngine(effect: .pulsating)
    for _ in 0..<24 {
      advanceOneStep(&engine)
      XCTAssertGreaterThan(
        engine.frame().pixelsByPhysicalKey.map(\.normalizedIntensity).max() ?? 0,
        0.5
      )
    }
  }

  func testOutwardKeepsAVisibleBandAcrossEveryPresentationPhase() {
    var engine = makeEngine(effect: .outward)
    for _ in 0..<17 {
      XCTAssertGreaterThan(
        engine.frame().pixelsByPhysicalKey.map(\.normalizedIntensity).max() ?? 0,
        0.5
      )
      advanceOneStep(&engine)
    }
  }

  func testFlowingRendersBothEndpointsBeforeClearingAtWrap() {
    var forward = makeEngine(effect: .flowing, direction: 0)
    advanceOneStep(&forward)
    XCTAssertGreaterThan(forward.frame().pixelsByPhysicalKey[0].normalizedIntensity, 0.5)
    for _ in 1..<AK47LightingPreviewFrame.keyCount { advanceOneStep(&forward) }
    XCTAssertGreaterThan(
      forward.frame().pixelsByPhysicalKey[AK47LightingPreviewFrame.keyCount - 1]
        .normalizedIntensity,
      0.5
    )
    advanceOneStep(&forward)
    XCTAssertGreaterThan(forward.frame().pixelsByPhysicalKey[0].normalizedIntensity, 0.5)
    XCTAssertLessThan(
      forward.frame().pixelsByPhysicalKey[AK47LightingPreviewFrame.keyCount - 1]
        .normalizedIntensity,
      0.5
    )

    var reverse = makeEngine(effect: .flowing, direction: 1)
    advanceOneStep(&reverse)
    XCTAssertGreaterThan(
      reverse.frame().pixelsByPhysicalKey[AK47LightingPreviewFrame.keyCount - 1]
        .normalizedIntensity,
      0.5
    )
    for _ in 1..<AK47LightingPreviewFrame.keyCount { advanceOneStep(&reverse) }
    XCTAssertGreaterThan(reverse.frame().pixelsByPhysicalKey[0].normalizedIntensity, 0.5)
    advanceOneStep(&reverse)
    XCTAssertGreaterThan(
      reverse.frame().pixelsByPhysicalKey[AK47LightingPreviewFrame.keyCount - 1]
        .normalizedIntensity,
      0.5
    )
    XCTAssertLessThan(reverse.frame().pixelsByPhysicalKey[0].normalizedIntensity, 0.5)
  }

  func testShuttleWrapRetainsTheNewEndpointInsteadOfClearingIt() {
    var engine = makeEngine(effect: .shuttle)
    for _ in 0..<17 { advanceOneStep(&engine) }

    XCTAssertGreaterThan(
      engine.frame().pixelsByPhysicalKey.map(\.normalizedIntensity).max() ?? 0,
      0.5
    )
  }

  func testSchedulerAdvancesEveryDueLogicalStepAtThirtyHertz() {
    let config = configuration(effect: .rolling, speed: 5)
    var scheduler = AK47LightingPreviewScheduler(configuration: config)

    for _ in 0..<30 {
      scheduler.advance(
        elapsedNanoseconds: AK47LightingPreviewScheduler.presentationIntervalNanoseconds
      )
    }

    XCTAssertEqual(scheduler.logicalTick, 999)
    XCTAssertEqual(
      scheduler.engine.completedStepCount,
      999 / config.effect.presentationStepPeriod(speedLevel: config.speedLevel)
    )
  }

  func testSchedulerRebasesLargeJumpWithoutOverflowOrCatchUpLoop() {
    var scheduler = AK47LightingPreviewScheduler(configuration: configuration(effect: .rolling))
    scheduler.advance(elapsedNanoseconds: UInt64.max)

    XCTAssertEqual(scheduler.logicalTick, 0)
    XCTAssertEqual(scheduler.engine.completedStepCount, 0)

    scheduler.advance(elapsedNanoseconds: 1_000_000_000)
    XCTAssertEqual(scheduler.logicalTick, 1_000)
  }

  func testSchedulerPauseAndResumeExcludePausedElapsedTime() {
    var scheduler = AK47LightingPreviewScheduler(configuration: configuration(effect: .flowing))
    scheduler.advance(monotonicNanoseconds: 100)
    scheduler.advance(monotonicNanoseconds: 1_000_000_100)
    XCTAssertEqual(scheduler.logicalTick, 1_000)

    scheduler.setPaused(true)
    scheduler.advance(monotonicNanoseconds: 40_000_000_000)
    scheduler.setPaused(false)
    scheduler.advance(monotonicNanoseconds: 50_000_000_000)
    XCTAssertEqual(scheduler.logicalTick, 1_000)

    scheduler.advance(monotonicNanoseconds: 50_500_000_000)
    XCTAssertEqual(scheduler.logicalTick, 1_500)
  }

  @MainActor
  func testPreviewSessionStopsItsThirtyHertzTaskWhilePausedOrDisabled() {
    let session = AK47LightingPreviewSession()
    session.configure(
      configuration(effect: .flowing),
      includesDeterministicDemoInput: false
    )
    session.setPaused(false)
    XCTAssertTrue(session.isAnimationRunning)

    session.setPaused(true)
    XCTAssertFalse(session.isAnimationRunning)

    session.setPaused(false)
    XCTAssertTrue(session.isAnimationRunning)

    session.configure(
      AK47LightingPreviewConfiguration(
        effect: .flowing,
        isEnabled: false,
        speedLevel: 3,
        brightnessLevel: 5,
        baseColor: base
      ),
      includesDeterministicDemoInput: false
    )
    XCTAssertFalse(session.isAnimationRunning)
  }

  private func makeEngine(
    effect: AK47OnboardLightingEffect,
    speed: Int = 3,
    brightness: Int = 5,
    direction: Int = 0,
    colorful: Bool = false
  ) -> AK47LightingPreviewEngine {
    AK47LightingPreviewEngine(
      configuration: configuration(
        effect: effect,
        speed: speed,
        brightness: brightness,
        direction: direction,
        colorful: colorful
      )
    )
  }

  private func configuration(
    effect: AK47OnboardLightingEffect,
    speed: Int = 3,
    brightness: Int = 5,
    direction: Int = 0,
    colorful: Bool = false,
    baseColor: AK47LightingPreviewRGB? = nil
  ) -> AK47LightingPreviewConfiguration {
    AK47LightingPreviewConfiguration(
      effect: effect,
      speedLevel: speed,
      brightnessLevel: brightness,
      direction: direction,
      colorful: colorful,
      baseColor: baseColor ?? base
    )
  }

  private func event(
    _ kind: AK47LightingPreviewKeyEventKind,
    key: AK47LightingPreviewKeyIndex,
    tick: UInt64,
    sequence: UInt64
  ) -> AK47LightingPreviewKeyEvent {
    AK47LightingPreviewKeyEvent(
      logicalTick: tick,
      sequence: sequence,
      key: key,
      kind: kind
    )
  }

  private func advanceOneStep(_ engine: inout AK47LightingPreviewEngine) {
    engine.advance(
      to: engine.logicalTick
        + engine.configuration.effect.presentationStepPeriod(
          speedLevel: engine.configuration.speedLevel
        )
    )
  }

  private func brightestGroup(
    in frame: AK47LightingPreviewFrame,
    groups: [[Int]]
  ) -> Int {
    groups.indices.max { first, second in
      let firstLevel = groups[first].map { frame.pixelsByPhysicalKey[$0].green }.max() ?? 0
      let secondLevel = groups[second].map { frame.pixelsByPhysicalKey[$0].green }.max() ?? 0
      return firstLevel < secondLevel
    } ?? 0
  }
}
