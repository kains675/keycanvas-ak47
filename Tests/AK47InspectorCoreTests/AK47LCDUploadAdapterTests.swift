import Foundation
import IOKit.hid
import XCTest

@testable import AK47InspectorCore

final class AK47LCDUploadAdapterTests: XCTestCase {
  func testSuccessfulSetCallbackZeroLengthIsNotTreatedAsShortWrite() {
    XCTAssertNoThrow(
      try AK47LCDAsyncReportCompletionValidator.validate(
        stage: .begin,
        completedType: kIOHIDReportTypeFeature,
        completedReportID: 0,
        completedLength: 0,
        expectedType: kIOHIDReportTypeFeature,
        expectedLength: 64,
        direction: .set
      )
    )
    XCTAssertNoThrow(
      try AK47LCDAsyncReportCompletionValidator.validate(
        stage: .page(0),
        completedType: kIOHIDReportTypeOutput,
        completedReportID: 0,
        completedLength: 0,
        expectedType: kIOHIDReportTypeOutput,
        expectedLength: 4_096,
        direction: .set
      )
    )
  }

  func testGetCallbackStillRequiresExactReturnedLength() {
    XCTAssertThrowsError(
      try AK47LCDAsyncReportCompletionValidator.validate(
        stage: .begin,
        completedType: kIOHIDReportTypeFeature,
        completedReportID: 0,
        completedLength: 0,
        expectedType: kIOHIDReportTypeFeature,
        expectedLength: 64,
        direction: .get
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadError,
        .invalidReportLength(stage: .begin, expected: 64, actual: 0)
      )
    }
  }

  func testSetCallbackStillRequiresExpectedReportTypeAndID() {
    XCTAssertThrowsError(
      try AK47LCDAsyncReportCompletionValidator.validate(
        stage: .begin,
        completedType: kIOHIDReportTypeOutput,
        completedReportID: 0,
        completedLength: 0,
        expectedType: kIOHIDReportTypeFeature,
        expectedLength: 64,
        direction: .set
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedCompletion(stage: .begin))
    }
    XCTAssertThrowsError(
      try AK47LCDAsyncReportCompletionValidator.validate(
        stage: .begin,
        completedType: kIOHIDReportTypeFeature,
        completedReportID: 1,
        completedLength: 0,
        expectedType: kIOHIDReportTypeFeature,
        expectedLength: 64,
        direction: .set
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedCompletion(stage: .begin))
    }
  }

  func testSuccessUsesExactOrderSixteenPrearmedAcknowledgementsAndNoF0() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = MockLCDGate(persistence: persistence)
    let driver = MockLCDDriver(mode: .success)
    let activity = MockLCDActivityProvider()
    var sleeps: [UInt32] = []
    var progress: [(Int, Int)] = []

    try AK47LCDUploadAdapter.perform(
      plan: plan,
      authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
      driver: driver,
      gate: gate,
      activityProvider: activity,
      sleep: { sleeps.append($0) },
      progress: { progress.append(($0, $1)) }
    )

    let session = try XCTUnwrap(driver.session)
    XCTAssertEqual(session.cancelCount, 1)
    XCTAssertEqual(driver.postflightCount, 1)
    XCTAssertEqual(activity.beginCount, 1)
    XCTAssertEqual(activity.endCount, 1)
    XCTAssertFalse(gate.state.isQuarantined)
    XCTAssertTrue(persistence.identities.isEmpty)
    XCTAssertEqual(progress.map(\.0), Array(1...16))
    XCTAssertEqual(progress.map(\.1), Array(repeating: 16, count: 16))

