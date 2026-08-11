import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class LCDExperimentalTransferGateTests: XCTestCase {
  func testGatePinsCapturedEndpointAndAcknowledgementEvidence() {
    XCTAssertEqual(LCDExperimentalTransferGate.expectedOutputEndpoint, 0x03)
    XCTAssertEqual(LCDExperimentalTransferGate.expectedInputEndpoint, 0x84)
    XCTAssertEqual(LCDExperimentalTransferGate.expectedAcknowledgementCount, 16)
  }

  func testAdapterTargetOperationAndSingleRiskAcknowledgementAreRequired() {
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

    gate.applyAcknowledgement.isAcknowledged = false
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

  func testMaximumBoundaryPurposeAcceptsExactlyOneHundredFortyFrames() {
    XCTAssertFalse(
      LCDQualifiedAnimationUploadPurpose.maximumBoundaryTrial.accepts(frameCount: 1)
    )
    XCTAssertFalse(
      LCDQualifiedAnimationUploadPurpose.maximumBoundaryTrial.accepts(frameCount: 40)
    )
    XCTAssertFalse(
      LCDQualifiedAnimationUploadPurpose.maximumBoundaryTrial.accepts(frameCount: 139)
    )
    XCTAssertTrue(
      LCDQualifiedAnimationUploadPurpose.maximumBoundaryTrial.accepts(frameCount: 140)
    )
    XCTAssertFalse(
      LCDQualifiedAnimationUploadPurpose.maximumBoundaryTrial.accepts(frameCount: 141)
    )
  }

  func testFinalQualifiedPurposeAcceptsOneThroughOneHundredFortyFrames() {
    XCTAssertFalse(LCDQualifiedAnimationUploadPurpose.qualified.accepts(frameCount: 0))
    XCTAssertTrue(LCDQualifiedAnimationUploadPurpose.qualified.accepts(frameCount: 1))
    XCTAssertTrue(LCDQualifiedAnimationUploadPurpose.qualified.accepts(frameCount: 40))
    XCTAssertTrue(LCDQualifiedAnimationUploadPurpose.qualified.accepts(frameCount: 140))
    XCTAssertFalse(LCDQualifiedAnimationUploadPurpose.qualified.accepts(frameCount: 141))
  }

  @MainActor
  func testMaximumBoundaryReceiptProjectionKeepsGeneralApplyLockedUntilFinalPowerEvidence() {
    let waiting = StudioModel.extendedQualificationViewState(
      AK47LCDExtendedUploadQualificationSnapshot(
        target: nil,
        state: .awaitingMaximumBoundaryTrial
      )
    )
    XCTAssertEqual(waiting, .awaitingMaximumBoundaryTrial)
    XCTAssertTrue(waiting.permitsMaximumBoundaryTrial)
    XCTAssertFalse(waiting.permitsExtendedUpload)

    let visual = StudioModel.extendedQualificationViewState(
      AK47LCDExtendedUploadQualificationSnapshot(
        target: nil,
        state: .awaitingMaximumBoundaryVisualAttestation,
        pendingContainerSHA256: String(repeating: "c", count: 64),
        pendingFrameCount: 140,
        pendingPageCount: 2_215
      )
    )
    XCTAssertEqual(
      visual,
      .awaitingMaximumBoundaryVisualAttestation(
        containerSHA256: String(repeating: "c", count: 64),
        frameCount: 140,
        pageCount: 2_215
      )
    )
    XCTAssertFalse(visual.permitsExtendedUpload)

    for state in [
      AK47LCDExtendedUploadQualificationState
        .awaitingMaximumBoundaryObservedUSBDisconnection,
      .awaitingMaximumBoundaryExactSamePortReappearance,
      .awaitingMaximumBoundaryUSBPowerCycleAttestation,
    ] {
      XCTAssertFalse(
        StudioModel.extendedQualificationViewState(
          AK47LCDExtendedUploadQualificationSnapshot(target: nil, state: state)
        ).permitsExtendedUpload
      )
    }

    let qualified = StudioModel.extendedQualificationViewState(
      AK47LCDExtendedUploadQualificationSnapshot(
        target: nil,
        state: .qualified(maximumFrameCount: 140)
      )
    )
    XCTAssertTrue(qualified.permitsExtendedUpload)
  }

  func testSessionGateCannotRecordSuccessRecoveryOrMaximumFrameAuthorization() {
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

  func testReadOnlyReceiptProjectionPermitsOnlyFinalOneHundredFortyFrameQualification() {
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
      LCDExtendedQualificationViewState.awaitingMaximumBoundaryTrial
        .permitsExtendedUpload)
    XCTAssertTrue(
      LCDExtendedQualificationViewState.awaitingMaximumBoundaryTrial
        .permitsMaximumBoundaryTrial)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.maximumBoundaryTransferInProgress
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingMaximumBoundaryVisualAttestation(
        containerSHA256: String(repeating: "b", count: 64),
        frameCount: 140,
        pageCount: 2_215
      ).permitsExtendedUpload
    )
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingMaximumBoundaryObservedAbsence
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingMaximumBoundaryExactReappearance
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.awaitingMaximumBoundaryWiredPowerRemovalAttestation
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.maximumBoundaryVisualMismatchQuarantinePending
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
    XCTAssertFalse(
      LCDExtendedQualificationViewState.qualified(maximumFrameCount: 40)
        .permitsExtendedUpload)
    XCTAssertTrue(
      LCDExtendedQualificationViewState.qualified(maximumFrameCount: 140)
        .permitsExtendedUpload)
    XCTAssertFalse(
      LCDExtendedQualificationViewState.blocked("receipt read failed")
        .permitsExtendedUpload)
  }

  func testDetailedQualificationStepsStartCollapsedAndHideWhenQualified() {
    XCTAssertFalse(LCDExtendedQualificationDetailsPresentation.initiallyExpanded)
    XCTAssertTrue(
      LCDExtendedQualificationDetailsPresentation.isAvailable(for: .receiptUnavailable)
    )
    XCTAssertTrue(
      LCDExtendedQualificationDetailsPresentation.isAvailable(
        for: .awaitingMaximumBoundaryTrial
      )
    )
    XCTAssertFalse(
      LCDExtendedQualificationDetailsPresentation.isAvailable(
        for: .qualified(maximumFrameCount: 140)
      )
    )
  }

  private func fullyAcknowledgedGate() -> LCDExperimentalTransferGate {
    var gate = LCDExperimentalTransferGate()
    gate.applyAcknowledgement.isAcknowledged = true
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
