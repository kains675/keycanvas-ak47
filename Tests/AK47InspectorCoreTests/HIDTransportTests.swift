import XCTest

@testable import AK47InspectorCore

final class HIDTransportTests: XCTestCase {
  func testDefaultGateAllowsInspectionRead() throws {
    let request = HIDTransportRequest.readFeature(reportID: 1, expectedLength: 4)
    let mock = MockHIDTransport(steps: [
      MockHIDTransportStep(
        expectedRequest: request,
        response: HIDTransportResponse(bytes: [1, 2, 3, 4])
      )
    ])
    let gated = CapabilityGatedHIDTransport(underlying: mock)

    XCTAssertEqual(try gated.perform(request).bytes, [1, 2, 3, 4])
    XCTAssertEqual(mock.performedRequests, [request])
  }

  func testDefaultGateDeniesConfigurationWriteWithoutForwarding() {
    let request = HIDTransportRequest.writeFeature(
      reportID: 0,
      bytes: [1]
    )
    let mock = MockHIDTransport()
    let gated = CapabilityGatedHIDTransport(underlying: mock)

    XCTAssertThrowsError(try gated.perform(request)) { error in
      XCTAssertEqual(error as? HIDTransportError, .capabilityDenied(.configurationWrite))
    }
    XCTAssertTrue(mock.performedRequests.isEmpty)
  }

  func testDefaultGateDeniesOutputWriteWithoutForwarding() {
    let request = HIDTransportRequest.writeOutput(
      reportID: 0,
      bytes: [1, 2]
    )
    let mock = MockHIDTransport()
    let gated = CapabilityGatedHIDTransport(underlying: mock)

    XCTAssertThrowsError(try gated.perform(request)) { error in
      XCTAssertEqual(error as? HIDTransportError, .capabilityDenied(.configurationWrite))
    }
    XCTAssertTrue(mock.performedRequests.isEmpty)
  }

  func testConfigurationGrantAllowsFeatureAndOutputRequests() throws {
    let feature = HIDTransportRequest.writeFeature(
      reportID: 0,
      bytes: [1]
    )
    let output = HIDTransportRequest.writeOutput(
      reportID: 0,
      bytes: [2]
    )
    let mock = MockHIDTransport(steps: [
      MockHIDTransportStep(
        expectedRequest: feature,
        response: HIDTransportResponse()
      ),
      MockHIDTransportStep(
        expectedRequest: output,
        response: HIDTransportResponse()
      ),
    ])
    let gated = CapabilityGatedHIDTransport(
      underlying: mock,
      policy: HIDCapabilityPolicy(allowConfigurationWrites: true)
    )

    XCTAssertEqual(try gated.perform(feature), HIDTransportResponse())
    XCTAssertEqual(try gated.perform(output), HIDTransportResponse())
    XCTAssertEqual(mock.performedRequests, [feature, output])
  }

  func testReadResponseLengthIsChecked() {
    let request = HIDTransportRequest.readFeature(reportID: 1, expectedLength: 4)
    let mock = MockHIDTransport(steps: [
      MockHIDTransportStep(response: HIDTransportResponse(bytes: [1, 2]))
    ])

    XCTAssertThrowsError(
      try CapabilityGatedHIDTransport(underlying: mock).perform(request)
    ) { error in
      XCTAssertEqual(
        error as? HIDTransportError,
        .invalidResponse(expectedLength: 4, actualLength: 2)
      )
    }
  }

  func testInvalidRequestIsRejectedBeforeForwarding() {
    let request = HIDTransportRequest.writeFeature(
      reportID: 0,
      bytes: [UInt8](repeating: 0, count: 65)
    )
    let mock = MockHIDTransport()
    let gated = CapabilityGatedHIDTransport(
      underlying: mock,
      policy: HIDCapabilityPolicy(allowConfigurationWrites: true)
    )

    XCTAssertThrowsError(try gated.perform(request))
    XCTAssertTrue(mock.performedRequests.isEmpty)
  }

  func testFeatureReadCannotExceedCommandReportSize() {
    let request = HIDTransportRequest.readFeature(reportID: 0, expectedLength: 65)
    let mock = MockHIDTransport()

    XCTAssertThrowsError(
      try CapabilityGatedHIDTransport(underlying: mock).perform(request)
    ) { error in
      guard case .invalidRequest = error as? HIDTransportError else {
        return XCTFail("expected invalid request, got \(error)")
      }
    }
    XCTAssertTrue(mock.performedRequests.isEmpty)
  }

  func testMockChecksExpectedRequestAndPreservesMismatchedStep() {
    let expected = HIDTransportRequest.readFeature(reportID: 1, expectedLength: 1)
    let actual = HIDTransportRequest.readFeature(reportID: 2, expectedLength: 1)
    let mock = MockHIDTransport(steps: [
      MockHIDTransportStep(
        expectedRequest: expected,
        response: HIDTransportResponse(bytes: [0])
      )
    ])

    XCTAssertThrowsError(try mock.perform(actual)) { error in
      XCTAssertEqual(
        error as? HIDTransportError,
        .unexpectedRequest(expected: expected, actual: actual)
      )
    }
    XCTAssertEqual(mock.remainingStepCount, 1)
    XCTAssertEqual(mock.performedRequests, [actual])
  }

  func testMockCanScriptFailureAndReset() {
    let request = HIDTransportRequest.readFeature(reportID: 1, expectedLength: 1)
    let mock = MockHIDTransport(steps: [
      MockHIDTransportStep(expectedRequest: request, failure: "offline")
    ])

    XCTAssertThrowsError(try mock.perform(request)) { error in
      XCTAssertEqual(error as? HIDTransportError, .scriptedFailure("offline"))
    }
    XCTAssertEqual(mock.performedRequests, [request])
    mock.reset()
    XCTAssertTrue(mock.performedRequests.isEmpty)
    XCTAssertEqual(mock.remainingStepCount, 0)
  }
}