    let commands = session.operations.compactMap(\.featureCommand)
    XCTAssertEqual(commands, [0x18, 0x72, 0x02])
    XCTAssertFalse(commands.contains(0xF0))
    XCTAssertEqual(session.operations.filter(\.isOutput).count, 16)
    XCTAssertEqual(session.operations.filter(\.isAcknowledgement).count, 16)
    for page in 0..<16 {
      let prearm = try XCTUnwrap(session.operations.firstIndex(of: .prearm(page)))
      let output = try XCTUnwrap(session.operations.firstIndex(of: .output(page, 4_096, 0)))
      let acknowledgement = try XCTUnwrap(session.operations.firstIndex(of: .acknowledgement(page)))
      XCTAssertLessThan(prearm, output)
      XCTAssertLessThan(output, acknowledgement)
    }
    XCTAssertEqual(sleeps.filter { $0 == 35 }.count, 7)
    XCTAssertEqual(sleeps.last, 50)
  }

  func testAuthorizationIsBoundToExactPlanAndConsumedOnce() throws {
    let plan = try fixturePlan()
    let authorization = AK47LCDUploadAuthorization(explicitlyConfirming: plan)
    let differentPlan = try fixturePlan(locationID: 0x5678)
    let unusedDriver = MockLCDDriver(mode: .success)
    let unusedGate = MockLCDGate()
    let unusedActivity = MockLCDActivityProvider()

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: differentPlan,
        authorization: authorization,
        driver: unusedDriver,
        gate: unusedGate,
        activityProvider: unusedActivity,
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .authorizationMismatch)
    }
    XCTAssertEqual(unusedDriver.makeSessionCount, 0)
    XCTAssertEqual(unusedActivity.beginCount, 0)

    try AK47LCDUploadAdapter.perform(
      plan: plan,
      authorization: authorization,
      driver: unusedDriver,
      gate: unusedGate,
      activityProvider: unusedActivity,
      sleep: { _ in }
    )
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: authorization,
        driver: MockLCDDriver(mode: .success),
        gate: MockLCDGate(),
        activityProvider: MockLCDActivityProvider(),
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .authorizationAlreadyConsumed)
    }
  }

  func testOnlyGoldenFixtureCanReachDriver() throws {
    let good = try fixturePlan()
    var changedData = good.container.data
    changedData[256 + (120 * 2)] ^= 0x01
    let changedContainer = replacingData(good.container, with: changedData)
    let changed = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: good.target,
      container: changedContainer
    )
    let driver = MockLCDDriver(mode: .success)
    let activity = MockLCDActivityProvider()

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: changed,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: changed),
        driver: driver,
        gate: MockLCDGate(),
        activityProvider: activity,
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .fixtureNotAllowlisted)
    }
    XCTAssertEqual(driver.makeSessionCount, 0)
    XCTAssertEqual(activity.beginCount, 0)
  }

  func testAdapterRejectsNonSingleFrameBeforeOpeningSession() throws {
    let image = try AK47LCDDiagnosticFixture.makeImage()
    let delay = try AK47LCDSourceDelay(milliseconds: 100)
    let project = try AK47LCDAnimationProject(
      frames: [
        try AK47LCDAnimationFrame(image: image, sourceDelay: delay),
        try AK47LCDAnimationFrame(image: image, sourceDelay: delay),
      ]
    )
    let container = try AK47LCDContainerEncoder.encode(project: project)
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(target: target, container: container)
    let driver = MockLCDDriver(mode: .success)

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        driver: driver,
        gate: MockLCDGate(),
        activityProvider: MockLCDActivityProvider(),
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .liveFrameCountNotEnabled(2))
    }
    XCTAssertEqual(driver.makeSessionCount, 0)
  }

  func testShortOutputFailsFastWithoutRetryOrCommitAndPersistsQuarantine() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = MockLCDGate(persistence: persistence)
    let driver = MockLCDDriver(mode: .shortOutput(page: 0, actual: 4_095))
    let activity = MockLCDActivityProvider()

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        driver: driver,
        gate: gate,
        activityProvider: activity,
        sleep: { _ in }
      )
    ) {
      guard case .partialTransactionQuarantined = $0 as? AK47LCDUploadAdapterError else {
        return XCTFail("unexpected error: \($0)")
      }
    }

    let session = try XCTUnwrap(driver.session)
    XCTAssertEqual(session.operations.filter(\.isOutput).count, 1)
    XCTAssertFalse(session.operations.compactMap(\.featureCommand).contains(0x02))
    XCTAssertEqual(session.cancelCount, 1)
    XCTAssertEqual(driver.postflightCount, 0)
    XCTAssertTrue(gate.state.isQuarantined)
    XCTAssertEqual(persistence.identities.count, 1)
    XCTAssertEqual(activity.endCount, 1)
  }

  func testAcknowledgementTimeoutFailsFastAndPersistsQuarantine() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = MockLCDGate(persistence: persistence)
    let driver = MockLCDDriver(mode: .acknowledgementTimeout(page: 1))

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        driver: driver,
        gate: gate,
        activityProvider: MockLCDActivityProvider(),
        sleep: { _ in }
      )
    ) {
      guard case .partialTransactionQuarantined = $0 as? AK47LCDUploadAdapterError else {
        return XCTFail("unexpected error: \($0)")
      }
    }
    let session = try XCTUnwrap(driver.session)
    XCTAssertEqual(session.operations.filter(\.isOutput).count, 2)
    XCTAssertFalse(session.operations.compactMap(\.featureCommand).contains(0x02))
    XCTAssertTrue(gate.state.isQuarantined)
  }

  func testPreSubmissionFailureCanClearMarkerOnlyAfterCancelAndPostflight() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = MockLCDGate(persistence: persistence)
    let driver = MockLCDDriver(mode: .rejectFirstSubmission)

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        driver: driver,
        gate: gate,
        activityProvider: MockLCDActivityProvider(),
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadAdapterError,
        .operationFailed(stage: .begin, code: 0xE000_02BC)
      )
    }
    XCTAssertEqual(driver.session?.cancelCount, 1)
    XCTAssertEqual(driver.postflightCount, 1)
    XCTAssertFalse(gate.state.isQuarantined)
    XCTAssertTrue(persistence.identities.isEmpty)
  }

  func testUnconfirmedCancellationKeepsQuarantine() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = MockLCDGate(persistence: persistence)
    let driver = MockLCDDriver(mode: .rejectFirstSubmission, cancellationFails: true)

    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        driver: driver,
        gate: gate,
        activityProvider: MockLCDActivityProvider(),
        sleep: { _ in }
      )
    ) {
      guard case .partialTransactionQuarantined = $0 as? AK47LCDUploadAdapterError else {
        return XCTFail("unexpected error: \($0)")
      }
    }
    XCTAssertTrue(gate.state.isQuarantined)
    XCTAssertEqual(persistence.identities.count, 1)
  }

  func testLifecycleHazardBeforeCommitBlocksCommitAndMarkerCleanup() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = MockLCDGate(persistence: persistence)
    let driver = MockLCDDriver(mode: .lifecycleHazardAfterAcknowledgement(page: 15))

    XCTAssertFalse(AK47LCDUploadLifecycleInterlock.isTransferActive)
    XCTAssertThrowsError(
      try AK47LCDUploadAdapter.perform(
        plan: plan,
        authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
        driver: driver,
        gate: gate,
        activityProvider: MockLCDActivityProvider(),
        sleep: { _ in }
      )
    ) {
      guard case .partialTransactionQuarantined = $0 as? AK47LCDUploadAdapterError else {
        return XCTFail("unexpected error: \($0)")
      }
    }
    XCTAssertFalse(AK47LCDUploadLifecycleInterlock.isTransferActive)
    XCTAssertFalse(driver.session?.operations.compactMap(\.featureCommand).contains(0x02) ?? true)
    XCTAssertTrue(gate.state.isQuarantined)
    XCTAssertEqual(persistence.identities.count, 1)
  }

  func testTopologyRequiresExactSameIdentityAndUniqueFF13FF68() throws {
    let records = exactTopologyRecords()
    let proofs = exactAncestryProofs()
    let selection = try AK47LCDSystemTopology.select(
      records: records,
      ancestryProofs: proofs,
      target: target
    )
    XCTAssertEqual(records[selection.featureIndex].usagePage, 0xFF13)
    XCTAssertEqual(records[selection.outputIndex].usagePage, 0xFF68)

    var wrongRevision = records
    wrongRevision[3] = record(
      usagePage: 0xFF68,
      usage: 0x0061,
      input: 64,
      output: 4_096,
      feature: 0,
      version: 0x0114
    )
    XCTAssertThrowsError(
      try AK47LCDSystemTopology.select(
        records: wrongRevision,
        ancestryProofs: proofs,
        target: target
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedTopology(collections: 3))
    }

    var differentSerial = records
    differentSerial[3] = record(
      usagePage: 0xFF68,
      usage: 0x0061,
      input: 64,
      output: 4_096,
      feature: 0,
      serial: "different"
    )
    XCTAssertThrowsError(
      try AK47LCDSystemTopology.select(
        records: differentSerial,
        ancestryProofs: proofs,
        target: target
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedTopology(collections: 4))
    }
  }

  func testTopologyRejectsMissingIdentityAndWrongInterfaceOrPhysicalParent() throws {
    var missingVendor = exactTopologyRecords()
    let ff68 = missingVendor[3]
    missingVendor[3] = HIDCollectionRecord(
      vendorID: 0,
      productID: ff68.productID,
      product: ff68.product,
      manufacturer: ff68.manufacturer,
      serialNumber: ff68.serialNumber,
      transport: ff68.transport,
      versionNumber: ff68.versionNumber,
      locationID: ff68.locationID,
      usagePage: ff68.usagePage,
      usage: ff68.usage,
      maxInputReportSize: ff68.maxInputReportSize,
      maxOutputReportSize: ff68.maxOutputReportSize,
      maxFeatureReportSize: ff68.maxFeatureReportSize
    )
    XCTAssertThrowsError(
      try AK47LCDSystemTopology.select(
        records: missingVendor,
        ancestryProofs: exactAncestryProofs(),
        target: target
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedTopology(collections: 3))
    }

    var wrongInterface = exactAncestryProofs()
    wrongInterface[3] = AK47LCDUSBAncestryProof(
      interfaceNumber: 3,
      physicalParentRegistryID: 0xAABB,
      vendorID: HIDEnumerator.vendorID,
      productID: HIDEnumerator.productID,
      locationID: target.locationID
    )
    XCTAssertThrowsError(
      try AK47LCDSystemTopology.select(
        records: exactTopologyRecords(),
        ancestryProofs: wrongInterface,
        target: target
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .usbAncestryMismatch)
    }

    var wrongParent = exactAncestryProofs()
    wrongParent[3] = AK47LCDUSBAncestryProof(
      interfaceNumber: 2,
      physicalParentRegistryID: 0xCCDD,
      vendorID: HIDEnumerator.vendorID,
      productID: HIDEnumerator.productID,
      locationID: target.locationID
    )
    XCTAssertThrowsError(
      try AK47LCDSystemTopology.select(
        records: exactTopologyRecords(),
        ancestryProofs: wrongParent,
        target: target
      )
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .usbAncestryMismatch)
    }
  }

  func testPersistentInputDispatcherAcceptsOnlyCurrentSubmittedGeneration() throws {
    let dispatcher = AK47LCDInputReportDispatcher()
    let first = try dispatcher.prepareForOutput()
    try dispatcher.markSubmitted(generation: first)
    var accepted = acceptedPageBytes(fill: 0x33)
    deliver(&accepted, to: dispatcher)

    let acknowledgement = try dispatcher.wait(generation: first, timeoutMilliseconds: 10)
    XCTAssertEqual(acknowledgement.reportID, 0)
    XCTAssertEqual(acknowledgement.bytes.count, 64)
    XCTAssertEqual(acknowledgement.bytes[3], 0x33)

    let second = try dispatcher.prepareForOutput()
    try dispatcher.markSubmitted(generation: second)
    XCTAssertThrowsError(try dispatcher.wait(generation: first, timeoutMilliseconds: 1)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .inputCallbackGenerationMismatch)
    }
    var secondBytes = acceptedPageBytes(fill: 0x55)
    deliver(&secondBytes, to: dispatcher)
    XCTAssertEqual(
      try dispatcher.wait(generation: second, timeoutMilliseconds: 10).bytes[3],
      0x55
    )
  }

  func testInputDispatcherLatchesUnsolicitedEarlyAndDuplicateInputAsFatal() throws {
    let unsolicitedDispatcher = AK47LCDInputReportDispatcher()
    var unsolicited = acceptedPageBytes(fill: 0x11)
    deliver(&unsolicited, to: unsolicitedDispatcher)
    XCTAssertThrowsError(try unsolicitedDispatcher.prepareForOutput()) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedInputAcknowledgement)
    }

    let earlyDispatcher = AK47LCDInputReportDispatcher()
    let earlyGeneration = try earlyDispatcher.prepareForOutput()
    var early = acceptedPageBytes(fill: 0x22)
    deliver(&early, to: earlyDispatcher)
    XCTAssertThrowsError(try earlyDispatcher.markSubmitted(generation: earlyGeneration)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedInputAcknowledgement)
    }

    let duplicateDispatcher = AK47LCDInputReportDispatcher()
    let duplicateGeneration = try duplicateDispatcher.prepareForOutput()
    try duplicateDispatcher.markSubmitted(generation: duplicateGeneration)
    var first = acceptedPageBytes(fill: 0x33)
    deliver(&first, to: duplicateDispatcher)
    var duplicate = acceptedPageBytes(fill: 0x44)
    deliver(&duplicate, to: duplicateDispatcher)
    XCTAssertThrowsError(
      try duplicateDispatcher.wait(generation: duplicateGeneration, timeoutMilliseconds: 10)
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedInputAcknowledgement)
    }
  }

  func testInputDispatcherRejectsAnyNonzeroReportIDWithoutTruncation() throws {
    let dispatcher = AK47LCDInputReportDispatcher()
    let generation = try dispatcher.prepareForOutput()
    try dispatcher.markSubmitted(generation: generation)
    var bytes = acceptedPageBytes(fill: 0)
    deliver(&bytes, to: dispatcher, reportID: 0x100)
    XCTAssertThrowsError(try dispatcher.wait(generation: generation, timeoutMilliseconds: 10)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .inputReportIDMismatch(0x100))
    }
  }

  func testInputDispatcherPreservesShortLengthForStateMachineValidation() throws {
    let dispatcher = AK47LCDInputReportDispatcher()
    let generation = try dispatcher.prepareForOutput()
    try dispatcher.markSubmitted(generation: generation)
    var short = [UInt8](repeating: 0, count: 63)
    deliver(&short, to: dispatcher)
    let acknowledgement = try dispatcher.wait(generation: generation, timeoutMilliseconds: 10)
    XCTAssertEqual(acknowledgement.reportID, 0)
    XCTAssertEqual(acknowledgement.bytes.count, 63)
  }

  func testInputDispatcherTimeoutIsBoundedAndDoesNotAcceptLateGeneration() throws {
    let dispatcher = AK47LCDInputReportDispatcher()
    let generation = try dispatcher.prepareForOutput()
    try dispatcher.markSubmitted(generation: generation)
    XCTAssertThrowsError(try dispatcher.wait(generation: generation, timeoutMilliseconds: 1)) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .operationTimedOut(stage: .page(0)))
    }
    var late = acceptedPageBytes(fill: 0x66)
    deliver(&late, to: dispatcher)
    XCTAssertThrowsError(try dispatcher.prepareForOutput()) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedInputAcknowledgement)
    }
  }

  func testSubmissionBarrierDrainsQueuedDuplicateBeforeNextPageOrCommit() throws {
    let dispatcher = AK47LCDInputReportDispatcher()
    let queue = DispatchQueue(label: "test.ak47.lcd.callback-barrier")
    let generation = try dispatcher.prepareForOutput()
    try dispatcher.markSubmitted(generation: generation)
    var first = acceptedPageBytes(fill: 0x33)
    deliver(&first, to: dispatcher)
    _ = try dispatcher.wait(generation: generation, timeoutMilliseconds: 10)

    queue.async {
      var duplicate = self.acceptedPageBytes(fill: 0x44)
      self.deliver(&duplicate, to: dispatcher)
    }
    var subsequentSubmissionCount = 0
    XCTAssertThrowsError(
      try AK47LCDCallbackSubmissionBarrier.sync(queue: queue, dispatcher: dispatcher) {
        subsequentSubmissionCount += 1
      }
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadAdapterError, .unexpectedInputAcknowledgement)
    }
    XCTAssertEqual(subsequentSubmissionCount, 0)
  }

  func testLifecycleSuccessClaimIsAtomicAgainstConcurrentHazard() throws {
    let plan = try fixturePlan()
    let persistence = HIDDeviceQuarantineMemoryPersistence()
    let gate = BlockingSuccessfulFinishLCDGate(persistence: persistence)
    let transferResult = LockedTestBox<Result<Void, Error>?>(nil)
    let hazardResult = LockedTestBox<Bool?>(nil)
    let transferFinished = expectation(description: "transfer finished")
    let hazardStarted = DispatchSemaphore(value: 0)
    let hazardFinished = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try AK47LCDUploadAdapter.perform(
          plan: plan,
          authorization: AK47LCDUploadAuthorization(explicitlyConfirming: plan),
          driver: MockLCDDriver(mode: .success),
          gate: gate,
          activityProvider: MockLCDActivityProvider(),
          sleep: { _ in }
        )
        transferResult.value = .success(())
      } catch {
        transferResult.value = .failure(error)
      }
      transferFinished.fulfill()
    }

    XCTAssertEqual(
      gate.enteredSuccessfulFinish.wait(timeout: .now() + .seconds(1)),
      .success
    )
    DispatchQueue.global(qos: .userInitiated).async {
      hazardStarted.signal()
      hazardResult.value = AK47LCDUploadLifecycleInterlock.recordLifecycleHazard()
      hazardFinished.signal()
    }
    XCTAssertEqual(hazardStarted.wait(timeout: .now() + .seconds(1)), .success)
    // The hazard call must wait while success cleanup owns the lifecycle claim.
    XCTAssertEqual(
      hazardFinished.wait(timeout: .now() + .milliseconds(20)),
      .timedOut
    )
    gate.allowSuccessfulFinish.signal()
    wait(for: [transferFinished], timeout: 1)
    XCTAssertEqual(hazardFinished.wait(timeout: .now() + .seconds(1)), .success)

    if case .failure(let error) = transferResult.value {
      XCTFail("unexpected transfer error: \(error)")
    }
    XCTAssertEqual(hazardResult.value, false)
    XCTAssertFalse(gate.state.isQuarantined)
    XCTAssertTrue(persistence.identities.isEmpty)
    XCTAssertFalse(AK47LCDUploadLifecycleInterlock.isTransferActive)
  }

  private var target: AK47WiredDeviceTarget {
    AK47WiredDeviceTarget(locationID: 0x1234, versionNumber: 0x0115)
  }

  private func fixturePlan(locationID: UInt64 = 0x1234) throws -> AK47LCDUploadPlan {
    try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: AK47WiredDeviceTarget(locationID: locationID, versionNumber: 0x0115),
      container: AK47LCDDiagnosticFixture.encode()
    )
  }

  private func replacingData(
    _ container: AK47LCDEncodedContainer,
    with data: Data
  ) -> AK47LCDEncodedContainer {
    AK47LCDEncodedContainer(
      data: data,
      frameCount: container.frameCount,
      sourceDelaysMilliseconds: container.sourceDelaysMilliseconds,
      encodedDeviceDelays: container.encodedDeviceDelays,
      nominalEncodedDelaysMilliseconds: container.nominalEncodedDelaysMilliseconds,
      effectiveDeviceDelaysMilliseconds: container.effectiveDeviceDelaysMilliseconds,
      firmwareMinimumAppliedFrameIndices: container.firmwareMinimumAppliedFrameIndices,
      unpaddedByteCount: container.unpaddedByteCount,
      pageCount: container.pageCount,
      paddingByte: container.paddingByte,
      partitionBudgetByteCount: container.partitionBudgetByteCount
    )
  }

  private func acceptedPageBytes(fill: UInt8) -> [UInt8] {
    var bytes = [UInt8](repeating: fill, count: 64)
    bytes.replaceSubrange(0..<3, with: [0x01, 0x5A, 0x02])
    return bytes
  }

  private func deliver(
    _ bytes: inout [UInt8],
    to dispatcher: AK47LCDInputReportDispatcher,
    reportID: UInt32 = 0
  ) {
    bytes.withUnsafeMutableBufferPointer { buffer in
      dispatcher.receive(
        result: kIOReturnSuccess,
        reportType: kIOHIDReportTypeInput,
        reportID: reportID,
        report: buffer.baseAddress!,
        reportLength: buffer.count
      )
    }
  }

  private func exactTopologyRecords() -> [HIDCollectionRecord] {
    [
      record(usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
      record(usagePage: 0x000C, usage: 0x0001, input: 16, output: 1, feature: 1),
      record(usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64, feature: 64),
      record(usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096, feature: 0),
    ]
  }

  private func exactAncestryProofs() -> [AK47LCDUSBAncestryProof] {
    [0, 1, 3, 2].map { interfaceNumber in
      AK47LCDUSBAncestryProof(
        interfaceNumber: UInt64(interfaceNumber),
        physicalParentRegistryID: 0xAABB,
        vendorID: HIDEnumerator.vendorID,
        productID: HIDEnumerator.productID,
        locationID: target.locationID
      )
    }
  }

  private func record(
    usagePage: UInt64,
    usage: UInt64,
    input: UInt64,
    output: UInt64,
    feature: UInt64,
    version: UInt64 = 0x0115,
    serial: String? = nil
  ) -> HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: HIDEnumerator.vendorID,
      productID: HIDEnumerator.productID,
      product: "Archon AK47",
      manufacturer: "Synthetic",
      serialNumber: serial,
      transport: "USB",
      versionNumber: version,
      locationID: 0x1234,
      usagePage: usagePage,
      usage: usage,
      maxInputReportSize: input,
      maxOutputReportSize: output,
      maxFeatureReportSize: feature
    )
  }
}

