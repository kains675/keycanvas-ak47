import XCTest

@testable import AK47InspectorCore

final class HIDDeviceOperationGateTests: XCTestCase {
  private let target = AK47WiredDeviceTarget(
    locationID: 0x0014_0000,
    versionNumber: 0x0115
  )

  func testFailureBeforeWriteAheadSubmissionReleasesGate() throws {
    let gate = HIDDeviceOperationGateState()
    let identity = HIDDeviceQuarantineIdentity(target: target)
    let evidence = gate.makeTransactionEvidence()

    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    try gate.finish(succeeded: false, evidence: evidence)

    XCTAssertFalse(gate.isQuarantined)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    gate.releaseReadOnlyOperation()
  }

  func testWriteAheadMarkerExistsBeforeSubmittedReportIsRecorded() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    let evidence = gate.makeTransactionEvidence()

    try evidence.prepareForSubmission()

    XCTAssertEqual(persistence.identities, [identity])
    XCTAssertFalse(evidence.hasSubmittedReport)
    evidence.recordSubmittedReport()
    try gate.finish(succeeded: false, evidence: evidence)
  }

  func testCrashSimulationLeavesMarkerAcrossNewGateInstance() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let identity = HIDDeviceQuarantineIdentity(target: target)

    do {
      let firstProcess = HIDDeviceOperationGateState(persistence: persistence)
      XCTAssertEqual(firstProcess.acquire(target: identity), .acquired)
      let evidence = firstProcess.makeTransactionEvidence()
      try evidence.prepareForSubmission()
      evidence.recordSubmittedReport()
      // No finish: simulates force quit after the IOHID call began.
    }

    let restartedProcess = HIDDeviceOperationGateState(persistence: persistence)
    XCTAssertEqual(restartedProcess.acquire(target: identity), .quarantined)
  }

  func testSubmittedFailureQuarantinesEvenAfterConfirmedCancellation() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    let evidence = gate.makeTransactionEvidence()
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()

    try gate.finish(succeeded: false, evidence: evidence)

    XCTAssertTrue(gate.isQuarantined)
    XCTAssertEqual(gate.acquire(target: identity), .quarantined)
  }

  func testSuccessfulSubmittedTransactionDurablyClearsMarker() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    let evidence = gate.makeTransactionEvidence()
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()

    try gate.finish(succeeded: true, evidence: evidence)

    XCTAssertTrue(persistence.identities.isEmpty)
    XCTAssertFalse(gate.isQuarantined)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    gate.releaseReadOnlyOperation()
  }

  func testSynchronousSubmissionFailureClearsOnlyAfterSafeCleanupEvidence() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let identity = HIDDeviceQuarantineIdentity(target: target)

    do {
      let unsafeGate = HIDDeviceOperationGateState(persistence: persistence)
      XCTAssertEqual(unsafeGate.acquire(target: identity), .acquired)
      let evidence = unsafeGate.makeTransactionEvidence()
      try evidence.prepareForSubmission()
      try unsafeGate.finish(succeeded: false, evidence: evidence)
    }
    XCTAssertEqual(
      HIDDeviceOperationGateState(persistence: persistence).acquire(target: identity),
      .quarantined
    )

    try persistence.save([])
    let safeGate = HIDDeviceOperationGateState(persistence: persistence)
    XCTAssertEqual(safeGate.acquire(target: identity), .acquired)
    let safeEvidence = safeGate.makeTransactionEvidence()
    try safeEvidence.prepareForSubmission()
    safeEvidence.recordSafePreSubmissionCleanup()
    try safeGate.finish(succeeded: false, evidence: safeEvidence)
    XCTAssertTrue(persistence.identities.isEmpty)
  }

  func testWriteAheadPersistenceFailurePreventsIOCall() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    let evidence = gate.makeTransactionEvidence()
    persistence.failsSaves = true
    var simulatedIOCallCount = 0

    XCTAssertThrowsError(try evidence.prepareForSubmission())
    if !persistence.failsSaves {
      simulatedIOCallCount += 1
    }

    XCTAssertEqual(simulatedIOCallCount, 0)
    try gate.finish(succeeded: false, evidence: evidence)
    XCTAssertTrue(gate.isQuarantined)
  }

  func testMarkerClearFailureIsThrownAndGateStaysQuarantined() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    let evidence = gate.makeTransactionEvidence()
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()
    persistence.failsSaves = true

    XCTAssertThrowsError(try gate.finish(succeeded: true, evidence: evidence))

    XCTAssertEqual(persistence.identities, [identity])
    XCTAssertTrue(gate.isQuarantined)
  }

  func testTwoProcessStatesCannotHoldTransactionLockTogether() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let firstProcess = HIDDeviceOperationGateState(persistence: persistence)
    let secondProcess = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)

    XCTAssertEqual(firstProcess.acquire(target: identity), .acquired)
    XCTAssertEqual(secondProcess.acquire(target: identity), .busy)
    firstProcess.releaseReadOnlyOperation()
    XCTAssertEqual(secondProcess.acquire(target: identity), .acquired)
    secondProcess.releaseReadOnlyOperation()
  }

  func testExactReappearanceWithoutObservedAbsenceNeverEnablesClear() throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    let persistence = HIDDeviceQuarantineMemoryPersistence(identities: [identity])
    let gate = HIDDeviceOperationGateState(persistence: persistence)

    gate.observeSuccessfulEnumeration(exactRecords(for: target))

    XCTAssertEqual(gate.recoveryState(for: identity), .awaitingObservedAbsence)
    XCTAssertThrowsError(try gate.acknowledgeFullPowerCycle(for: identity))
    XCTAssertEqual(gate.acquire(target: identity), .quarantined)
  }

  func testPartialTopologyDoesNotCountAsAbsence() {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    let persistence = HIDDeviceQuarantineMemoryPersistence(identities: [identity])
    let gate = HIDDeviceOperationGateState(persistence: persistence)

    gate.observeSuccessfulEnumeration(Array(exactRecords(for: target).prefix(3)))

    XCTAssertEqual(gate.recoveryState(for: identity), .awaitingObservedAbsence)
  }

  func testAbsenceAndExactReappearanceStillRequireExplicitPowerCycleAcknowledgement() throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    let persistence = HIDDeviceQuarantineMemoryPersistence(identities: [identity])
    let gate = HIDDeviceOperationGateState(persistence: persistence)

    gate.observeSuccessfulEnumeration([])
    XCTAssertEqual(gate.recoveryState(for: identity), .awaitingExactReappearance)
    gate.observeSuccessfulEnumeration(exactRecords(for: target))
    XCTAssertEqual(
      gate.recoveryState(for: identity),
      .awaitingFullPowerCycleAcknowledgement
    )
    XCTAssertEqual(gate.acquire(target: identity), .quarantined)

    try gate.acknowledgeFullPowerCycle(for: identity)

    XCTAssertTrue(persistence.identities.isEmpty)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    gate.releaseReadOnlyOperation()
  }

  func testSeriallessMarkerBlocksOtherPortAndCannotUseItAsExactReappearance() {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    let persistence = HIDDeviceQuarantineMemoryPersistence(identities: [identity])
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let otherPortTarget = AK47WiredDeviceTarget(
      locationID: 0x0020_0000,
      versionNumber: 0x0115
    )
    let otherIdentity = HIDDeviceQuarantineIdentity(target: otherPortTarget)

    XCTAssertEqual(gate.acquire(target: otherIdentity), .quarantined)
    gate.observeSuccessfulEnumeration([])
    gate.observeSuccessfulEnumeration(exactRecords(for: otherPortTarget))

    XCTAssertEqual(gate.recoveryState(for: otherIdentity), .awaitingExactReappearance)
    XCTAssertEqual(gate.acquire(target: otherIdentity), .quarantined)
  }

  func testWrongSerializedTargetCannotClearMarker() throws {
    let serializedTarget = AK47WiredDeviceTarget(
      locationID: target.locationID,
      versionNumber: target.versionNumber,
      serialNumber: "AK47-A"
    )
    let identity = HIDDeviceQuarantineIdentity(target: serializedTarget)
    let persistence = HIDDeviceQuarantineMemoryPersistence(identities: [identity])
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let wrongTarget = AK47WiredDeviceTarget(
      locationID: target.locationID,
      versionNumber: target.versionNumber,
      serialNumber: "AK47-B"
    )

    gate.observeSuccessfulEnumeration([])
    gate.observeSuccessfulEnumeration(exactRecords(for: wrongTarget))

    XCTAssertEqual(gate.recoveryState(for: identity), .awaitingExactReappearance)
    XCTAssertThrowsError(
      try gate.acknowledgeFullPowerCycle(
        for: HIDDeviceQuarantineIdentity(target: wrongTarget)
      )
    )
    XCTAssertEqual(persistence.identities, [identity])
  }

  func testFirstSubmittedFailureIsWrappedWithImmediateRecoveryGuidance() throws {
    let evidence = HIDDeviceTransactionEvidence()
    evidence.recordSubmittedReport()
    let originalWrite = AK47DeviceWriteError.operationTimedOut(stage: .begin)
    let originalQuery = AK47PerKeyRGBQueryAdapterError.operationTimedOut(
      stage: .queryCommand
    )

    let writeError = try XCTUnwrap(
      AK47DeviceWriteAdapter.errorForFailedTransaction(
        originalWrite,
        evidence: evidence
      ) as? AK47DeviceWriteError
    )
    let queryError = try XCTUnwrap(
      AK47PerKeyRGBQueryAdapter.errorForFailedTransaction(
        originalQuery,
        evidence: evidence
      ) as? AK47PerKeyRGBQueryAdapterError
    )

    guard case .partialTransactionQuarantined(let writeCause) = writeError,
      case .partialTransactionQuarantined(let queryCause) = queryError
    else {
      return XCTFail("submitted failures must use the dedicated quarantine error")
    }
    XCTAssertTrue(writeCause.contains("360 ms"))
    XCTAssertTrue(queryCause.contains("360 ms"))
    for error in [writeError.localizedDescription, queryError.localizedDescription] {
      XCTAssertTrue(error.contains("refresh Device Inspector while it is absent"))
      XCTAssertTrue(error.contains("Relaunching alone does not clear"))
    }
  }

  func testUnsubmittedFailurePreservesOriginalError() {
    let evidence = HIDDeviceTransactionEvidence()
    let original = AK47DeviceWriteError.openFailed(1)

    XCTAssertEqual(
      AK47DeviceWriteAdapter.errorForFailedTransaction(
        original,
        evidence: evidence
      ) as? AK47DeviceWriteError,
      original
    )
  }

  func testFilePersistenceUsesAtomicMarkerAndNonblockingLifetimeLock() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let marker = directory.appendingPathComponent("quarantine.json")
    let persistence = HIDDeviceQuarantineFilePersistence(markerURL: marker)
    let identity = HIDDeviceQuarantineIdentity(target: target)

    let firstLock = try persistence.acquireProcessLock()
    XCTAssertThrowsError(try persistence.acquireProcessLock())
    try persistence.save([identity])
    XCTAssertEqual(try persistence.load(), [identity])
    firstLock.release()

    let secondLock = try persistence.acquireProcessLock()
    try persistence.save([])
    XCTAssertEqual(try persistence.load(), [])
    secondLock.release()
  }

  func testClearDirectorySyncFailureKeepsQuarantineAcrossRestart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let marker = directory.appendingPathComponent("quarantine.json")
    let persistence = HIDDeviceQuarantineFilePersistence(markerURL: marker)
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    XCTAssertEqual(gate.acquire(target: identity), .acquired)
    let evidence = gate.makeTransactionEvidence()
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()

    // Clear syncs the staged rollback record, then the cleared primary, then
    // the pending-record removal. Fail that final directory fsync after the
    // unlink has occurred.
    persistence.injectedDirectorySynchronizationFailureCountdown = 3
    XCTAssertThrowsError(try gate.finish(succeeded: true, evidence: evidence))

    let restartedPersistence = HIDDeviceQuarantineFilePersistence(markerURL: marker)
    XCTAssertEqual(try restartedPersistence.load(), [identity])
    let restartedGate = HIDDeviceOperationGateState(persistence: restartedPersistence)
    XCTAssertEqual(restartedGate.acquire(target: identity), .quarantined)
  }

  private func exactRecords(
    for target: AK47WiredDeviceTarget
  ) -> [HIDCollectionRecord] {
    [
      record(target: target, usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
      record(
        target: target, usagePage: 0x000C, usage: 0x0001, input: 16, output: 1,
        feature: 1),
      record(
        target: target, usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64,
        feature: 64),
      record(
        target: target, usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096,
        feature: 0),
    ]
  }

  private func record(
    target: AK47WiredDeviceTarget,
    usagePage: UInt64,
    usage: UInt64,
    input: UInt64,
    output: UInt64,
    feature: UInt64
  ) -> HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: HIDEnumerator.vendorID,
      productID: HIDEnumerator.productID,
      product: target.product,
      manufacturer: "SONiX",
      serialNumber: target.serialNumber,
      transport: "USB",
      versionNumber: target.versionNumber,
      locationID: target.locationID,
      usagePage: usagePage,
      usage: usage,
      maxInputReportSize: input,
      maxOutputReportSize: output,
      maxFeatureReportSize: feature
    )
  }
}
