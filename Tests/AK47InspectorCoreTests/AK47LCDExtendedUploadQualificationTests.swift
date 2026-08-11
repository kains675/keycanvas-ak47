import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47LCDExtendedUploadQualificationTests: XCTestCase {
  func testFreshReceiptRequiresOrderedVisualAbsenceSamePortAndPowerAttestation() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 1_000))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = makeStore(persistence: persistence, clock: clock)
    let plan = try fixturePlan()

    XCTAssertEqual(store.snapshot.state, .unavailable)
    try recordCanonicalSuccess(store: store, plan: plan)
    XCTAssertEqual(
      store.snapshot,
      AK47LCDExtendedUploadQualificationSnapshot(
        target: plan.target,
        state: .awaitingCanonicalFixtureVisualAttestation
      )
    )

    clock.advance()
    try store.recordCanonicalFixtureVisualAttestation(
      for: plan.target,
      attestation: AK47LCDCanonicalFixtureVisualAttestation(
        explicitlyConfirmingCanonicalCornersAt: clock.value
      )
    )
    XCTAssertEqual(store.snapshot.state, .awaitingObservedUSBDisconnection)

    // With no serial number, another compatible AK47 anywhere still prevents
    // an absence observation from being accepted.
    store.observeSuccessfulHardwareEnumeration(exactTopology(locationID: 0x2222))
    XCTAssertEqual(store.snapshot.state, .awaitingObservedUSBDisconnection)

    clock.advance()
    store.observeSuccessfulHardwareEnumeration([])
    XCTAssertEqual(store.snapshot.state, .awaitingExactSamePortReappearance)

    let restarted = makeStore(persistence: persistence, clock: clock)
    restarted.observeSuccessfulHardwareEnumeration(exactTopology(locationID: 0x2222))
    XCTAssertEqual(restarted.snapshot.state, .awaitingExactSamePortReappearance)
    restarted.observeSuccessfulHardwareEnumeration(
      Array(exactTopology(locationID: plan.target.locationID).dropLast())
    )
    XCTAssertEqual(restarted.snapshot.state, .awaitingExactSamePortReappearance)

    clock.advance()
    restarted.observeSuccessfulHardwareEnumeration(
      exactTopology(locationID: plan.target.locationID)
    )
    XCTAssertEqual(restarted.snapshot.state, .awaitingUSBPowerCycleAttestation)

    clock.advance()
    try restarted.acknowledgeUSBModeCablePowerCycle(
      for: plan.target,
      attestation: AK47LCDUSBModeCablePowerCycleAttestation(
        explicitlyConfirmingUSBModeCableRemovalAt: clock.value
      )
    )
    XCTAssertEqual(restarted.snapshot.state, .awaitingMaximumBoundaryTrial)
    XCTAssertEqual(
      makeStore(persistence: persistence, clock: clock).snapshot.state,
      .awaitingMaximumBoundaryTrial
    )
  }

  func testQualificationCannotSkipVisualOrHardwareObservationOrder() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 2_000))
    let store = makeStore(clock: clock)
    let plan = try fixturePlan()
    try recordCanonicalSuccess(store: store, plan: plan)

    XCTAssertThrowsError(
      try store.acknowledgeUSBModeCablePowerCycle(
        for: plan.target,
        attestation: AK47LCDUSBModeCablePowerCycleAttestation(
          explicitlyConfirmingUSBModeCableRemovalAt: clock.value
        )
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDExtendedUploadQualificationError,
        .transitionNotAllowed
      )
    }
    store.observeSuccessfulHardwareEnumeration([])
    XCTAssertEqual(store.snapshot.state, .awaitingCanonicalFixtureVisualAttestation)

    XCTAssertThrowsError(
      try store.recordCanonicalFixtureVisualAttestation(
        for: plan.target,
        attestation: AK47LCDCanonicalFixtureVisualAttestation(
          explicitlyConfirmingCanonicalCornersAt: clock.value.addingTimeInterval(-1)
        )
      )
    )
  }

  func testQualifiedLeaseIsDurableAndSubmittedFailureRevokesQualification() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 3_000))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = try qualifiedStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)

    let lease = try store.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    XCTAssertEqual(store.snapshot.state, .extendedTransferInProgress)
    let restarted = makeStore(persistence: persistence, clock: clock)
    XCTAssertEqual(restarted.snapshot.state, .extendedTransferInProgress)
    XCTAssertThrowsError(
      try restarted.claimQualifiedLease(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
    )

    try restarted.finishQualifiedLease(lease, outcome: .submittedOrUncertainFailure)
    XCTAssertEqual(restarted.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertThrowsError(
      try restarted.claimQualifiedLease(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDExtendedUploadQualificationError,
        .qualificationRevoked
      )
    }
  }

  func testExtendedVisualMismatchIsDurableBlocksAuthorityAndReconcilesQuarantine() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 3_500))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let quarantine = QualificationQuarantineRecorder()
    let store = try qualifiedStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 3)
    let digest = AK47LCDUploadDigest.sha256Hex(plan.container.data)
    let lease = try store.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    clock.advance()
    try store.finishQualifiedLease(lease, outcome: .succeeded)
    XCTAssertEqual(store.snapshot.state, .awaitingExtendedVisualAttestation)

    quarantine.shouldFail = true
    let restarted = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertThrowsError(
      try restarted.reportQualifiedUploadVisualMismatch(
        for: plan.target,
        containerSHA256: digest
      )
    )
    XCTAssertEqual(restarted.snapshot.state, .extendedVisualMismatchQuarantinePending)
    let pendingReload = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertEqual(pendingReload.snapshot.state, .extendedVisualMismatchQuarantinePending)
    XCTAssertThrowsError(
      try pendingReload.claimQualifiedLease(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
    )
    XCTAssertThrowsError(
      try pendingReload.claimCanonicalTransfer(
        plan: fixturePlan(),
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(fixturePlan())
      )
    )
    XCTAssertThrowsError(
      try pendingReload.recordQualifiedUploadVisualAttestation(
        for: plan.target,
        attestation: .init(
          explicitlyConfirmingContainerSHA256: digest,
          at: clock.value
        )
      )
    )

    quarantine.shouldFail = false
    try pendingReload.reportQualifiedUploadVisualMismatch(
      for: plan.target,
      containerSHA256: digest
    )
    XCTAssertEqual(pendingReload.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertEqual(quarantine.targets, [HIDDeviceQuarantineIdentity(target: plan.target)])
    XCTAssertThrowsError(
      try pendingReload.recordQualifiedUploadVisualAttestation(
        for: plan.target,
        attestation: .init(
          explicitlyConfirmingContainerSHA256: digest,
          at: clock.value
        )
      )
    )
  }

  func testCanonicalVisualMismatchUsesSameDurableQuarantineHandshake() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 3_700))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let quarantine = QualificationQuarantineRecorder()
    let store = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    let plan = try fixturePlan()
    try recordCanonicalSuccess(store: store, plan: plan)

    quarantine.shouldFail = true
    XCTAssertThrowsError(try store.reportCanonicalFixtureVisualMismatch(for: plan.target))
    XCTAssertEqual(store.snapshot.state, .canonicalVisualMismatchQuarantinePending)
    let pendingReload = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertEqual(pendingReload.snapshot.state, .canonicalVisualMismatchQuarantinePending)
    XCTAssertThrowsError(
      try pendingReload.recordCanonicalFixtureVisualAttestation(
        for: plan.target,
        attestation: .init(explicitlyConfirmingCanonicalCornersAt: clock.value)
      )
    )

    quarantine.shouldFail = false
    try pendingReload.reportCanonicalFixtureVisualMismatch(for: plan.target)
    XCTAssertEqual(pendingReload.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertEqual(quarantine.targets.count, 1)
  }

  func testMarkerSuccessThenReceiptFinalizeFailureReloadsPendingAndCanReconcile() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 3_900))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let initial = try qualifiedStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 2)
    let digest = AK47LCDUploadDigest.sha256Hex(plan.container.data)
    let lease = try initial.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    try initial.finishQualifiedLease(lease, outcome: .succeeded)

    let quarantine = QualificationQuarantineRecorder()
    quarantine.afterSuccessfulQuarantine = { persistence.failsSaves = true }
    let store = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertThrowsError(
      try store.reportQualifiedUploadVisualMismatch(
        for: plan.target,
        containerSHA256: digest
      )
    )
    XCTAssertEqual(quarantine.targets.count, 1)
    XCTAssertEqual(store.snapshot.state, .persistenceUnavailable)

    persistence.failsSaves = false
    quarantine.afterSuccessfulQuarantine = nil
    let reloaded = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertEqual(reloaded.snapshot.state, .extendedVisualMismatchQuarantinePending)
    try reloaded.reportQualifiedUploadVisualMismatch(
      for: plan.target,
      containerSHA256: digest
    )
    XCTAssertEqual(reloaded.snapshot.state, .invalidatedRequiresFreshDiagnostic)
  }

  func testVisualMismatchQuarantineUsesExactDurableOperationGateIdentity() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)

    try gate.quarantine(target: identity)
    XCTAssertEqual(persistence.identities, [identity])
    XCTAssertEqual(gate.acquire(target: identity), .quarantined)
  }

  func testQuarantineBusyFromAnotherProcessCanRetryWithoutPoisoningState() throws {
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = HIDDeviceOperationGateState(persistence: persistence)
    let identity = HIDDeviceQuarantineIdentity(target: target)
    let competingProcessLock = try persistence.acquireProcessLock()

    XCTAssertThrowsError(try gate.quarantine(target: identity)) {
      XCTAssertEqual($0 as? HIDDeviceQuarantinePersistenceError, .busy)
    }
    XCTAssertTrue(persistence.identities.isEmpty)
    competingProcessLock.release()

    try gate.quarantine(target: identity)
    XCTAssertEqual(persistence.identities, [identity])
  }

  func testSuccessfulAndConfirmedPreSubmissionLeaseOutcomesRestoreQualifiedState() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 4_000))
    let store = try qualifiedStore(clock: clock)
    let plan = try qualifiedPlan(frameCount: 2)

    var lease = try store.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    try store.finishQualifiedLease(lease, outcome: .failedBeforeSubmissionWithConfirmedCleanup)
    XCTAssertEqual(store.snapshot.state, .qualified(maximumFrameCount: 140))

    lease = try store.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    clock.advance()
    try store.finishQualifiedLease(lease, outcome: .succeeded)
    XCTAssertEqual(store.snapshot.state, .awaitingExtendedVisualAttestation)
    try store.recordQualifiedUploadVisualAttestation(
      for: plan.target,
      attestation: .init(
        explicitlyConfirmingContainerSHA256: AK47LCDUploadDigest.sha256Hex(plan.container.data),
        at: clock.value
      )
    )
    XCTAssertEqual(store.snapshot.state, .qualified(maximumFrameCount: 140))
  }

  func testCanonicalRunRequiresAbsentOrInvalidatedReceiptAndClaimsDurably() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 5_000))
    let store = try qualifiedStore(clock: clock)
    let canonicalPlan = try fixturePlan()
    XCTAssertThrowsError(
      try store.claimCanonicalTransfer(
        plan: canonicalPlan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(canonicalPlan)
      )
    )

    let extendedPlan = try qualifiedPlan(frameCount: 2)
    let extendedLease = try store.claimQualifiedLease(
      plan: extendedPlan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(extendedPlan)
    )
    try store.finishQualifiedLease(extendedLease, outcome: .submittedOrUncertainFailure)
    XCTAssertEqual(store.snapshot.state, .invalidatedRequiresFreshDiagnostic)

    let canonicalLease = try store.claimCanonicalTransfer(
      plan: canonicalPlan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(canonicalPlan)
    )
    XCTAssertEqual(store.snapshot.state, .canonicalTransferInProgress)
    try store.finishCanonicalTransfer(canonicalLease, plan: canonicalPlan, outcome: .succeeded)
    XCTAssertEqual(store.snapshot.state, .awaitingCanonicalFixtureVisualAttestation)
  }

  func testCorruptLeaseMathUnicodeDigestAndTimestampChronologyFailClosed() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 6_000))
    let plan = try qualifiedPlan(frameCount: 2)

    do {
      let persistence = AK47LCDQualificationMemoryPersistence()
      let store = try qualifiedStore(persistence: persistence, clock: clock)
      _ = try store.claimQualifiedLease(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
      var record = try XCTUnwrap(persistence.load())
      record.activeFrameCount = Int.max
      try persistence.save(record)
      XCTAssertEqual(
        makeStore(persistence: persistence, clock: clock).snapshot.state,
        .persistenceUnavailable
      )
    }

    do {
      let persistence = AK47LCDQualificationMemoryPersistence()
      let store = try qualifiedStore(persistence: persistence, clock: clock)
      _ = try store.claimQualifiedLease(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
      var record = try XCTUnwrap(persistence.load())
      record.activePlanFingerprintSHA256 = String(repeating: "١", count: 64)
      try persistence.save(record)
      XCTAssertEqual(
        makeStore(persistence: persistence, clock: clock).snapshot.state,
        .persistenceUnavailable
      )
    }

    do {
      let persistence = AK47LCDQualificationMemoryPersistence()
      _ = try qualifiedStore(persistence: persistence, clock: clock)
      var record = try XCTUnwrap(persistence.load())
      record.canonicalVisualAttestedAt = try XCTUnwrap(record.canonicalTransferCompletedAt)
        .addingTimeInterval(-1)
      try persistence.save(record)
      XCTAssertEqual(
        makeStore(persistence: persistence, clock: clock).snapshot.state,
        .persistenceUnavailable
      )
    }
  }

  func testFileReceiptReloadsAndCorruptFileFailsClosed() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "KeyCanvas-Qualification-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let receiptURL = directory.appendingPathComponent("receipt.json")
    let persistence = AK47LCDQualificationFilePersistence(receiptURL: receiptURL)
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_000))
    let store = makeStore(persistence: persistence, clock: clock)
    try recordCanonicalSuccess(store: store, plan: fixturePlan())

    XCTAssertEqual(
      makeStore(
        persistence: AK47LCDQualificationFilePersistence(receiptURL: receiptURL),
        clock: clock
      ).snapshot.state,
      .awaitingCanonicalFixtureVisualAttestation
    )
    let permissions =
      try FileManager.default.attributesOfItem(atPath: receiptURL.path)[
        .posixPermissions
      ] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o600)

    try Data("not-json".utf8).write(to: receiptURL, options: .atomic)
    XCTAssertEqual(
      makeStore(
        persistence: AK47LCDQualificationFilePersistence(receiptURL: receiptURL),
        clock: clock
      ).snapshot.state,
      .persistenceUnavailable
    )
  }

  func testExpandedPolicyReplacesV1ReceiptWithFixedV2LiveLimits() {
    XCTAssertEqual(AK47LCDQualificationRecord.schemaVersion, 2)
    XCTAssertEqual(
      AK47LCDExtendedUploadQualificationStateStore.policyRevision,
      "ak47-lcd-qualified-upload-v2"
    )
    XCTAssertEqual(
      AK47LCDQualificationFilePersistence.production().receiptURL.lastPathComponent,
      "ak47-lcd-qualified-upload-v1.json"
    )
    XCTAssertEqual(AK47LCDUploadAdapter.qualifiedMaximumFrameCount, 140)
    XCTAssertEqual(AK47LCDUploadAdapter.qualifiedMaximumPageCount, 2_215)
    XCTAssertEqual(AK47LCDUploadAdapter.qualifiedMaximumContainerByteCount, 9_072_640)
    XCTAssertEqual(AK47LCDUploadAdapter.qualifiedTransferEndAddressExclusive, 0xFE_7000)
    XCTAssertGreaterThanOrEqual(
      AK47LCDFormat.maximumFrameCount,
      AK47LCDUploadAdapter.qualifiedMaximumFrameCount
    )
    XCTAssertGreaterThanOrEqual(
      AK47LCDUploadPreflight.maximumPageCount,
      AK47LCDUploadAdapter.qualifiedMaximumPageCount
    )
    XCTAssertGreaterThanOrEqual(
      AK47LCDFormat.maximumContainerByteCount,
      AK47LCDUploadAdapter.qualifiedMaximumContainerByteCount
    )
    XCTAssertGreaterThanOrEqual(
      AK47LCDUploadPreflight.softwareTransferEndLimit,
      AK47LCDUploadAdapter.qualifiedTransferEndAddressExclusive
    )
  }

  func testExactInactiveLegacyV1QualifiedReceiptMigratesAtomicallyToBoundaryTrial() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_100))
    let persistence = AK47LCDQualificationMemoryPersistence()
    _ = try maximumBoundaryReadyStore(persistence: persistence, clock: clock)
    var legacy = try XCTUnwrap(persistence.load())
    legacy.schemaVersion = 1
    legacy.policyRevision = AK47LCDExtendedUploadQualificationStateStore.legacyPolicyRevision
    legacy.phase = .qualified
    try persistence.save(legacy)

    XCTAssertFalse(AK47LCDExtendedUploadQualificationStateStore.isValid(legacy))
    XCTAssertNotNil(
      AK47LCDExtendedUploadQualificationStateStore.migratedLegacyV1Record(legacy)
    )

    let migratedStore = makeStore(persistence: persistence, clock: clock)
    XCTAssertEqual(migratedStore.snapshot.state, .awaitingMaximumBoundaryTrial)
    let migrated = try XCTUnwrap(persistence.load())
    XCTAssertEqual(migrated.schemaVersion, 2)
    XCTAssertEqual(
      migrated.policyRevision,
      AK47LCDExtendedUploadQualificationStateStore.policyRevision
    )
    XCTAssertEqual(migrated.phase, .awaitingMaximumBoundaryTrial)
    XCTAssertEqual(migrated.target, legacy.target)
    XCTAssertEqual(migrated.canonicalTransferStartedAt, legacy.canonicalTransferStartedAt)
    XCTAssertEqual(migrated.canonicalTransferCompletedAt, legacy.canonicalTransferCompletedAt)
    XCTAssertEqual(migrated.canonicalVisualAttestedAt, legacy.canonicalVisualAttestedAt)
    XCTAssertEqual(
      migrated.usbDisconnectionAbsenceObservedAt,
      legacy.usbDisconnectionAbsenceObservedAt
    )
    XCTAssertEqual(
      migrated.exactSamePortReappearanceObservedAt,
      legacy.exactSamePortReappearanceObservedAt
    )
    XCTAssertEqual(
      migrated.usbModeCablePowerCycleAttestedAt,
      legacy.usbModeCablePowerCycleAttestedAt
    )
    XCTAssertTrue(AK47LCDExtendedUploadQualificationStateStore.isValid(migrated))
  }

  func testActualProductionV1ReceiptMigrationDryRunNeverWritesProduction() throws {
    let productionURL = AK47LCDQualificationFilePersistence.production().receiptURL
    guard FileManager.default.fileExists(atPath: productionURL.path) else {
      throw XCTSkip("No local production v1 LCD qualification receipt is present.")
    }
    let originalData = try Data(contentsOf: productionURL, options: .mappedIfSafe)
    let legacy = try JSONDecoder().decode(AK47LCDQualificationRecord.self, from: originalData)
    guard legacy.schemaVersion == 1,
      legacy.policyRevision == AK47LCDExtendedUploadQualificationStateStore.legacyPolicyRevision,
      legacy.phase == .qualified
    else {
      throw XCTSkip("The local production receipt is not an eligible inactive v1 receipt.")
    }
    XCTAssertFalse(AK47LCDExtendedUploadQualificationStateStore.isValid(legacy))
    XCTAssertNotNil(
      AK47LCDExtendedUploadQualificationStateStore.migratedLegacyV1Record(legacy)
    )

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "KeyCanvas-V1-Migration-DryRun-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let copiedReceiptURL = directory.appendingPathComponent(productionURL.lastPathComponent)
    try originalData.write(to: copiedReceiptURL, options: .atomic)
    let copiedPersistence = AK47LCDQualificationFilePersistence(receiptURL: copiedReceiptURL)
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_200))
    let store = makeStore(persistence: copiedPersistence, clock: clock)

    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryTrial)
    let migrated = try XCTUnwrap(copiedPersistence.load())
    XCTAssertEqual(migrated.schemaVersion, 2)
    XCTAssertEqual(migrated.policyRevision, "ak47-lcd-qualified-upload-v2")
    XCTAssertEqual(migrated.target, legacy.target)
    XCTAssertEqual(migrated.canonicalTransferStartedAt, legacy.canonicalTransferStartedAt)
    XCTAssertEqual(migrated.canonicalTransferCompletedAt, legacy.canonicalTransferCompletedAt)
    XCTAssertEqual(migrated.canonicalVisualAttestedAt, legacy.canonicalVisualAttestedAt)
    XCTAssertEqual(
      migrated.usbModeCablePowerCycleAttestedAt,
      legacy.usbModeCablePowerCycleAttestedAt
    )
    XCTAssertEqual(try Data(contentsOf: productionURL), originalData)
  }

  func testLegacyMigrationRejectsAnythingExceptExactCleanInactiveV1Qualified() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_300))
    let seedPersistence = AK47LCDQualificationMemoryPersistence()
    _ = try maximumBoundaryReadyStore(persistence: seedPersistence, clock: clock)
    var legacy = try XCTUnwrap(seedPersistence.load())
    legacy.schemaVersion = 1
    legacy.policyRevision = AK47LCDExtendedUploadQualificationStateStore.legacyPolicyRevision
    legacy.phase = .qualified

    var activeLease = legacy
    activeLease.activeLeaseIdentifier = UUID()
    var pendingVisual = legacy
    pendingVisual.pendingVisualContainerSHA256 = String(repeating: "0", count: 64)
    var boundaryEvidence = legacy
    boundaryEvidence.maximumBoundaryFrameCount = 140
    var wrongPhase = legacy
    wrongPhase.phase = .extendedTransferInProgress
    var wrongPolicy = legacy
    wrongPolicy.policyRevision = "ak47-lcd-qualified-upload-v0"
    var wrongSchema = legacy
    wrongSchema.schemaVersion = 0

    for malformed in [
      activeLease,
      pendingVisual,
      boundaryEvidence,
      wrongPhase,
      wrongPolicy,
      wrongSchema,
    ] {
      XCTAssertNil(
        AK47LCDExtendedUploadQualificationStateStore.migratedLegacyV1Record(malformed)
      )
      let persistence = AK47LCDQualificationMemoryPersistence(record: malformed)
      XCTAssertEqual(
        makeStore(persistence: persistence, clock: clock).snapshot.state,
        .persistenceUnavailable
      )
      XCTAssertEqual(try persistence.load(), malformed)
    }
  }

  func testMaximumBoundaryTrialRequiresExactPlanAndAllOrderedDurableEvidence() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_400))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = try maximumBoundaryReadyStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let digest = AK47LCDUploadDigest.sha256Hex(plan.container.data)
    let fingerprint = AK47LCDUploadPlanFingerprint.hex(plan)

    XCTAssertThrowsError(
      try store.claimQualifiedLease(plan: plan, planFingerprintSHA256: fingerprint)
    ) {
      XCTAssertEqual($0 as? AK47LCDExtendedUploadQualificationError, .unavailable)
    }
    let canonical = try fixturePlan()
    XCTAssertThrowsError(
      try store.claimCanonicalTransfer(
        plan: canonical,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(canonical)
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDExtendedUploadQualificationError, .transitionNotAllowed)
    }
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.makeMaximumBoundaryTrialPlanSummary(
        qualifiedPlan(frameCount: 139)
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .maximumBoundaryTrialPlanRequired)
    }

    let summary = try AK47LCDUploadAdapter.makeMaximumBoundaryTrialPlanSummary(plan)
    XCTAssertEqual(summary.frameCount, 140)
    XCTAssertEqual(summary.pageCount, 2_215)
    XCTAssertEqual(summary.containerByteCount, 9_072_640)
    XCTAssertEqual(summary.transferEndAddressExclusive, 0xFE_7000)

    let lease = try store.claimMaximumBoundaryTransfer(
      plan: plan,
      planFingerprintSHA256: fingerprint
    )
    XCTAssertEqual(store.snapshot.state, .maximumBoundaryTransferInProgress)
    XCTAssertTrue(store.requiresDeviceOperationQuarantine)
    let restartedDuringTransfer = makeStore(persistence: persistence, clock: clock)
    XCTAssertEqual(restartedDuringTransfer.snapshot.state, .maximumBoundaryTransferInProgress)
    XCTAssertFalse(
      restartedDuringTransfer.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )
    XCTAssertTrue(
      store.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )
    XCTAssertFalse(
      store.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )

    clock.advance()
    try store.finishMaximumBoundaryTransfer(lease, outcome: .succeeded)
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryVisualAttestation)
    XCTAssertEqual(store.snapshot.pendingContainerSHA256, digest)
    XCTAssertEqual(store.snapshot.pendingFrameCount, 140)
    XCTAssertEqual(store.snapshot.pendingPageCount, 2_215)

    XCTAssertThrowsError(
      try store.recordMaximumBoundaryVisualAttestation(
        for: plan.target,
        attestation: .init(
          explicitlyConfirmingContainerSHA256: digest,
          at: clock.value.addingTimeInterval(-1)
        )
      )
    )
    clock.advance()
    try store.recordMaximumBoundaryVisualAttestation(
      for: plan.target,
      attestation: .init(
        explicitlyConfirmingContainerSHA256: digest,
        at: clock.value
      )
    )
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryObservedUSBDisconnection)

    store.observeSuccessfulHardwareEnumeration(exactTopology(locationID: 0x9999))
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryObservedUSBDisconnection)
    clock.advance()
    store.observeSuccessfulHardwareEnumeration([])
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryExactSamePortReappearance)
    store.observeSuccessfulHardwareEnumeration(
      Array(exactTopology(locationID: plan.target.locationID).dropLast())
    )
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryExactSamePortReappearance)
    clock.advance()
    store.observeSuccessfulHardwareEnumeration(
      exactTopology(locationID: plan.target.locationID)
    )
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryUSBPowerCycleAttestation)

    XCTAssertThrowsError(
      try store.acknowledgeMaximumBoundaryUSBModeCablePowerCycle(
        for: plan.target,
        attestation: .init(
          explicitlyConfirmingUSBModeCableRemovalAt: clock.value.addingTimeInterval(-1)
        )
      )
    )
    clock.advance()
    try store.acknowledgeMaximumBoundaryUSBModeCablePowerCycle(
      for: plan.target,
      attestation: .init(explicitlyConfirmingUSBModeCableRemovalAt: clock.value)
    )
    XCTAssertEqual(store.snapshot.state, .qualified(maximumFrameCount: 140))
    XCTAssertEqual(
      makeStore(persistence: persistence, clock: clock).snapshot.state,
      .qualified(maximumFrameCount: 140)
    )

    let qualified = try XCTUnwrap(persistence.load())
    XCTAssertEqual(qualified.schemaVersion, 2)
    XCTAssertEqual(qualified.policyRevision, "ak47-lcd-qualified-upload-v2")
    XCTAssertEqual(qualified.maximumBoundaryPlanFingerprintSHA256, fingerprint)
    XCTAssertEqual(qualified.maximumBoundaryContainerSHA256, digest)
    XCTAssertEqual(qualified.maximumBoundaryFrameCount, 140)
    XCTAssertEqual(qualified.maximumBoundaryPageCount, 2_215)
    XCTAssertEqual(qualified.maximumBoundaryContainerByteCount, 9_072_640)
    XCTAssertEqual(qualified.maximumBoundaryPartitionBudgetByteCount, 9_072_640)
    XCTAssertEqual(qualified.maximumBoundaryTransferEndAddressExclusive, 0xFE_7000)
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(qualified.maximumBoundaryHostCompletedAt),
      try XCTUnwrap(qualified.maximumBoundaryVisualAttestedAt)
    )
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(qualified.maximumBoundaryVisualAttestedAt),
      try XCTUnwrap(qualified.maximumBoundaryUSBDisconnectionAbsenceObservedAt)
    )
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(qualified.maximumBoundaryUSBDisconnectionAbsenceObservedAt),
      try XCTUnwrap(qualified.maximumBoundaryExactSamePortReappearanceObservedAt)
    )
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(qualified.maximumBoundaryExactSamePortReappearanceObservedAt),
      try XCTUnwrap(qualified.maximumBoundaryUSBModeCablePowerCycleAttestedAt)
    )
    XCTAssertEqual(qualified.lastSuccessfulContainerSHA256, digest)
    XCTAssertTrue(AK47LCDExtendedUploadQualificationStateStore.isValid(qualified))
  }

  func testQualifiedEncoderAndSummaryUseExactOneHundredFortyFrameBoundary() throws {
    let boundaries: [(frames: Int, pages: Int, bytes: Int, end: UInt64)] = [
      (1, 16, 65_536, 0x75_0000),
      (2, 32, 131_072, 0x76_0000),
      (3, 48, 196_608, 0x77_0000),
      (39, 618, 2_531_328, 0x9A_A000),
      (40, 633, 2_592_768, 0x9B_9000),
      (139, 2_200, 9_011_200, 0xFD_8000),
      (140, 2_215, 9_072_640, 0xFE_7000),
    ]
    for boundary in boundaries {
      let summary = try AK47LCDUploadAdapter.makeQualifiedPlanSummary(
        qualifiedPlan(frameCount: boundary.frames)
      )
      XCTAssertEqual(summary.frameCount, boundary.frames)
      XCTAssertEqual(summary.pageCount, boundary.pages)
      XCTAssertEqual(summary.expectedInputAcknowledgementCount, boundary.pages)
      XCTAssertEqual(summary.containerByteCount, boundary.bytes)
      XCTAssertEqual(summary.transferEndAddressExclusive, boundary.end)
    }

    let maximum = try qualifiedPlan(frameCount: 140)
    let summary = try AK47LCDUploadAdapter.makeQualifiedPlanSummary(maximum)
    XCTAssertEqual(summary.frameCount, 140)
    XCTAssertEqual(summary.pageCount, 2_215)
    XCTAssertEqual(summary.containerByteCount, 9_072_640)
    XCTAssertEqual(summary.transferStartAddress, 0x74_0000)
    XCTAssertEqual(summary.transferEndAddressExclusive, 0xFE_7000)
    XCTAssertEqual(summary.containerSHA256.count, 64)

    let selector = AK47LCDUploadStateMachine.selectorPayload(pageCount: 2_215)
    XCTAssertEqual(selector[0...2], [0x04, 0x72, 0x01])
    XCTAssertEqual(selector[8], 0xA7)
    XCTAssertEqual(selector[9], 0x08)
    XCTAssertEqual(maximum.container.unpaddedByteCount, 9_072_256)
    XCTAssertEqual(maximum.container.data[0], 0x8C)
    XCTAssertEqual(
      Array(maximum.container.data[1...140]),
      [UInt8](repeating: 0x32, count: 140)
    )
    XCTAssertTrue(maximum.container.data[141..<256].allSatisfy { $0 == 0xFF })
    XCTAssertTrue(maximum.container.data.suffix(384).allSatisfy { $0 == 0xFF })
  }

  func testQualifiedValidationRejectsOutOfRangeFramesInflatedPageAndLargeBudget() throws {
    let maximum = try qualifiedPlan(frameCount: 140)
    let frameCount141 = AK47LCDEncodedContainer(
      data: maximum.container.data,
      frameCount: 141,
      sourceDelaysMilliseconds: maximum.container.sourceDelaysMilliseconds + [100],
      encodedDeviceDelays: maximum.container.encodedDeviceDelays + [50],
      nominalEncodedDelaysMilliseconds: maximum.container.nominalEncodedDelaysMilliseconds + [100],
      effectiveDeviceDelaysMilliseconds:
        maximum.container.effectiveDeviceDelaysMilliseconds + [100],
      firmwareMinimumAppliedFrameIndices: maximum.container.firmwareMinimumAppliedFrameIndices,
      unpaddedByteCount: maximum.container.unpaddedByteCount,
      pageCount: maximum.container.pageCount,
      paddingByte: maximum.container.paddingByte,
      partitionBudgetByteCount: maximum.container.partitionBudgetByteCount
    )
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.validateQualifiedAnimation(
        AK47LCDUploadPlan(target: maximum.target, container: frameCount141)
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadAdapterError,
        .qualifiedFrameCountNotEnabled(141)
      )
    }

    let valid = try qualifiedPlan(frameCount: 2)
    var inflatedData = valid.container.data
    inflatedData.append(Data(repeating: 0xFF, count: AK47LCDFormat.transferPageByteCount))
    let inflated = AK47LCDEncodedContainer(
      data: inflatedData,
      frameCount: valid.container.frameCount,
      sourceDelaysMilliseconds: valid.container.sourceDelaysMilliseconds,
      encodedDeviceDelays: valid.container.encodedDeviceDelays,
      nominalEncodedDelaysMilliseconds: valid.container.nominalEncodedDelaysMilliseconds,
      effectiveDeviceDelaysMilliseconds: valid.container.effectiveDeviceDelaysMilliseconds,
      firmwareMinimumAppliedFrameIndices: valid.container.firmwareMinimumAppliedFrameIndices,
      unpaddedByteCount: valid.container.unpaddedByteCount,
      pageCount: valid.container.pageCount + 1,
      paddingByte: valid.container.paddingByte,
      partitionBudgetByteCount: valid.container.partitionBudgetByteCount
    )
    let inflatedPlan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: valid.target,
      container: inflated
    )
    XCTAssertThrowsError(try AK47LCDUploadAdapter.makeQualifiedPlanSummary(inflatedPlan)) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadAdapterError,
        .qualifiedPageCountMismatch(expected: valid.container.pageCount, actual: 33)
      )
    }

    let oversizedBudgetContainer = AK47LCDEncodedContainer(
      data: valid.container.data,
      frameCount: valid.container.frameCount,
      sourceDelaysMilliseconds: valid.container.sourceDelaysMilliseconds,
      encodedDeviceDelays: valid.container.encodedDeviceDelays,
      nominalEncodedDelaysMilliseconds: valid.container.nominalEncodedDelaysMilliseconds,
      effectiveDeviceDelaysMilliseconds: valid.container.effectiveDeviceDelaysMilliseconds,
      firmwareMinimumAppliedFrameIndices: valid.container.firmwareMinimumAppliedFrameIndices,
      unpaddedByteCount: valid.container.unpaddedByteCount,
      pageCount: valid.container.pageCount,
      paddingByte: valid.container.paddingByte,
      partitionBudgetByteCount:
        AK47LCDUploadAdapter.qualifiedMaximumContainerByteCount
        + AK47LCDFormat.transferPageByteCount
    )
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.validateQualifiedAnimation(
        AK47LCDUploadPlan(target: valid.target, container: oversizedBudgetContainer)
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadError, .partitionBudgetMismatch)
    }

    let wrappedDelayContainer = AK47LCDEncodedContainer(
      data: valid.container.data,
      frameCount: valid.container.frameCount,
      sourceDelaysMilliseconds: [512, 100],
      encodedDeviceDelays: valid.container.encodedDeviceDelays,
      nominalEncodedDelaysMilliseconds: valid.container.nominalEncodedDelaysMilliseconds,
      effectiveDeviceDelaysMilliseconds: valid.container.effectiveDeviceDelaysMilliseconds,
      firmwareMinimumAppliedFrameIndices: valid.container.firmwareMinimumAppliedFrameIndices,
      unpaddedByteCount: valid.container.unpaddedByteCount,
      pageCount: valid.container.pageCount,
      paddingByte: valid.container.paddingByte,
      partitionBudgetByteCount: valid.container.partitionBudgetByteCount
    )
    let wrappedDelayPlan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: valid.target,
      container: wrappedDelayContainer
    )
    XCTAssertThrowsError(try AK47LCDUploadAdapter.makeQualifiedPlanSummary(wrappedDelayPlan)) {
      XCTAssertEqual($0 as? AK47LCDUploadError, .delayMetadataMismatch)
    }
  }

  func testMaximumBoundaryAuthorizationIsExactAndOneUse() throws {
    let plan = try qualifiedPlan(frameCount: 140)
    let different = try qualifiedPlan(frameCount: 139)
    let authorization = AK47LCDMaximumBoundaryUploadAuthorization(
      explicitlyConfirming: plan
    )
    XCTAssertThrowsError(try authorization.consume(for: different)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .authorizationMismatch)
    }
    try authorization.consume(for: plan)
    XCTAssertThrowsError(try authorization.consume(for: plan)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .authorizationAlreadyConsumed)
    }
  }

  func testMaximumBoundaryAdapterTransfersExactlyTwoThousandTwoHundredFifteenPages()
    throws
  {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_600))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = try maximumBoundaryReadyStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let driver = QualificationMockDriver(mode: .success)
    var progress: [(Int, Int)] = []

    try AK47LCDUploadAdapter.performMaximumBoundaryTrial(
      plan: plan,
      authorization: AK47LCDMaximumBoundaryUploadAuthorization(
        explicitlyConfirming: plan
      ),
      qualification: store,
      driver: driver,
      gate: QualificationMockGate(),
      activityProvider: QualificationMockActivityProvider(),
      sleep: { _ in },
      progress: { progress.append(($0, $1)) }
    )

    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryVisualAttestation)
    XCTAssertEqual(driver.session?.featureCommands, [0x18, 0x72, 0x02])
    XCTAssertEqual(driver.session?.outputCount, 2_215)
    XCTAssertEqual(driver.session?.acknowledgementCount, 2_215)
    XCTAssertEqual(driver.session?.outputCountAtCommit, 2_215)
    XCTAssertEqual(progress.map(\.0), Array(1...2_215))
    XCTAssertEqual(progress.map(\.1), Array(repeating: 2_215, count: 2_215))
    let record = try XCTUnwrap(persistence.load())
    XCTAssertEqual(record.maximumBoundaryFrameCount, 140)
    XCTAssertEqual(record.maximumBoundaryPageCount, 2_215)
    XCTAssertEqual(record.maximumBoundaryContainerByteCount, 9_072_640)
    XCTAssertEqual(record.maximumBoundaryTransferEndAddressExclusive, 0xFE_7000)
  }

  func testMaximumBoundaryPreSubmissionFailureRestoresOneUseTrial() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_700))
    let store = try maximumBoundaryReadyStore(clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let driver = QualificationMockDriver(mode: .success)
    let gate = QualificationMockGate(forcedAcquireResult: .busy)

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performMaximumBoundaryTrial(
        plan: plan,
        authorization: AK47LCDMaximumBoundaryUploadAuthorization(
          explicitlyConfirming: plan
        ),
        qualification: store,
        driver: driver,
        gate: gate,
        activityProvider: QualificationMockActivityProvider(),
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .deviceBusy)
    }
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryTrial)
    XCTAssertEqual(driver.makeSessionCount, 0)
    XCTAssertEqual(gate.acquireCount, 1)
  }

  func testMaximumBoundarySubmittedFailuresInvalidateAndGloballyQuarantine() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_800))
    let plan = try qualifiedPlan(frameCount: 140)

    for failingPage in [0, 1_107, 2_214] {
      let quarantine = QualificationQuarantineRecorder()
      let store = try maximumBoundaryReadyStore(
        clock: clock,
        quarantineTarget: { try quarantine.quarantine($0) }
      )
      let driver = QualificationMockDriver(mode: .failOutput(failingPage))
      var progress: [(Int, Int)] = []
      XCTAssertThrowsError(
        try AK47LCDUploadAdapter.performMaximumBoundaryTrial(
          plan: plan,
          authorization: AK47LCDMaximumBoundaryUploadAuthorization(
            explicitlyConfirming: plan
          ),
          qualification: store,
          driver: driver,
          gate: QualificationMockGate(),
          activityProvider: QualificationMockActivityProvider(),
          sleep: { _ in },
          progress: { progress.append(($0, $1)) }
        )
      ) {
        guard case .partialTransactionQuarantined = $0 as? AK47LCDUploadAdapterError else {
          return XCTFail("unexpected error: \($0)")
        }
      }
      XCTAssertEqual(driver.session?.featureCommands, [0x18, 0x72])
      XCTAssertEqual(driver.session?.outputCount, failingPage)
      XCTAssertEqual(driver.session?.acknowledgementCount, failingPage)
      XCTAssertEqual(progress.count, failingPage)
      XCTAssertEqual(store.snapshot.state, .invalidatedRequiresFreshDiagnostic)
      XCTAssertEqual(
        quarantine.targets,
        [HIDDeviceQuarantineIdentity(target: plan.target)]
      )
    }
  }

  func testInterruptedMaximumBoundaryLeaseRequiresQuarantineReconciliation() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_900))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let original = try maximumBoundaryReadyStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let lease = try original.claimMaximumBoundaryTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    let quarantine = QualificationQuarantineRecorder()
    let restarted = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertEqual(restarted.snapshot.state, .maximumBoundaryTransferInProgress)

    try restarted.reconcileInterruptedTransfer(for: plan.target)
    XCTAssertEqual(restarted.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertEqual(quarantine.targets, [HIDDeviceQuarantineIdentity(target: plan.target)])
    XCTAssertThrowsError(
      try original.finishMaximumBoundaryTransfer(
        lease,
        outcome: .failedBeforeSubmissionWithConfirmedCleanup
      )
    )
  }

  func testMaximumBoundaryVisualMismatchIsDurableAndQuarantined() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_950))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let initial = try maximumBoundaryReadyStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let digest = AK47LCDUploadDigest.sha256Hex(plan.container.data)
    let lease = try initial.claimMaximumBoundaryTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    clock.advance()
    try initial.finishMaximumBoundaryTransfer(lease, outcome: .succeeded)

    let quarantine = QualificationQuarantineRecorder()
    quarantine.shouldFail = true
    let restarted = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertThrowsError(
      try restarted.reportMaximumBoundaryVisualMismatch(
        for: plan.target,
        containerSHA256: digest
      )
    )
    XCTAssertEqual(
      restarted.snapshot.state,
      .maximumBoundaryVisualMismatchQuarantinePending
    )
    XCTAssertEqual(
      makeStore(
        persistence: persistence,
        clock: clock,
        quarantineTarget: { try quarantine.quarantine($0) }
      ).snapshot.state,
      .maximumBoundaryVisualMismatchQuarantinePending
    )

    quarantine.shouldFail = false
    try restarted.reportMaximumBoundaryVisualMismatch(
      for: plan.target,
      containerSHA256: digest
    )
    XCTAssertEqual(restarted.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertEqual(quarantine.targets, [HIDDeviceQuarantineIdentity(target: plan.target)])
  }

  func testMissingReceiptRejectsBeforeGateActivityOrDriver() throws {
    let plan = try qualifiedPlan(frameCount: 2)
    let qualification = AK47LCDExtendedUploadQualificationStateStore(
      persistence: AK47LCDQualificationMemoryPersistence()
    )
    let driver = QualificationMockDriver(mode: .success)
    let gate = QualificationMockGate()
    let activity = QualificationMockActivityProvider()

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performQualified(
        plan: plan,
        authorization: AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan),
        qualification: qualification,
        driver: driver,
        gate: gate,
        activityProvider: activity,
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDExtendedUploadQualificationError, .unavailable)
    }
    XCTAssertEqual(driver.makeSessionCount, 0)
    XCTAssertEqual(gate.acquireCount, 0)
    XCTAssertEqual(activity.beginCount, 0)
  }

  func testQualifiedAuthorizationBindsExactImmutablePlanAndIsOneUse() throws {
    let plan = try qualifiedPlan(frameCount: 2)
    let different = try qualifiedPlan(frameCount: 3)
    let authorization = AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan)
    XCTAssertThrowsError(try authorization.consume(for: different)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .authorizationMismatch)
    }
    try authorization.consume(for: plan)
    XCTAssertThrowsError(try authorization.consume(for: plan)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .authorizationAlreadyConsumed)
    }
  }

  func testCanonicalDurableLeaseSaveFailureRejectsBeforeAnyTransportObject() throws {
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = AK47LCDExtendedUploadQualificationStateStore(
      persistence: persistence,
      quarantineTarget: { _ in }
    )
    persistence.failsSaves = true
    let plan = try fixturePlan()
    let driver = QualificationMockDriver(mode: .success)
    let gate = QualificationMockGate()
    let activity = QualificationMockActivityProvider()

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performCanonical(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        qualification: store,
        driver: driver,
        gate: gate,
        activityProvider: activity,
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDExtendedUploadQualificationError,
        .persistenceUnavailable
      )
    }
    XCTAssertEqual(driver.makeSessionCount, 0)
    XCTAssertEqual(gate.acquireCount, 0)
    XCTAssertEqual(activity.beginCount, 0)
    XCTAssertEqual(store.snapshot.state, .persistenceUnavailable)
  }

  func testQualifiedDurableLeaseSaveFailureRejectsBeforeAnyTransportObject() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_800))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = try qualifiedStore(persistence: persistence, clock: clock)
    persistence.failsSaves = true
    let plan = try qualifiedPlan(frameCount: 2)
    let driver = QualificationMockDriver(mode: .success)
    let gate = QualificationMockGate()
    let activity = QualificationMockActivityProvider()

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performQualified(
        plan: plan,
        authorization: AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan),
        qualification: store,
        driver: driver,
        gate: gate,
        activityProvider: activity,
        sleep: { _ in }
      )
    )
    XCTAssertEqual(driver.makeSessionCount, 0)
    XCTAssertEqual(gate.acquireCount, 0)
    XCTAssertEqual(activity.beginCount, 0)
    XCTAssertEqual(store.snapshot.state, .persistenceUnavailable)
  }

  func testQualificationFinalizeSaveFailureNeverCreatesPositiveAuthority() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_900))

    do {
      let persistence = AK47LCDQualificationMemoryPersistence()
      let store = try qualifiedStore(persistence: persistence, clock: clock)
      let plan = try qualifiedPlan(frameCount: 2)
      let lease = try store.claimQualifiedLease(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
      persistence.failsSaves = true
      XCTAssertThrowsError(try store.finishQualifiedLease(lease, outcome: .succeeded))
      persistence.failsSaves = false
      XCTAssertEqual(
        makeStore(persistence: persistence, clock: clock).snapshot.state,
        .extendedTransferInProgress
      )
    }

    do {
      let persistence = AK47LCDQualificationMemoryPersistence()
      let store = makeStore(persistence: persistence, clock: clock)
      let plan = try fixturePlan()
      let lease = try store.claimCanonicalTransfer(
        plan: plan,
        planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
      )
      persistence.failsSaves = true
      XCTAssertThrowsError(
        try store.finishCanonicalTransfer(lease, plan: plan, outcome: .succeeded)
      )
      persistence.failsSaves = false
      XCTAssertEqual(
        makeStore(persistence: persistence, clock: clock).snapshot.state,
        .canonicalTransferInProgress
      )
    }
  }

  func testPreSubmissionGateBusyInvalidatesCanonicalButRestoresQualifiedLease() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 7_950))
    let canonicalStore = makeStore(clock: clock)
    let canonicalPlan = try fixturePlan()
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performCanonical(
        plan: canonicalPlan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: canonicalPlan),
        qualification: canonicalStore,
        driver: QualificationMockDriver(mode: .success),
        gate: QualificationMockGate(forcedAcquireResult: .busy),
        activityProvider: QualificationMockActivityProvider(),
        sleep: { _ in }
      )
    )
    XCTAssertEqual(canonicalStore.snapshot.state, .invalidatedRequiresFreshDiagnostic)

    let qualifiedStore = try qualifiedStore(clock: clock)
    let qualifiedPlan = try qualifiedPlan(frameCount: 2)
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performQualified(
        plan: qualifiedPlan,
        authorization: AK47LCDQualifiedUploadAuthorization(
          explicitlyConfirming: qualifiedPlan
        ),
        qualification: qualifiedStore,
        driver: QualificationMockDriver(mode: .success),
        gate: QualificationMockGate(forcedAcquireResult: .busy),
        activityProvider: QualificationMockActivityProvider(),
        sleep: { _ in }
      )
    )
    XCTAssertEqual(qualifiedStore.snapshot.state, .qualified(maximumFrameCount: 140))
  }

  func testQualifiedAdapterSuccessUsesSharedPathAndSubmittedFailureRevokesLease() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 8_000))
    let successPersistence = AK47LCDQualificationMemoryPersistence()
    let successStore = try qualifiedStore(persistence: successPersistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let successDriver = QualificationMockDriver(mode: .success)
    var progress: [(Int, Int)] = []

    try AK47LCDUploadAdapter.performQualified(
      plan: plan,
      authorization: AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan),
      qualification: successStore,
      driver: successDriver,
      gate: QualificationMockGate(),
      activityProvider: QualificationMockActivityProvider(),
      sleep: { _ in },
      progress: { progress.append(($0, $1)) }
    )
    XCTAssertEqual(successStore.snapshot.state, .awaitingExtendedVisualAttestation)
    XCTAssertEqual(
      successStore.snapshot.pendingContainerSHA256,
      AK47LCDUploadDigest.sha256Hex(plan.container.data)
    )
    XCTAssertEqual(successDriver.session?.outputCount, plan.container.pageCount)
    XCTAssertEqual(successDriver.session?.acknowledgementCount, 2_215)
    XCTAssertEqual(successDriver.session?.outputCountAtCommit, 2_215)
    XCTAssertEqual(successDriver.session?.featureCommands, [0x18, 0x72, 0x02])
    XCTAssertEqual(progress.map(\.0), Array(1...2_215))
    XCTAssertEqual(progress.map(\.1), Array(repeating: 2_215, count: 2_215))
    let pendingReload = makeStore(persistence: successPersistence, clock: clock)
    XCTAssertEqual(pendingReload.snapshot.state, .awaitingExtendedVisualAttestation)
    try pendingReload.recordQualifiedUploadVisualAttestation(
      for: plan.target,
      attestation: .init(
        explicitlyConfirmingContainerSHA256: AK47LCDUploadDigest.sha256Hex(plan.container.data),
        at: clock.value
      )
    )
    XCTAssertEqual(pendingReload.snapshot.state, .qualified(maximumFrameCount: 140))

    let failedStore = try qualifiedStore(clock: clock)
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.performQualified(
        plan: plan,
        authorization: AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan),
        qualification: failedStore,
        driver: QualificationMockDriver(mode: .failOutput(0)),
        gate: QualificationMockGate(),
        activityProvider: QualificationMockActivityProvider(),
        sleep: { _ in }
      )
    ) {
      guard case .partialTransactionQuarantined = $0 as? AK47LCDUploadAdapterError else {
        return XCTFail("unexpected error: \($0)")
      }
    }
    XCTAssertEqual(failedStore.snapshot.state, .invalidatedRequiresFreshDiagnostic)
  }

  func testQualifiedMiddleAndLastPageFailureNeverRetryOrCommitAndInvalidate() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 8_500))
    let plan = try qualifiedPlan(frameCount: 140)
    for failingPage in [1_107, 2_214] {
      let store = try qualifiedStore(clock: clock)
      let driver = QualificationMockDriver(mode: .failOutput(failingPage))
      var progress: [(Int, Int)] = []
      XCTAssertThrowsError(
        try AK47LCDUploadAdapter.performQualified(
          plan: plan,
          authorization: AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan),
          qualification: store,
          driver: driver,
          gate: QualificationMockGate(),
          activityProvider: QualificationMockActivityProvider(),
          sleep: { _ in },
          progress: { progress.append(($0, $1)) }
        )
      )
      XCTAssertEqual(driver.session?.featureCommands, [0x18, 0x72])
      XCTAssertEqual(driver.session?.outputCount, failingPage)
      XCTAssertEqual(driver.session?.acknowledgementCount, failingPage)
      XCTAssertEqual(progress.count, failingPage)
      XCTAssertEqual(store.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    }
  }

  func testQualificationGateAdmissionIsExactProcessLocalAndOneUse() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 9_000))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = makeStore(persistence: persistence, clock: clock)
    let plan = try fixturePlan()
    let lease = try store.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )

    XCTAssertTrue(store.requiresDeviceOperationQuarantine)
    let wrongTarget = HIDDeviceQuarantineIdentity(
      vendorID: HIDEnumerator.vendorID,
      productID: HIDEnumerator.productID,
      product: "Archon AK47",
      locationID: 0x9999,
      versionNumber: 0x0115,
      serialNumber: nil
    )
    XCTAssertFalse(store.consumeGateAdmission(lease.gateAdmission, for: wrongTarget))
    let forgedAdmission = AK47LCDQualificationGateAdmission(
      kind: .canonical,
      leaseIdentifier: UUID(),
      target: HIDDeviceQuarantineIdentity(target: plan.target),
      planFingerprintSHA256: lease.planFingerprintSHA256
    )
    XCTAssertFalse(
      store.consumeGateAdmission(
        forgedAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )
    XCTAssertTrue(
      store.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )
    XCTAssertFalse(
      store.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )

    let restarted = makeStore(persistence: persistence, clock: clock)
    XCTAssertTrue(restarted.requiresDeviceOperationQuarantine)
    XCTAssertFalse(
      restarted.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )
  }

  func testLeaseFinalizationFailureRevokesLocalGateAdmission() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 9_100))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = makeStore(persistence: persistence, clock: clock)
    let plan = try fixturePlan()
    let lease = try store.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    persistence.failsSaves = true
    XCTAssertThrowsError(
      try store.finishCanonicalTransfer(
        lease,
        plan: plan,
        outcome: .failedBeforeSubmissionWithConfirmedCleanup
      )
    )
    persistence.failsSaves = false
    XCTAssertFalse(
      store.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )
  }

  func testInterruptedCanonicalLeasePersistsPendingBeforeMarkerAndInvalidatesOldLease() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 9_200))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let original = makeStore(persistence: persistence, clock: clock)
    let plan = try fixturePlan()
    let lease = try original.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )

    let quarantine = QualificationQuarantineRecorder()
    quarantine.shouldFail = true
    let restarted = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertThrowsError(try restarted.reconcileInterruptedTransfer(for: plan.target))
    XCTAssertEqual(restarted.snapshot.state, .interruptedTransferQuarantinePending)
    XCTAssertTrue(restarted.requiresDeviceOperationQuarantine)
    XCTAssertThrowsError(
      try original.finishCanonicalTransfer(
        lease,
        plan: plan,
        outcome: .failedBeforeSubmissionWithConfirmedCleanup
      )
    )
    XCTAssertFalse(
      original.consumeGateAdmission(
        lease.gateAdmission,
        for: HIDDeviceQuarantineIdentity(target: plan.target)
      )
    )

    quarantine.shouldFail = false
    let pendingReload = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertEqual(pendingReload.snapshot.state, .interruptedTransferQuarantinePending)
    try pendingReload.reconcileInterruptedTransfer(for: plan.target)
    XCTAssertEqual(pendingReload.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertEqual(quarantine.targets, [HIDDeviceQuarantineIdentity(target: plan.target)])
  }

  func testInterruptedExtendedLeaseMarkerThenFinalizeFailureRetriesAfterRelaunch() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 9_300))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let original = try qualifiedStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 3)
    let lease = try original.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    let quarantine = QualificationQuarantineRecorder()
    quarantine.afterSuccessfulQuarantine = { persistence.failsSaves = true }
    let restarted = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertThrowsError(try restarted.reconcileInterruptedTransfer(for: plan.target))
    XCTAssertEqual(quarantine.targets.count, 1)
    XCTAssertThrowsError(
      try original.finishQualifiedLease(
        lease,
        outcome: .failedBeforeSubmissionWithConfirmedCleanup
      )
    )

    persistence.failsSaves = false
    quarantine.afterSuccessfulQuarantine = nil
    let pendingReload = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: { try quarantine.quarantine($0) }
    )
    XCTAssertEqual(pendingReload.snapshot.state, .interruptedTransferQuarantinePending)
    try pendingReload.reconcileInterruptedTransfer(for: plan.target)
    XCTAssertEqual(pendingReload.snapshot.state, .invalidatedRequiresFreshDiagnostic)
    XCTAssertEqual(quarantine.targets.count, 2)
  }

  func testPendingVisualCannotPredatePreviousSuccessfulVisualAttestation() throws {
    let clock = QualificationTestClock(Date(timeIntervalSinceReferenceDate: 9_400))
    let persistence = AK47LCDQualificationMemoryPersistence()
    let store = try qualifiedStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 2)
    var lease = try store.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    try store.finishQualifiedLease(lease, outcome: .succeeded)
    try store.recordQualifiedUploadVisualAttestation(
      for: plan.target,
      attestation: .init(
        explicitlyConfirmingContainerSHA256: AK47LCDUploadDigest.sha256Hex(plan.container.data),
        at: clock.value
      )
    )
    clock.advance()
    lease = try store.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    try store.finishQualifiedLease(lease, outcome: .succeeded)

    var record = try XCTUnwrap(persistence.load())
    record.pendingVisualHostCompletedAt = try XCTUnwrap(record.lastSuccessfulTransferAt)
      .addingTimeInterval(-1)
    try persistence.save(record)
    XCTAssertEqual(
      makeStore(persistence: persistence, clock: clock).snapshot.state,
      .persistenceUnavailable
    )
  }

  private func makeStore(
    persistence: any AK47LCDQualificationPersisting = AK47LCDQualificationMemoryPersistence(),
    clock: QualificationTestClock,
    quarantineTarget: @escaping @Sendable (HIDDeviceQuarantineIdentity) throws -> Void = { _ in }
  ) -> AK47LCDExtendedUploadQualificationStateStore {
    AK47LCDExtendedUploadQualificationStateStore(
      persistence: persistence,
      now: { clock.value },
      quarantineTarget: quarantineTarget
    )
  }

  private func recordCanonicalSuccess(
    store: AK47LCDExtendedUploadQualificationStateStore,
    plan: AK47LCDUploadPlan
  ) throws {
    let lease = try store.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    try store.finishCanonicalTransfer(lease, plan: plan, outcome: .succeeded)
  }

  private func qualifiedStore(
    persistence: AK47LCDQualificationMemoryPersistence = .init(),
    clock: QualificationTestClock
  ) throws -> AK47LCDExtendedUploadQualificationStateStore {
    let store = try maximumBoundaryReadyStore(persistence: persistence, clock: clock)
    let plan = try qualifiedPlan(frameCount: 140)
    let lease = try store.claimMaximumBoundaryTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    clock.advance()
    try store.finishMaximumBoundaryTransfer(lease, outcome: .succeeded)
    clock.advance()
    try store.recordMaximumBoundaryVisualAttestation(
      for: plan.target,
      attestation: .init(
        explicitlyConfirmingContainerSHA256: AK47LCDUploadDigest.sha256Hex(plan.container.data),
        at: clock.value
      )
    )
    clock.advance()
    store.observeSuccessfulHardwareEnumeration([])
    clock.advance()
    store.observeSuccessfulHardwareEnumeration(exactTopology(locationID: plan.target.locationID))
    clock.advance()
    try store.acknowledgeMaximumBoundaryUSBModeCablePowerCycle(
      for: plan.target,
      attestation: .init(explicitlyConfirmingUSBModeCableRemovalAt: clock.value)
    )
    return store
  }

  private func maximumBoundaryReadyStore(
    persistence: AK47LCDQualificationMemoryPersistence = .init(),
    clock: QualificationTestClock,
    quarantineTarget: @escaping @Sendable (HIDDeviceQuarantineIdentity) throws -> Void = { _ in }
  ) throws -> AK47LCDExtendedUploadQualificationStateStore {
    let store = makeStore(
      persistence: persistence,
      clock: clock,
      quarantineTarget: quarantineTarget
    )
    let plan = try fixturePlan()
    try recordCanonicalSuccess(store: store, plan: plan)
    clock.advance()
    try store.recordCanonicalFixtureVisualAttestation(
      for: plan.target,
      attestation: .init(explicitlyConfirmingCanonicalCornersAt: clock.value)
    )
    clock.advance()
    store.observeSuccessfulHardwareEnumeration([])
    clock.advance()
    store.observeSuccessfulHardwareEnumeration(exactTopology(locationID: plan.target.locationID))
    clock.advance()
    try store.acknowledgeUSBModeCablePowerCycle(
      for: plan.target,
      attestation: .init(explicitlyConfirmingUSBModeCableRemovalAt: clock.value)
    )
    XCTAssertEqual(store.snapshot.state, .awaitingMaximumBoundaryTrial)
    return store
  }

  private func fixturePlan() throws -> AK47LCDUploadPlan {
    try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: AK47LCDDiagnosticFixture.encode()
    )
  }

  private func qualifiedPlan(frameCount: Int) throws -> AK47LCDUploadPlan {
    try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: AK47LCDUploadAdapter.encodeQualifiedAnimation(project(frameCount: frameCount))
    )
  }

  private func project(frameCount: Int) throws -> AK47LCDAnimationProject {
    let image = try AK47LCDRGBAImage(
      width: AK47LCDFormat.canvasWidth,
      height: AK47LCDFormat.canvasHeight,
      color: .black
    )
    let delay = try AK47LCDSourceDelay(milliseconds: 100)
    return try AK47LCDAnimationProject(
      frames: (0..<frameCount).map { _ in
        try AK47LCDAnimationFrame(image: image, sourceDelay: delay)
      }
    )
  }

  private var target: AK47WiredDeviceTarget {
    AK47WiredDeviceTarget(locationID: 0x1234, versionNumber: 0x0115)
  }

  private func exactTopology(locationID: UInt64) -> [HIDCollectionRecord] {
    [
      record(locationID: locationID, page: 0x0001, usage: 0x0006, 8, 1, 0),
      record(locationID: locationID, page: 0x000C, usage: 0x0001, 16, 1, 1),
      record(locationID: locationID, page: 0xFF13, usage: 0x0001, 64, 64, 64),
      record(locationID: locationID, page: 0xFF68, usage: 0x0061, 64, 4_096, 0),
    ]
  }

  private func record(
    locationID: UInt64,
    page: UInt64,
    usage: UInt64,
    _ input: UInt64,
    _ output: UInt64,
    _ feature: UInt64
  ) -> HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: HIDEnumerator.vendorID,
      productID: HIDEnumerator.productID,
      product: "Archon AK47",
      manufacturer: "Test",
      transport: "USB",
      versionNumber: 0x0115,
      locationID: locationID,
      usagePage: page,
      usage: usage,
      maxInputReportSize: input,
      maxOutputReportSize: output,
      maxFeatureReportSize: feature
    )
  }
}