private final class MockLCDGate: AK47LCDUploadOperationGating {
  let state: HIDDeviceOperationGateState

  init(persistence: HIDDeviceQuarantineMemoryPersistence = .init()) {
    state = HIDDeviceOperationGateState(persistence: persistence)
  }

  func acquire(target: HIDDeviceQuarantineIdentity) -> HIDDeviceOperationGateAcquireResult {
    state.acquire(target: target)
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

private final class BlockingSuccessfulFinishLCDGate: AK47LCDUploadOperationGating {
  let state: HIDDeviceOperationGateState
  let enteredSuccessfulFinish = DispatchSemaphore(value: 0)
  let allowSuccessfulFinish = DispatchSemaphore(value: 0)

  init(persistence: HIDDeviceQuarantineMemoryPersistence) {
    state = HIDDeviceOperationGateState(persistence: persistence)
  }

  func acquire(target: HIDDeviceQuarantineIdentity) -> HIDDeviceOperationGateAcquireResult {
    state.acquire(target: target)
  }

  func acquire(
    target: HIDDeviceQuarantineIdentity,
    qualificationAdmission _: AK47LCDQualificationGateAdmission?
  ) -> HIDDeviceOperationGateAcquireResult {
    acquire(target: target)
  }

  func makeEvidence() -> HIDDeviceTransactionEvidence { state.makeTransactionEvidence() }

  func finish(succeeded: Bool, evidence: HIDDeviceTransactionEvidence) throws {
    if succeeded {
      enteredSuccessfulFinish.signal()
      guard allowSuccessfulFinish.wait(timeout: .now() + .seconds(1)) == .success else {
        throw AK47LCDUploadAdapterError.operationTimedOut(stage: .commit)
      }
    }
    try state.finish(succeeded: succeeded, evidence: evidence)
  }
}

private final class LockedTestBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) { storage = value }

