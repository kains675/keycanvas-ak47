import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class AK47PerKeyLightingDraftTests: XCTestCase {
  private let mint = AK47InspectorCore.RGBColor(red: 12, green: 210, blue: 160)
  private let violet = AK47InspectorCore.RGBColor(red: 135, green: 90, blue: 240)

  func testEmptyDraftImmediatelyRepresentsAllPhysicalKeysAsOff() {
    let draft = AK47PerKeyLightingDraft()

    XCTAssertEqual(draft.configuredKeyCount, 84)
    XCTAssertEqual(draft.missingKeyCount, 0)
    XCTAssertEqual(draft.entries.count, 84)
    XCTAssertEqual(draft.litKeyCount, 0)
    XCTAssertEqual(draft.offKeyCount, 84)
    XCTAssertTrue(draft.isApplyReady)
    XCTAssertFalse(draft.hasLitKeys)
    XCTAssertEqual(
      Set(draft.entries.map(\.position)),
      Set(AK47PhysicalLayout.keys.map(\.lightIndex))
    )
    XCTAssertTrue(
      draft.entries.allSatisfy { entry in
        entry.color == AK47PerKeyLightingDraft.offColor && entry.intensityPercent == 100
      })
  }

  func testFillUsesAllExactFirmwareLightIndices() {
    var draft = AK47PerKeyLightingDraft()

    draft.fill(mint)

    XCTAssertEqual(draft.entries.count, 84)
    XCTAssertEqual(draft.litKeyCount, 84)
    XCTAssertEqual(draft.offKeyCount, 0)
    XCTAssertEqual(
      Set(draft.entries.map(\.position)),
      Set(AK47PhysicalLayout.keys.map(\.lightIndex))
    )
    XCTAssertTrue(draft.entries.allSatisfy { $0.color == mint && $0.intensityPercent == 100 })
  }

  func testToggleMovesFromOffToBrushAndBackToOff() throws {
    let key = try XCTUnwrap(AK47PhysicalLayout.keys.first { $0.id == "Space" })
    var draft = AK47PerKeyLightingDraft()

    XCTAssertTrue(draft.toggle(brushColor: mint, at: key.lightIndex))
    XCTAssertEqual(draft.color(at: key.lightIndex), mint)
    XCTAssertEqual(draft.litKeyCount, 1)

    XCTAssertTrue(draft.toggle(brushColor: mint, at: key.lightIndex))
    XCTAssertEqual(draft.color(at: key.lightIndex), AK47PerKeyLightingDraft.offColor)
    XCTAssertEqual(draft.litKeyCount, 0)
    XCTAssertEqual(draft.entries.count, 84)
  }

  func testToggleReplacesAnotherColorBeforeTurningBrushColorOff() throws {
    let key = try XCTUnwrap(AK47PhysicalLayout.keys.first)
    var draft = AK47PerKeyLightingDraft()
    draft.setColor(violet, at: key.lightIndex)

    XCTAssertTrue(draft.toggle(brushColor: mint, at: key.lightIndex))
    XCTAssertEqual(draft.color(at: key.lightIndex), mint)

    XCTAssertTrue(draft.toggle(brushColor: mint, at: key.lightIndex))
    XCTAssertEqual(draft.color(at: key.lightIndex), AK47PerKeyLightingDraft.offColor)
  }

  func testBlackBrushExplicitlyMeansOff() throws {
    let key = try XCTUnwrap(AK47PhysicalLayout.keys.first)
    var draft = AK47PerKeyLightingDraft()
    draft.setColor(mint, at: key.lightIndex)

    XCTAssertEqual(
      draft.toggleTargetColor(
        brushColor: AK47PerKeyLightingDraft.offColor,
        at: key.lightIndex
      ),
      AK47PerKeyLightingDraft.offColor
    )
    XCTAssertTrue(
      draft.toggle(brushColor: AK47PerKeyLightingDraft.offColor, at: key.lightIndex)
    )
    XCTAssertEqual(draft.color(at: key.lightIndex), AK47PerKeyLightingDraft.offColor)
    XCTAssertFalse(
      draft.toggle(brushColor: AK47PerKeyLightingDraft.offColor, at: key.lightIndex)
    )
  }

  func testSettingOffDoesNotSilentlyNormalizeAnExplicitBlackEntry() throws {
    let key = try XCTUnwrap(AK47PhysicalLayout.keys.first)
    let explicitBlack = PerKeyLighting(
      position: key.lightIndex,
      color: AK47PerKeyLightingDraft.offColor,
      intensityPercent: 45
    )
    var draft = AK47PerKeyLightingDraft(entries: [explicitBlack])
    let before = draft

    XCTAssertFalse(draft.setColor(AK47PerKeyLightingDraft.offColor, at: key.lightIndex))
    XCTAssertEqual(draft, before)
    XCTAssertEqual(draft.entry(at: key.lightIndex), explicitBlack)
  }

  func testUnsupportedPositionIsPreservedButCannotBeEdited() {
    let legacy = PerKeyLighting(
      position: 0,
      color: AK47InspectorCore.RGBColor(red: 1, green: 2, blue: 3),
      intensityPercent: 40
    )
    var draft = AK47PerKeyLightingDraft(entries: [legacy])

    XCTAssertFalse(draft.setColor(mint, at: 999))
    XCTAssertFalse(draft.toggle(brushColor: mint, at: 999))
    draft.clear(lightIndex: legacy.position)

    XCTAssertEqual(draft.unsupportedEntryCount, 1)
    XCTAssertEqual(draft.entry(at: legacy.position), legacy)
    XCTAssertEqual(draft.entries.filter { $0.position == legacy.position }, [legacy])
    XCTAssertEqual(draft.entries.count, 85)
  }

  func testClearAllTurnsPhysicalKeysOffAndPreservesUnsupportedLoadedEntries() {
    let legacy = PerKeyLighting(
      position: 0,
      color: AK47InspectorCore.RGBColor(red: 1, green: 2, blue: 3)
    )
    var draft = AK47PerKeyLightingDraft(entries: [legacy])
    draft.fill(mint)

    draft.clearAll()

    XCTAssertEqual(draft.litKeyCount, 0)
    XCTAssertEqual(draft.offKeyCount, 84)
    XCTAssertTrue(draft.isApplyReady)
    XCTAssertEqual(draft.unsupportedEntryCount, 1)
    XCTAssertEqual(draft.entry(at: legacy.position), legacy)
    XCTAssertEqual(draft.entries.count, 85)
  }

  func testStrokeLocksFirstKeysTargetAndSkipsReenteredKeys() throws {
    let firstKey = try XCTUnwrap(AK47PhysicalLayout.keys.first)
    let secondKey = try XCTUnwrap(AK47PhysicalLayout.keys.dropFirst().first)
    var draft = AK47PerKeyLightingDraft()
    draft.setColor(mint, at: firstKey.lightIndex)
    var stroke = AK47PerKeyLightingStroke()

    let firstTarget = stroke.nextTargetColor(
      at: firstKey.lightIndex,
      draft: draft,
      brushColor: mint
    )
    XCTAssertEqual(firstTarget, AK47PerKeyLightingDraft.offColor)
    XCTAssertEqual(
      stroke.nextTargetColor(at: secondKey.lightIndex, draft: draft, brushColor: mint),
      AK47PerKeyLightingDraft.offColor
    )
    XCTAssertNil(
      stroke.nextTargetColor(at: firstKey.lightIndex, draft: draft, brushColor: mint)
    )

    stroke.reset()
    XCTAssertEqual(
      stroke.nextTargetColor(at: secondKey.lightIndex, draft: draft, brushColor: mint),
      mint
    )
  }

  func testHitTestingUsesEveryExactPhysicalKeyFrameAtNativeSize() {
    let size = AK47PhysicalLayout.canvasSize

    for key in AK47PhysicalLayout.keys {
      XCTAssertEqual(
        AK47PerKeyLightingHitTesting.key(at: key.center, in: size)?.lightIndex,
        key.lightIndex,
        "Failed to hit \(key.id)"
      )
    }
  }

  func testHitTestingAccountsForResponsiveScaleAndLetterboxing() {
    let availableSize = CGSize(width: 1_344, height: 600)
    let scale = min(
      availableSize.width / AK47PhysicalLayout.canvasSize.width,
      availableSize.height / AK47PhysicalLayout.canvasSize.height
    )
    let offset = CGPoint(
      x: (availableSize.width - AK47PhysicalLayout.canvasSize.width * scale) / 2,
      y: (availableSize.height - AK47PhysicalLayout.canvasSize.height * scale) / 2
    )

    for key in AK47PhysicalLayout.keys {
      let renderedCenter = CGPoint(
        x: offset.x + key.center.x * scale,
        y: offset.y + key.center.y * scale
      )
      XCTAssertEqual(
        AK47PerKeyLightingHitTesting.key(at: renderedCenter, in: availableSize)?.lightIndex,
        key.lightIndex,
        "Failed to hit scaled \(key.id)"
      )
    }

    XCTAssertNil(
      AK47PerKeyLightingHitTesting.key(
        at: CGPoint(x: offset.x + 40 * scale, y: offset.y + 16 * scale),
        in: availableSize
      )
    )
    XCTAssertNil(
      AK47PerKeyLightingHitTesting.key(
        at: CGPoint(
          x: offset.x + AK47PhysicalLayout.lcdFrame.midX * scale,
          y: offset.y + AK47PhysicalLayout.lcdFrame.midY * scale
        ),
        in: availableSize
      )
    )
    XCTAssertNil(
      AK47PerKeyLightingHitTesting.key(
        at: CGPoint(x: availableSize.width / 2, y: offset.y / 2),
        in: availableSize
      )
    )
  }
}
