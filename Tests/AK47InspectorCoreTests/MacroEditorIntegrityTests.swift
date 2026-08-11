import Foundation
import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class MacroEditorIntegrityTests: XCTestCase {
  func testEmptyProfileLoadsAsAnActuallyEmptyDraftList() {
    XCTAssertTrue(MacroEditorIntegrity.drafts(from: []).isEmpty)
  }

  func testExistingMacroDefinitionRoundTripsThroughEditorDraft() {
    let definition = MacroDefinition(
      identifier: "macro-round-trip",
      name: "Round trip",
      repeatCount: 7,
      events: [
        .keyDown(0x04),
        .delay(milliseconds: 1),
        .delay(milliseconds: 60_000),
        .keyUp(0x04),
      ]
    )

    XCTAssertEqual(MacroDraft(definition).definition, definition)
  }

  func testMacroKeyAssignmentChoicePreservesIdentifier() {
    let action = KeyAction.macro(identifier: "macro-round-trip")
    let choice = KeymapAssignmentChoice(action: action)

    XCTAssertEqual(choice, .macro(identifier: "macro-round-trip"))
    XCTAssertEqual(choice.action, action)
  }

  func testDuplicateUsesNewIdentityAndCopiesEvents() {
    let source = MacroDraft(
      MacroDefinition(
        identifier: "source",
        name: "Source",
        repeatCount: 3,
        events: [.keyDown(0x04), .delay(milliseconds: 25), .keyUp(0x04)]
      )
    )

    let duplicate = source.duplicate(identifier: "copy", name: "Source Copy")

    XCTAssertEqual(duplicate.id, "copy")
    XCTAssertEqual(duplicate.name, "Source Copy")
    XCTAssertEqual(duplicate.repeatCount, source.repeatCount)
    XCTAssertEqual(duplicate.steps.map(\.event), source.steps.map(\.event))
    XCTAssertEqual(Set(duplicate.steps.map(\.id)).count, source.steps.count)
    XCTAssertTrue(Set(duplicate.steps.map(\.id)).isDisjoint(with: source.steps.map(\.id)))
  }

  func testReferencedMacroLookupOnlyReturnsExactAssignments() {
    let keymap = KeymapProfile(assignments: [
      KeyAssignment(layer: 0, position: 2, action: .macro(identifier: "target")),
      KeyAssignment(layer: 1, position: 7, action: .macro(identifier: "target")),
      KeyAssignment(layer: 0, position: 8, action: .macro(identifier: "other")),
      KeyAssignment(layer: 0, position: 9, action: .keyCode(0x04)),
    ])

    let references = MacroEditorIntegrity.references(to: "target", in: keymap)

    XCTAssertEqual(references.map(\.position), [2, 7])
  }

  func testStepReorderPreservesEveryEvent() {
    var draft = MacroDraft(
      MacroDefinition(
        identifier: "reorder",
        name: "Reorder",
        events: [.keyDown(0x04), .delay(milliseconds: 25), .keyUp(0x04)]
      )
    )

    draft.moveStep(from: 1, to: 2)

    XCTAssertEqual(
      draft.steps.map(\.event),
      [.keyDown(0x04), .keyUp(0x04), .delay(milliseconds: 25)]
    )
    let reordered = draft.steps
    draft.moveStep(from: -1, to: 0)
    XCTAssertEqual(draft.steps, reordered)
  }

  func testDelayValidationAcceptsInclusiveBoundsAndRejectsOutsideValues() {
    var profile = DeviceProfile(identifier: "profile", name: "Profile")

    for validDelay in [1, 60_000] {
      let draft = MacroDraft(
        MacroDefinition(
          identifier: "delay",
          name: "Delay",
          events: [.delay(milliseconds: validDelay)]
        )
      )
      XCTAssertTrue(MacroEditorIntegrity.validationIssues(for: [draft], in: profile).isEmpty)
    }

    profile.macros = []
    for invalidDelay in [0, 60_001] {
      let draft = MacroDraft(
        MacroDefinition(
          identifier: "delay",
          name: "Delay",
          events: [.delay(milliseconds: invalidDelay)]
        )
      )
      XCTAssertTrue(
        MacroEditorIntegrity.validationIssues(for: [draft], in: profile).contains {
          $0.code == "invalid-delay"
        }
      )
    }
  }

  @MainActor
  func testSavedProfilePreservesMacroAssignmentAndMacroDefinition() throws {
    let storageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("keycanvas-macro-integrity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: storageDirectory) }

    let macro = MacroDefinition(
      identifier: "saved-macro",
      name: "Saved macro",
      events: [.keyDown(0x04), .delay(milliseconds: 20), .keyUp(0x04)]
    )
    let store = LocalProfileStore(storageDirectory: storageDirectory)
    store.replaceMacros([macro])
    store.setKeyAssignment(.macro(identifier: macro.identifier), position: 4, layer: 1)
    store.saveSelected()

    guard case .saved = store.status else {
      return XCTFail("expected macro profile to save")
    }

    let reloaded = LocalProfileStore(storageDirectory: storageDirectory).selectedProfile
    XCTAssertEqual(reloaded.macros, [macro])
    XCTAssertEqual(
      reloaded.keymap.assignments.first(where: { $0.layer == 1 && $0.position == 4 })?.action,
      .macro(identifier: macro.identifier)
    )
  }
}