  var value: Value {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }
    set {
      lock.lock()
      storage = newValue
      lock.unlock()
    }
  }
}

private final class MockLCDActivity: AK47LCDUploadActivityHolding {
  private let onEnd: () -> Void
  private var ended = false

  init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

  func end() {
    guard !ended else { return }
    ended = true
    onEnd()
  }
}

private final class MockLCDActivityProvider: AK47LCDUploadActivityProviding {
  private(set) var beginCount = 0
  private(set) var endCount = 0

  func begin() -> any AK47LCDUploadActivityHolding {
    beginCount += 1
    return MockLCDActivity { [weak self] in self?.endCount += 1 }
  }
}

private final class MockLCDDriver: AK47LCDUploadSystemDriving {
  enum Mode {
    case success
    case shortOutput(page: Int, actual: Int)
    case acknowledgementTimeout(page: Int)
    case rejectFirstSubmission
    case lifecycleHazardAfterAcknowledgement(page: Int)
  }

  let mode: Mode
  let cancellationFails: Bool
  private(set) var makeSessionCount = 0
  private(set) var postflightCount = 0
  private(set) var session: MockLCDLifecycleSession?

  init(mode: Mode, cancellationFails: Bool = false) {
    self.mode = mode
    self.cancellationFails = cancellationFails
  }

