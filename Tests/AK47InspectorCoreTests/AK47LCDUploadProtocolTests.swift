import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47LCDUploadProtocolTests: XCTestCase {
  func testPreflightAcceptsExactSingleFrameContainer() throws {
    let container = makeContainer()
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: container
    )

    XCTAssertEqual(plan.container.pageCount, 16)
    XCTAssertEqual(
      AK47LCDUploadPreflight.externalFlashStartAddress
        + UInt64(plan.container.data.count),
      0x75_0000
    )
  }

  func testStateMachineUsesVerifiedCommandsPagesAndAcknowledgementsWithoutF0() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: makeContainer()
    )
    let session = MockLCDUploadSession(
      featureAcknowledgements: acceptedFeatureSequence(pageCount: 16),
      pageAcknowledgements: Array(repeating: acceptedPage(), count: 16)
    )
    var sleeps: [UInt32] = []
    var progress: [(Int, Int)] = []

    try AK47LCDUploadStateMachine.execute(
      plan: plan,
      session: session,
      sleep: { sleeps.append($0) },
      progress: { progress.append(($0, $1)) }
    )

    XCTAssertEqual(session.operations.count, 6 + (16 * 2))
    XCTAssertEqual(session.operations[0], .setFeature(AK47LCDUploadStateMachine.beginPayload))
    XCTAssertEqual(session.operations[1], .getFeature(64))

    let selector = try XCTUnwrap(session.operations[2].featurePayload)
    XCTAssertEqual(Array(selector.prefix(3)), [0x04, 0x72, 0x01])
    XCTAssertEqual(selector[8], 0x10)
    XCTAssertEqual(selector[9], 0x00)
    XCTAssertEqual(session.operations[3], .getFeature(64))

    for page in 0..<16 {
      XCTAssertEqual(session.operations[4 + (page * 2)], .setOutput(reportID: 0, byteCount: 4096))
      XCTAssertEqual(session.operations[5 + (page * 2)], .getInput)
    }
    XCTAssertEqual(
      session.operations[36],
      .setFeature(AK47LCDUploadStateMachine.commitPayload)
    )
    XCTAssertEqual(session.operations[37], .getFeature(64))
    XCTAssertFalse(
      session.operations.compactMap(\.featurePayload).contains { payload in
        payload.prefix(2).elementsEqual([0x04, 0xF0])
      }
    )
    XCTAssertEqual(sleeps, Array(repeating: 35, count: 7))
    XCTAssertEqual(progress.map(\.0), Array(1...16))
    XCTAssertEqual(progress.map(\.1), Array(repeating: 16, count: 16))
  }

  func testRejectedPageAcknowledgementFailsFastWithoutRetryOrCommit() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target, container: makeContainer())
    var rejectedBytes = acceptedPage().bytes
    rejectedBytes[2] = 0
    let rejected = AK47LCDInputAcknowledgement(reportID: 0, bytes: rejectedBytes)
    let session = MockLCDUploadSession(
      featureAcknowledgements: Array(acceptedFeatureSequence(pageCount: 16).prefix(2)),
      pageAcknowledgements: [acceptedPage(), rejected]
    )

    XCTAssertThrowsError(
      try AK47LCDUploadStateMachine.execute(plan: plan, session: session, sleep: { _ in })
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadError,
        .acknowledgementRejected(stage: .page(1))
      )
    }
    XCTAssertEqual(
      session.operations.filter { $0.isOutput },
      [
        .setOutput(reportID: 0, byteCount: 4096),
        .setOutput(reportID: 0, byteCount: 4096),
      ]
    )
    XCTAssertFalse(
      session.operations.compactMap(\.featurePayload).contains {
        $0.prefix(2).elementsEqual([0x04, 0x02])
      }
    )
  }

  func testFeatureAcknowledgementsRequireCapturedKnownFieldEchoes() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: makeContainer()
    )
    var wrongBegin = acceptedFeature(for: AK47LCDUploadStateMachine.beginPayload)
    wrongBegin[1] = 0x19
    var wrongBeginByte2 = acceptedFeature(for: AK47LCDUploadStateMachine.beginPayload)
    wrongBeginByte2[2] = 1
    var wrongSelector = acceptedFeature(
      for: AK47LCDUploadStateMachine.selectorPayload(pageCount: 16)
    )
    wrongSelector[8] = 0x11

    for (acknowledgements, expectedStage) in [
      ([wrongBegin], AK47LCDUploadStage.begin),
      ([wrongBeginByte2], AK47LCDUploadStage.begin),
      (
        [
          acceptedFeature(for: AK47LCDUploadStateMachine.beginPayload),
          wrongSelector,
        ],
        AK47LCDUploadStage.selectUpload
      ),
    ] {
      let session = MockLCDUploadSession(
        featureAcknowledgements: acknowledgements,
        pageAcknowledgements: []
      )
      XCTAssertThrowsError(
        try AK47LCDUploadStateMachine.execute(plan: plan, session: session, sleep: { _ in })
      ) {
        XCTAssertEqual(
          $0 as? AK47LCDUploadError,
          .acknowledgementRejected(stage: expectedStage)
        )
      }
      XCTAssertTrue(session.operations.filter(\.isOutput).isEmpty)
    }
  }

  func testCommitAcknowledgementRejectsNonzeroDefinedLCDChecksum() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: makeContainer()
    )
    var nonzeroChecksum = acceptedFeature(for: AK47LCDUploadStateMachine.commitPayload)
    nonzeroChecksum[6] = 1
    let session = MockLCDUploadSession(
      featureAcknowledgements: [
        acceptedFeature(for: AK47LCDUploadStateMachine.beginPayload),
        acceptedFeature(for: AK47LCDUploadStateMachine.selectorPayload(pageCount: 16)),
        nonzeroChecksum,
      ],
      pageAcknowledgements: Array(repeating: acceptedPage(), count: 16)
    )

    XCTAssertThrowsError(
      try AK47LCDUploadStateMachine.execute(plan: plan, session: session, sleep: { _ in })
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadError,
        .acknowledgementRejected(stage: .commit)
      )
    }
    XCTAssertEqual(session.operations.filter(\.isOutput).count, 16)
  }

  func testPageAcknowledgementRequiresReportIDLengthAndExactPrefix() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target, container: makeContainer())
    let invalidValues: [(AK47LCDInputAcknowledgement, AK47LCDUploadError)] = [
      (
        AK47LCDInputAcknowledgement(reportID: 1, bytes: acceptedPage().bytes),
        .outputReportIDMismatch(stage: .page(0), actual: 1)
      ),
      (
        AK47LCDInputAcknowledgement(reportID: 0, bytes: [0x01, 0x5A, 0x02]),
        .invalidReportLength(stage: .page(0), expected: 64, actual: 3)
      ),
      (
        AK47LCDInputAcknowledgement(
          reportID: 0, bytes: [0x01, 0x5A, 0x03] + .init(repeating: 0, count: 61)),
        .acknowledgementRejected(stage: .page(0))
      ),
    ]

    for (acknowledgement, expectedError) in invalidValues {
      let session = MockLCDUploadSession(
        featureAcknowledgements: Array(acceptedFeatureSequence(pageCount: 16).prefix(2)),
        pageAcknowledgements: [acknowledgement]
      )
      XCTAssertThrowsError(
        try AK47LCDUploadStateMachine.execute(plan: plan, session: session, sleep: { _ in })
      ) {
        XCTAssertEqual($0 as? AK47LCDUploadError, expectedError)
      }
      XCTAssertEqual(session.operations.filter { $0.isOutput }.count, 1)
    }
  }

  func testRejectedLastPageNeverRetriesOrCommitsAndReportsOnlyAcceptedPages() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target, container: makeContainer())
    var rejectedBytes = acceptedPage().bytes
    rejectedBytes[0] = 0
    let acknowledgements =
      Array(repeating: acceptedPage(), count: 15) + [
        AK47LCDInputAcknowledgement(reportID: 0, bytes: rejectedBytes)
      ]
    let session = MockLCDUploadSession(
      featureAcknowledgements: Array(acceptedFeatureSequence(pageCount: 16).prefix(2)),
      pageAcknowledgements: acknowledgements
    )
    var completed: [Int] = []

    XCTAssertThrowsError(
      try AK47LCDUploadStateMachine.execute(
        plan: plan,
        session: session,
        sleep: { _ in },
        progress: { page, _ in completed.append(page) }
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadError,
        .acknowledgementRejected(stage: .page(15))
      )
    }
    XCTAssertEqual(session.operations.filter(\.isOutput).count, 16)
    XCTAssertEqual(completed, Array(1...15))
    XCTAssertFalse(
      session.operations.compactMap(\.featurePayload).contains {
        $0.prefix(2).elementsEqual([0x04, 0x02])
      }
    )
  }

  func testPreflightRejectsMutatedHeaderAndTailPadding() {
    var badHeader = makeContainer().data
    badHeader[2] = 0
    XCTAssertThrowsError(
      try AK47LCDUploadPreflight.makeSyntheticPlan(
        target: target,
        container: makeContainer(data: badHeader)
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadError,
        .headerPaddingMismatch(offset: 2)
      )
    }

    var badTail = makeContainer().data
    badTail[65_056] = 0
    XCTAssertThrowsError(
      try AK47LCDUploadPreflight.makeSyntheticPlan(
        target: target,
        container: makeContainer(data: badTail)
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47LCDUploadError,
        .pagePaddingMismatch(offset: 65_056)
      )
    }
  }

  func testPreflightRejectsExperimentalZeroPagePadding() {
    let container = makeContainer(paddingByte: 0)
    XCTAssertThrowsError(
      try AK47LCDUploadPreflight.makeSyntheticPlan(target: target, container: container)
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadError, .unsupportedPagePadding(0))
    }
  }

  func testPreflightRejectsPageCountAboveExclusiveEndCeiling() {
    let pageCount = AK47LCDUploadPreflight.maximumPageCount + 1
    let data = Data(repeating: 0xFF, count: pageCount * 4_096)
    let container = AK47LCDEncodedContainer(
      data: data,
      frameCount: 140,
      sourceDelaysMilliseconds: Array(repeating: 100, count: 140),
      encodedDeviceDelays: Array(repeating: 50, count: 140),
      nominalEncodedDelaysMilliseconds: Array(repeating: 100, count: 140),
      effectiveDeviceDelaysMilliseconds: Array(repeating: 100, count: 140),
      firmwareMinimumAppliedFrameIndices: [],
      unpaddedByteCount: 256 + (64_800 * 140),
      pageCount: pageCount,
      paddingByte: 0xFF,
      partitionBudgetByteCount: data.count
    )

    XCTAssertThrowsError(
      try AK47LCDUploadPreflight.makeSyntheticPlan(target: target, container: container)
    ) {
      XCTAssertEqual($0 as? AK47LCDUploadError, .invalidPageCount(2_216))
    }
    XCTAssertEqual(
      AK47LCDUploadPreflight.externalFlashStartAddress
        + UInt64(AK47LCDUploadPreflight.maximumPageCount * 4_096),
      AK47LCDUploadPreflight.softwareTransferEndLimit
    )
  }

  func testModeledPlanAlwaysExposesUnverifiedRecoveryRisks() throws {
    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target, container: makeContainer())

    XCTAssertFalse(plan.physicalPartitionEndVerified)
    XCTAssertEqual(
      plan.unresolvedRisks,
      [.unverifiedPhysicalPartitionEnd, .noVerifiedReadbackOrRecovery]
    )
  }

  private var target: AK47WiredDeviceTarget {
    AK47WiredDeviceTarget(locationID: 0x1234, versionNumber: 0x0115)
  }

  private func makeContainer(
    data suppliedData: Data? = nil,
    paddingByte: UInt8 = 0xFF
  ) -> AK47LCDEncodedContainer {
    let unpadded = 256 + 64_800
    let pageCount = 16
    var data = Data(repeating: paddingByte, count: pageCount * 4_096)
    data.replaceSubrange(0..<256, with: repeatElement(UInt8(0xFF), count: 256))
    data[0] = 1
    data[1] = 50
    if let suppliedData { data = suppliedData }
    return AK47LCDEncodedContainer(
      data: data,
      frameCount: 1,
      sourceDelaysMilliseconds: [100],
      encodedDeviceDelays: [50],
      nominalEncodedDelaysMilliseconds: [100],
      effectiveDeviceDelaysMilliseconds: [100],
      firmwareMinimumAppliedFrameIndices: [],
      unpaddedByteCount: unpadded,
      pageCount: pageCount,
      paddingByte: paddingByte,
      partitionBudgetByteCount: AK47LCDFormat.maximumContainerByteCount
    )
  }

  private func acceptedFeature(for payload: [UInt8]) -> [UInt8] {
    var bytes = payload
    bytes[3] = 1
    return bytes
  }

  private func acceptedFeatureSequence(pageCount: Int) -> [[UInt8]] {
    [
      acceptedFeature(for: AK47LCDUploadStateMachine.beginPayload),
      acceptedFeature(for: AK47LCDUploadStateMachine.selectorPayload(pageCount: pageCount)),
      acceptedFeature(for: AK47LCDUploadStateMachine.commitPayload),
    ]
  }

  private func acceptedPage() -> AK47LCDInputAcknowledgement {
    var bytes = [UInt8](repeating: 0xA5, count: 64)
    bytes.replaceSubrange(0..<3, with: [0x01, 0x5A, 0x02])
    return AK47LCDInputAcknowledgement(reportID: 0, bytes: bytes)
  }
}