private final class QualificationTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) { self.date = date }

  var value: Date {
    lock.lock()
    defer { lock.unlock() }
    return date
  }

  func advance() {
    lock.lock()
    date = date.addingTimeInterval(1)
    lock.unlock()
  }
}

private final class QualificationQuarantineRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedTargets: [HIDDeviceQuarantineIdentity] = []
  private var fails = false
  var afterSuccessfulQuarantine: (() -> Void)?

  var shouldFail: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return fails
    }
    set {
      lock.lock()
      fails = newValue
      lock.unlock()
    }
  }

  var targets: [HIDDeviceQuarantineIdentity] {
    lock.lock()
    defer { lock.unlock() }
    return storedTargets
  }

  func quarantine(_ target: HIDDeviceQuarantineIdentity) throws {
    lock.lock()
    guard !fails else {
      lock.unlock()
      throw AK47LCDQualificationPersistenceError.unavailable
    }
    storedTargets.append(target)
    let callback = afterSuccessfulQuarantine
    lock.unlock()
    callback?()
  }
}

private final class QualificationMockGate: AK47LCDUploadOperationGating {
  private let state = HIDDeviceOperationGateState(
    persistence: HIDDeviceQuarantineMemoryPersistence()
  )
  private(set) var acquireCount = 0
  private let forcedAcquireResult: HIDDeviceOperationGateAcquireResult?