  func makeSession(
    target _: AK47WiredDeviceTarget,
    evidence: HIDDeviceTransactionEvidence
  ) throws -> any AK47LCDUploadLifecycleSession {
    makeSessionCount += 1
    let session = MockLCDLifecycleSession(
      mode: mode,
      cancellationFails: cancellationFails,
      evidence: evidence
    )
    self.session = session
    return session
  }

  func verifyPostflight(target _: AK47WiredDeviceTarget) throws {
    postflightCount += 1
  }
}

private final class MockLCDLifecycleSession: AK47LCDUploadLifecycleSession {
  enum Operation: Equatable {
    case setFeature([UInt8])
    case getFeature(UInt8)
    case prearm(Int)
    case output(Int, Int, UInt8)
    case acknowledgement(Int)
    case cancel

    var featureCommand: UInt8? {
      guard case .setFeature(let bytes) = self, bytes.count >= 2, bytes[0] == 0x04 else {
        return nil
      }
      return bytes[1]
    }

    var isOutput: Bool {
      guard case .output = self else { return false }
      return true
    }

    var isAcknowledgement: Bool {
      guard case .acknowledgement = self else { return false }
      return true
    }
  }

  let mode: MockLCDDriver.Mode
  let cancellationFails: Bool
  let evidence: HIDDeviceTransactionEvidence
  private(set) var operations: [Operation] = []
  private(set) var cancelCount = 0
  private var lastFeature: [UInt8]?
  private var currentPage = 0

