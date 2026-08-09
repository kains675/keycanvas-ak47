import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class AK47PerKeyLightingDraftTests: XCTestCase {
  func testFillUsesAllExactFirmwareLightIndices() {
    let color = AK47InspectorCore.RGBColor(red: 12, green: 34, blue: 56)
    var draft = AK47PerKeyLightingDraft()

    draft.fill(color)

    XCTAssertEqual(draft.configuredKeyCount, 84)
    XCTAssertEqual(draft.entries.count, 84)
    XCTAssertEqual(
      Set(draft.entries.map(\.position)),
      Set(AK47PhysicalLayout.keys.map(\.lightIndex))
    )
    XCTAssertTrue(draft.entries.allSatisfy { $0.color == color && $0.intensityPercent == 100 })
  }

  func testPaintingAndClearingOnePhysicalKeyUsesItsLightIndex() throws {
    let key = try XCTUnwrap(AK47PhysicalLayout.keys.first { $0.id == "Space" })
    let color = AK47InspectorCore.RGBColor(red: 255, green: 90, blue: 0)
    var draft = AK47PerKeyLightingDraft()

    draft.setColor(color, at: key.lightIndex)

    XCTAssertEqual(draft.entry(at: key.lightIndex)?.position, key.lightIndex)
    XCTAssertEqual(draft.entry(at: key.lightIndex)?.color, color)
    draft.clear(lightIndex: key.lightIndex)
    XCTAssertNil(draft.entry(at: key.lightIndex))
  }

  func testUnsupportedPositionIsPreservedOnLoadButCannotBePainted() {
    let legacy = PerKeyLighting(
      position: 0,
      color: AK47InspectorCore.RGBColor(red: 1, green: 2, blue: 3),
      intensityPercent: 40
    )
    var draft = AK47PerKeyLightingDraft(entries: [legacy])

    draft.setColor(AK47InspectorCore.RGBColor(red: 4, green: 5, blue: 6), at: 999)

    XCTAssertEqual(draft.entries, [legacy])
    XCTAssertEqual(draft.configuredKeyCount, 0)
  }

  func testClearAllRemovesEveryEntry() {
    var draft = AK47PerKeyLightingDraft(entries: [
      PerKeyLighting(
        position: 0,
        color: AK47InspectorCore.RGBColor(red: 1, green: 2, blue: 3)
      )
    ])
    draft.fill(AK47InspectorCore.RGBColor(red: 10, green: 20, blue: 30))

    draft.clearAll()

    XCTAssertTrue(draft.entries.isEmpty)
    XCTAssertEqual(draft.configuredKeyCount, 0)
  }
}
