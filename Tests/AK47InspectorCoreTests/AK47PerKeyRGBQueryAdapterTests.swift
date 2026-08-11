import XCTest

@testable import AK47InspectorCore

final class AK47PerKeyRGBQueryAdapterTests: XCTestCase {
  func testTransactionUsesOneQueryNineReadsAndOneFinish() throws {
    let acknowledgement = acceptedAcknowledgement()
    let packets = syntheticPackets()
    let session = MockFeatureSession(
      responses: [acknowledgement] + packets + [acknowledgement]
    )
    var sleeps: [UInt32] = []

    let snapshot = try AK47PerKeyRGBTransaction.execute(
      session: session,
      sleep: { sleeps.append($0) }
    )

    XCTAssertEqual(snapshot.values.count, 84)
    XCTAssertEqual(
      session.operations,
      [.set(AK47PerKeyRGBQueryProtocol.queryPayload)]
        + Array(repeating: .get(64), count: 10)
        + [.set(AK47PerKeyRGBQueryProtocol.finishPayload), .get(64)]
    )
    XCTAssertEqual(sleeps, [10, 3, 5] + Array(repeating: 3, count: 9) + [35, 35])
  }

  func testRejectedQueryAcknowledgementNeverReadsDataOrFinishes() {
    let session = MockFeatureSession(
      responses: [[UInt8](repeating: 0, count: 64)]
    )

    XCTAssertThrowsError(
      try AK47PerKeyRGBTransaction.execute(session: session, sleep: { _ in })
    ) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryAdapterError,
        .acknowledgementRejected(stage: .queryAcknowledgement)
      )
    }
    XCTAssertEqual(
      session.operations,
      [.set(AK47PerKeyRGBQueryProtocol.queryPayload), .get(64)]
    )
  }

  func testDataReadFailureNeverSendsFinish() {
    let acknowledgement = acceptedAcknowledgement()
    let session = MockFeatureSession(
      responses: [acknowledgement, syntheticPackets()[0]],
      failureAfterResponses: MockFailure.read
    )

    XCTAssertThrowsError(
      try AK47PerKeyRGBTransaction.execute(session: session, sleep: { _ in })
    )
    XCTAssertFalse(
      session.operations.contains(.set(AK47PerKeyRGBQueryProtocol.finishPayload))
    )
  }

  func testParserRejectsSlotBeforeFinish() {
    let acknowledgement = acceptedAcknowledgement()
    var packets = syntheticPackets()
    packets[0][4] = 2
    let session = MockFeatureSession(
      responses: [acknowledgement] + packets + [acknowledgement]
    )

    XCTAssertThrowsError(
      try AK47PerKeyRGBTransaction.execute(session: session, sleep: { _ in })
    ) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryError,
        .invalidSlotIndex(lightIndex: 1, observed: 2)
      )
    }
    XCTAssertEqual(
      session.operations,
      [.set(AK47PerKeyRGBQueryProtocol.queryPayload)]
        + Array(repeating: .get(64), count: 10)
    )
  }

  func testRequestRequiresExactVerifiedRevisionAndProduct() throws {
    XCTAssertNoThrow(
      try AK47PerKeyRGBQueryRequest(locationID: 1, versionNumber: 0x0115).validate()
    )
    XCTAssertThrowsError(
      try AK47PerKeyRGBQueryRequest(locationID: 1, versionNumber: 0x0106).validate()
    )
    XCTAssertThrowsError(
      try AK47PerKeyRGBQueryRequest(
        product: "Other",
        locationID: 1,
        versionNumber: 0x0115
      ).validate()
    )
  }

  func testAuthorizationIsBoundToOneExactRequestAndConsumedOnce() throws {
    let request = AK47PerKeyRGBQueryRequest(
      locationID: 0x0014_0000,
      versionNumber: 0x0115
    )
    let otherRequest = AK47PerKeyRGBQueryRequest(
      locationID: 0x0020_0000,
      versionNumber: 0x0115
    )
    let authorization = AK47PerKeyRGBQueryAuthorization(
      explicitlyConfirming: request
    )

    XCTAssertThrowsError(try authorization.consume(for: otherRequest)) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryAdapterError,
        .authorizationMismatch
      )
    }
    XCTAssertNoThrow(try authorization.consume(for: request))
    XCTAssertThrowsError(try authorization.consume(for: request)) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryAdapterError,
        .authorizationAlreadyConsumed
      )
    }
  }

  func testAuthorizedHardwareOneShotQuery() throws {
    let authorization = ProcessInfo.processInfo.environment["KEYCANVAS_AK47_RGB_QUERY"]
    guard authorization == "RUN_ONE_SHOT_ON_0C45_800A_0115" else {
      throw XCTSkip("Set the explicit hardware authorization phrase to run this test.")
    }

    let records = try HIDEnumerator.enumerate()
    let commandRecords = records.filter {
      $0.vendorID == HIDEnumerator.vendorID
        && $0.productID == HIDEnumerator.productID
        && $0.product == "Archon AK47"
        && $0.versionNumber == 0x0115
        && $0.usagePage == 0xFF13
        && $0.usage == 0x0001
        && $0.maxFeatureReportSize == 64
    }
    let command = try XCTUnwrap(commandRecords.only)
    let locationID = try XCTUnwrap(command.locationID)
    let request = AK47PerKeyRGBQueryRequest(
      locationID: locationID,
      versionNumber: 0x0115
    )
    let snapshot = try AK47PerKeyRGBQueryAdapter.query(
      request,
      authorization: AK47PerKeyRGBQueryAuthorization(
        explicitlyConfirming: request
      )
    )

    XCTAssertEqual(snapshot.values.count, 84)
    XCTAssertEqual(try HIDEnumerator.enumerate().filter { $0.locationID == locationID }.count, 4)
    print(
      "Authorized AK47 RGB query succeeded: colors=\(snapshot.values.count), "
        + "nonzero=\(snapshot.nonzeroColorCount), distinct=\(snapshot.distinctColorCount)"
    )
  }

  private func acceptedAcknowledgement() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[3] = 1
    return bytes
  }

  private func syntheticPackets() -> [[UInt8]] {
    var packets = Array(repeating: [UInt8](repeating: 0, count: 64), count: 9)
    for lightIndex in AK47PerKeyRGBQueryProtocol.lightIndices {
      let packet = lightIndex / 16
      let offset = 4 * (lightIndex % 16)
      packets[packet][offset] = UInt8(lightIndex)
      packets[packet][offset + 1] = UInt8(lightIndex)
      packets[packet][offset + 2] = UInt8(lightIndex + 1)
      packets[packet][offset + 3] = UInt8(lightIndex + 2)
    }
    return packets
  }
}

private enum MockFailure: Error {
  case read
}

private final class MockFeatureSession: AK47FeatureReportSession {
  enum Operation: Equatable {
    case set([UInt8])
    case get(Int)
  }

  private var responses: [[UInt8]]
  private let failureAfterResponses: Error?
  private(set) var operations: [Operation] = []

  init(responses: [[UInt8]], failureAfterResponses: Error? = nil) {
    self.responses = responses
    self.failureAfterResponses = failureAfterResponses
  }

  func setFeature(_ bytes: [UInt8], stage _: AK47PerKeyRGBQueryStage) throws {
    operations.append(.set(bytes))
  }

  func getFeature(
    expectedLength: Int,
    stage _: AK47PerKeyRGBQueryStage
  ) throws -> [UInt8] {
    operations.append(.get(expectedLength))
    guard !responses.isEmpty else {
      throw failureAfterResponses ?? MockFailure.read
    }
    return responses.removeFirst()
  }
}

extension Array {
  fileprivate var only: Element? {
    count == 1 ? self[0] : nil
  }
}