  init(forcedAcquireResult: HIDDeviceOperationGateAcquireResult? = nil) {
    self.forcedAcquireResult = forcedAcquireResult
  }

  func acquire(target: HIDDeviceQuarantineIdentity) -> HIDDeviceOperationGateAcquireResult {
    acquireCount += 1
    if let forcedAcquireResult { return forcedAcquireResult }
    return state.acquire(target: target)
  }

  func acquire(
    target: HIDDeviceQuarantineIdentity,
    qualificationAdmission _: AK47LCDQualificationGateAdmission?
  ) -> HIDDeviceOperationGateAcquireResult {
    acquire(target: target)
  }

  func makeEvidence() -> HIDDeviceTransactionEvidence { state.makeTransactionEvidence() }

  func finish(succeeded: Bool, evidence: HIDDeviceTransactionEvidence) throws {
    try state.finish(succeeded: succeeded, evidence: evidence)
  }
}

private final class QualificationMockActivity: AK47LCDUploadActivityHolding {
  func end() {}
}

private final class QualificationMockActivityProvider: AK47LCDUploadActivityProviding {
  private(set) var beginCount = 0

  func begin() -> any AK47LCDUploadActivityHolding {
    beginCount += 1
    return QualificationMockActivity()
  }
}

private final class QualificationMockDriver: AK47LCDUploadSystemDriving {
  enum Mode {
    case success
    case failOutput(Int)
  }