  init(
    mode: MockLCDDriver.Mode,
    cancellationFails: Bool,
    evidence: HIDDeviceTransactionEvidence
  ) {
    self.mode = mode
    self.cancellationFails = cancellationFails
    self.evidence = evidence
  }

  func cancel() throws {
    cancelCount += 1
    operations.append(.cancel)
    if cancellationFails { throw AK47LCDUploadAdapterError.sessionCancellationTimedOut }
  }

  func setFeature(_ bytes: [UInt8], stage: AK47LCDUploadStage) throws {
    try prepare()
    operations.append(.setFeature(bytes))
    lastFeature = bytes
    if case .rejectFirstSubmission = mode, stage == .begin {
      throw AK47LCDUploadAdapterError.operationFailed(stage: stage, code: 0xE000_02BC)
    }
    evidence.recordSubmittedReport()
  }

  func getFeature(expectedLength _: Int, stage _: AK47LCDUploadStage) throws -> [UInt8] {
    try prepare()
    evidence.recordSubmittedReport()
    var acknowledgement = lastFeature ?? [UInt8](repeating: 0, count: 64)
    acknowledgement[3] = 1
    operations.append(.getFeature(acknowledgement[1]))
    return acknowledgement
  }

  func setOutput(
    _ bytes: [UInt8],
    reportID: UInt8,
    stage: AK47LCDUploadStage
  ) throws {
    let page = currentPage
    operations.append(.prearm(page))
    try prepare()
    operations.append(.output(page, bytes.count, reportID))
    evidence.recordSubmittedReport()
    if case .shortOutput(let failedPage, let actual) = mode, failedPage == page {
      throw AK47LCDUploadAdapterError.shortWrite(
        stage: stage,
        expected: bytes.count,
        actual: actual
      )
    }
  }

  func getInputAcknowledgement(stage: AK47LCDUploadStage) throws
    -> AK47LCDInputAcknowledgement
  {
    let page = currentPage
    operations.append(.acknowledgement(page))
    currentPage += 1
    if case .acknowledgementTimeout(let failedPage) = mode, failedPage == page {
      throw AK47LCDUploadAdapterError.operationTimedOut(stage: stage)
    }
    if case .lifecycleHazardAfterAcknowledgement(let hazardPage) = mode, hazardPage == page {
      XCTAssertTrue(AK47LCDUploadLifecycleInterlock.recordLifecycleHazard())
    }
    var bytes = [UInt8](repeating: 0xA5, count: 64)
    bytes.replaceSubrange(0..<3, with: [0x01, 0x5A, 0x02])
    return AK47LCDInputAcknowledgement(reportID: 0, bytes: bytes)
  }

  private func prepare() throws {
    try AK47LCDUploadLifecycleInterlock.check()
    do { try evidence.prepareForSubmission() } catch {
      throw AK47LCDUploadAdapterError.quarantinePersistenceFailed
    }
  }
}
