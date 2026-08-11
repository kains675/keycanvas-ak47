import XCTest

@testable import AK47StudioApp

final class LCDExperimentalTransferGateTests: XCTestCase {
  func testGatePinsCapturedEndpointAndAcknowledgementEvidence() {
    XCTAssertEqual(LCDExperimentalTransferGate.expectedOutputEndpoint, 0x03)
    XCTAssertEqual(LCDExperimentalTransferGate.expectedInputEndpoint, 0x84)
    XCTAssertEqual(LCDExperimentalTransferGate.expectedAcknowledgementCount, 16)
  }

  func testAdapterTargetOperationAndEveryRiskAcknowledgementAreRequired() {
    var gate = fullyAcknowledgedGate()

    XCTAssertFalse(
      gate.canRequestOneFrameUpload(
        adapterLinked: false,
        exactTargetReady: true,
        deviceOperationAllowed: true
      ))
    XCTAssertFalse(
      gate.canRequestOneFrameUpload(
        adapterLinked: true,
        exactTargetReady: false,
        deviceOperationAllowed: true
      ))
    XCTAssertFalse(
      gate.canRequestOneFrameUpload(
        adapterLinked: true,
        exactTargetReady: true,
        deviceOperationAllowed: false
      ))

    gate.confirmsColdRecoveryIsPrepared = false
    XCTAssertFalse(
      gate.canRequestOneFrameUpload(
        adapterLinked: true,
        exactTargetReady: true,
        deviceOperationAllowed: true
      ))
  }

  func testOneFrameConfirmationCanBeConsumedOnlyOnce() {
    var gate = fullyAcknowledgedGate()

    XCTAssertTrue(
      gate.consumeOneFrameConfirmation(
        adapterLinked: true,
        exactTargetReady: true,
        deviceOperationAllowed: true
      ))
    XCTAssertTrue(gate.confirmationWasConsumed)
    XCTAssertFalse(
      gate.consumeOneFrameConfirmation(
        adapterLinked: true,
        exactTargetReady: true,
        deviceOperationAllowed: true
      ))
  }

  func testSessionGateCannotRecordSuccessRecoveryOrFortyFrameAuthorization() {
    let source = try! String(
      contentsOf:
        projectRoot
        .appendingPathComponent("Sources/AK47StudioApp/LCDExperimentalTransferGate.swift"),
      encoding: .utf8
    )

    XCTAssertFalse(source.contains("recordOneFrameOutcome"))
    XCTAssertFalse(source.contains("recordObservedTargetAbsence"))
    XCTAssertFalse(source.contains("recordObservedExactTargetReappearance"))
    XCTAssertFalse(source.contains("recordFullPowerCycleAttestation"))
    XCTAssertFalse(source.contains("empiricalExtendedFrameLimit"))
  }

  func testReadOnlyReceiptProjectionPermitsOnlyExactFortyFrameQualification() {
    XCTAssertFalse(LCDExtendedQualificationViewState.receiptUnavailable.permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingVisualAttestation.permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingObservedAbsence.permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingExactReappearance.permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingWiredPowerRemovalAttestation
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.canonicalTransferInProgress
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.canonicalVisualMismatchQuarantinePending
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.extendedTransferInProgress
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingExtendedVisualAttestation(
        containerSHA256: String(repeating: "a", count: 64),
        frameCount: 40,
        pageCount: 633
      ).permitsExtendedUpload
    )
    XCTAssertFalse(
      LCDExtendedQualificationViewState.extendedVisualMismatchQuarantinePending
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.interruptedTransferQuarantinePending
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.invalidatedRequiresFreshDiagnostic
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.qualified(maximumFrameCount: 39)
        .permitsExtendedUpload)
    XCTAssertTrue(
      LCDExtendedQualificationViewState.qualified(maximumFrameCount: 40)
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.blocked("receipt read failed")
        .permitsExtendedUpload)
  }

  private func fullyAcknowledgedGate() -> LCDExperimentalTransferGate {
    var gate = LCDExperimentalTransferGate()
    gate.acknowledgesCurrentImageOverwrite = true
    gate.acknowledgesNoReadbackOrRollback = true
    gate.confirmsOtherUtilitiesAndVMsAreClosed = true
    gate.confirmsColdRecoveryIsPrepared = true
    return gate
  }

  private func consumedGate() -> LCDExperimentalTransferGate {
    var gate = fullyAcknowledgedGate()
    XCTAssertTrue(
      gate.consumeOneFrameConfirmation(
        adapterLinked: true,
        exactTargetReady: true,
        deviceOperationAllowed: true
      ))
    return gate
  }

  private var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