  let mode: Mode
  private(set) var makeSessionCount = 0
  private(set) var session: QualificationMockSession?

  init(mode: Mode) { self.mode = mode }

  func makeSession(
    target _: AK47WiredDeviceTarget,
    evidence: HIDDeviceTransactionEvidence
  ) throws -> any AK47LCDUploadLifecycleSession {
    makeSessionCount += 1
    let session = QualificationMockSession(mode: mode, evidence: evidence)
    self.session = session
    return session
  }

  func verifyPostflight(target _: AK47WiredDeviceTarget) throws {}
}

private final class QualificationMockSession: AK47LCDUploadLifecycleSession {
  private let mode: QualificationMockDriver.Mode
  private let evidence: HIDDeviceTransactionEvidence
  private var lastFeature = [UInt8](repeating: 0, count: 64)
  private(set) var featureCommands: [UInt8] = []
  private(set) var outputCount = 0
  private(set) var acknowledgementCount = 0
  private(set) var outputCountAtCommit: Int?

  init(mode: QualificationMockDriver.Mode, evidence: HIDDeviceTransactionEvidence) {
    self.mode = mode
    self.evidence = evidence
  }

  func setFeature(_ bytes: [UInt8], stage _: AK47LCDUploadStage) throws {
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()
    lastFeature = bytes
    featureCommands.append(bytes[1])
    if bytes[1] == 0x02 { outputCountAtCommit = outputCount }
  }

