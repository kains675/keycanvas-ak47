import XCTest

@testable import AK47StudioApp

final class LCDExperimentalApplyAcknowledgementTests: XCTestCase {
  func testAcknowledgementUsesRequestedKoreanPhraseAndEnglishLocalization() {
    XCTAssertEqual(
      LCDExperimentalApplyAcknowledgement.koreanText,
      "현재 프로그램은 실험적 기능임에 따라 장치 이상, 고장이 발생 할 수 있음을 인지하고 있습니다."
    )
    XCTAssertEqual(
      LCDExperimentalApplyAcknowledgement.englishText,
      "I understand that this program is experimental and may cause device malfunction or failure."
    )
  }

  func testApplyRequiresTheSingleAcknowledgementAndConsumesItOnlyOnce() {
    var acknowledgement = LCDExperimentalApplyAcknowledgement()

    XCTAssertFalse(acknowledgement.canApply)
    XCTAssertFalse(acknowledgement.consume())

    acknowledgement.isAcknowledged = true
    XCTAssertTrue(acknowledgement.canApply)
    XCTAssertTrue(acknowledgement.consume())
    XCTAssertTrue(acknowledgement.wasConsumed)
    XCTAssertFalse(acknowledgement.canApply)
    XCTAssertFalse(acknowledgement.consume())
  }

  func testBothLCDApplyViewsUseTheSharedSingleAcknowledgement() throws {
    let transferGateSource = try source("LCDExperimentalTransferGate.swift")
    let editorSource = try source("DisplayAnimationEditorView.swift")

    XCTAssertEqual(
      occurrences(
        of: "Toggle(isOn: $gate.applyAcknowledgement.isAcknowledged)",
        in: transferGateSource
      ),
      1
    )
    XCTAssertEqual(
      occurrences(
        of: "isOn: $applyAcknowledgement.isAcknowledged",
        in: editorSource
      ),
      1
    )
    XCTAssertFalse(transferGateSource.contains("showsFinalConfirmation"))
    XCTAssertFalse(
      transferGateSource.contains("Overwrite the current LCD image with the one-frame diagnostic?")
    )
    for removedState in [
      "acknowledgesCurrentImageOverwrite",
      "acknowledgesNoReadbackOrRollback",
      "acknowledgesInputsAreNotAcceptance",
      "confirmsOtherUtilitiesAndVMsAreClosed",
      "confirmsLongTransferSafety",
      "confirmsColdRecoveryIsPrepared",
      "confirmsRecoveryPrepared",
    ] {
      XCTAssertFalse(transferGateSource.contains(removedState))
      XCTAssertFalse(editorSource.contains(removedState))
    }
  }

  private func source(_ filename: String) throws -> String {
    try String(
      contentsOf:
        projectRoot
        .appendingPathComponent("Sources/AK47StudioApp")
        .appendingPathComponent(filename),
      encoding: .utf8
    )
  }

  private func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
  }

  private var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