private final class MockLCDUploadSession: AK47LCDUploadSession {
  enum Operation: Equatable {
    case setFeature([UInt8])
    case getFeature(Int)
    case setOutput(reportID: UInt8, byteCount: Int)
    case getInput

    var featurePayload: [UInt8]? {
      guard case .setFeature(let payload) = self else { return nil }
      return payload
    }

    var isOutput: Bool {
      guard case .setOutput = self else { return false }
      return true
    }
  }

  private var featureAcknowledgements: [[UInt8]]
  private var pageAcknowledgements: [AK47LCDInputAcknowledgement]
  private(set) var operations: [Operation] = []

  init(
    featureAcknowledgements: [[UInt8]],
    pageAcknowledgements: [AK47LCDInputAcknowledgement]
  ) {
    self.featureAcknowledgements = featureAcknowledgements
    self.pageAcknowledgements = pageAcknowledgements
  }

  func setFeature(_ bytes: [UInt8], stage _: AK47LCDUploadStage) throws {
    operations.append(.setFeature(bytes))
  }

  func getFeature(
    expectedLength: Int,
    stage: AK47LCDUploadStage
  ) throws -> [UInt8] {
    operations.append(.getFeature(expectedLength))
    guard !featureAcknowledgements.isEmpty else {
      throw AK47LCDUploadError.operationTimedOut(stage: stage)
    }
    return featureAcknowledgements.removeFirst()
  }

  func setOutput(
    _ bytes: [UInt8],
    reportID: UInt8,
    stage _: AK47LCDUploadStage
  ) throws {
    operations.append(.setOutput(reportID: reportID, byteCount: bytes.count))
  }

  func getInputAcknowledgement(stage: AK47LCDUploadStage) throws
    -> AK47LCDInputAcknowledgement
  {
    operations.append(.getInput)
    guard !pageAcknowledgements.isEmpty else {
      throw AK47LCDUploadError.operationTimedOut(stage: stage)
    }
    return pageAcknowledgements.removeFirst()
  }
}