  func getFeature(expectedLength: Int, stage _: AK47LCDUploadStage) throws -> [UInt8] {
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()
    var acknowledgement = [UInt8](repeating: 0, count: expectedLength)
    acknowledgement[0] = lastFeature[0]
    acknowledgement[1] = lastFeature[1]
    acknowledgement[2] = lastFeature[2]
    acknowledgement[3] = 1
    if lastFeature[1] == 0x72 {
      acknowledgement[8] = lastFeature[8]
      acknowledgement[9] = lastFeature[9]
    }
    return acknowledgement
  }

  func setOutput(
    _ bytes: [UInt8],
    reportID _: UInt8,
    stage: AK47LCDUploadStage
  ) throws {
    try evidence.prepareForSubmission()
    evidence.recordSubmittedReport()
    if case .failOutput(let failingIndex) = mode, outputCount == failingIndex {
      throw AK47LCDUploadAdapterError.shortWrite(
        stage: stage,
        expected: bytes.count,
        actual: 0
      )
    }
    outputCount += 1
  }

  func getInputAcknowledgement(
    stage _: AK47LCDUploadStage
  ) throws -> AK47LCDInputAcknowledgement {
    acknowledgementCount += 1
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0...2] = [0x01, 0x5A, 0x02]
    return AK47LCDInputAcknowledgement(reportID: 0, bytes: bytes)
  }

  func cancel() throws {}
}
