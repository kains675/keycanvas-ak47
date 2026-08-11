import XCTest

@testable import AK47StudioApp

final class DisplayEditorReplacementPolicyTests: XCTestCase {
  func testExistingEditorWithoutMountedDraftStateRequiresConfirmation() {
    XCTAssertEqual(
      DisplayEditorReplacementPolicy.decision(
        hasEditorInput: true,
        draftState: nil,
        replacementInProgress: false
      ),
      .confirmDiscard
    )
  }

  func testBusyOrAlreadyReplacingEditorIsBlocked() {
    let busy = DisplayAnimationEditorDraftState(
      hasUnexportedChanges: false,
      hasPendingSourceTransform: false,
      isBusy: true,
      requiresReplacementConfirmation: false
    )
    XCTAssertEqual(
      DisplayEditorReplacementPolicy.decision(
        hasEditorInput: true,
        draftState: busy,
        replacementInProgress: false
      ),
      .blocked
    )
    XCTAssertEqual(
      DisplayEditorReplacementPolicy.decision(
        hasEditorInput: false,
        draftState: nil,
        replacementInProgress: true
      ),
      .blocked
    )
  }

  func testDirtyDraftConfirmsAndCleanDraftProceeds() {
    let dirty = DisplayAnimationEditorDraftState(
      hasUnexportedChanges: true,
      hasPendingSourceTransform: false,
      isBusy: false,
      requiresReplacementConfirmation: true
    )
    let clean = DisplayAnimationEditorDraftState(
      hasUnexportedChanges: false,
      hasPendingSourceTransform: false,
      isBusy: false,
      requiresReplacementConfirmation: false
    )
    XCTAssertEqual(
      DisplayEditorReplacementPolicy.decision(
        hasEditorInput: true,
        draftState: dirty,
        replacementInProgress: false
      ),
      .confirmDiscard
    )
    XCTAssertEqual(
      DisplayEditorReplacementPolicy.decision(
        hasEditorInput: true,
        draftState: clean,
        replacementInProgress: false
      ),
      .proceed
    )
    XCTAssertEqual(
      DisplayEditorReplacementPolicy.decision(
        hasEditorInput: false,
        draftState: nil,
        replacementInProgress: false
      ),
      .proceed
    )
  }
}
