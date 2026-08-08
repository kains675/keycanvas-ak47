import XCTest

@testable import AK47InspectorCore

final class HIDFrameCodecTests: XCTestCase {
  func testCRC16KnownVector() {
    XCTAssertEqual(FrameChecksum.crc16CCITT(Array("123456789".utf8)), 0x29B1)
  }

  func testFeatureFrameRoundTrip() throws {
    let frame = try FeatureReportFrame(
      reportID: 3,
      protocolVersion: 1,
      messageType: 7,
      flags: 0x80,
      sequence: 0x1234,
      payload: [1, 2, 3, 4]
    )

    let bytes = FeatureReportCodec.encode(frame)

    XCTAssertEqual(bytes.count, 64)
    XCTAssertEqual(bytes[4], 0x34)
    XCTAssertEqual(bytes[5], 0x12)
    XCTAssertEqual(try FeatureReportCodec.decode(bytes), frame)
  }

  func testFeatureFrameSupportsMaximumPayload() throws {
    let frame = try FeatureReportFrame(
      reportID: 0,
      protocolVersion: 1,
      messageType: 2,
      sequence: 0,
      payload: [UInt8](repeating: 0xAA, count: FeatureReportFrame.maximumPayloadSize)
    )

    XCTAssertEqual(try FeatureReportCodec.decode(FeatureReportCodec.encode(frame)), frame)
  }

  func testFeatureFrameRejectsOversizedPayload() {
    XCTAssertThrowsError(
      try FeatureReportFrame(
        reportID: 0,
        protocolVersion: 1,
        messageType: 2,
        sequence: 0,
        payload: [UInt8](repeating: 0, count: 55)
      )
    ) { error in
      XCTAssertEqual(
        error as? HIDFrameCodecError,
        .payloadTooLarge(maximum: 54, actual: 55)
      )
    }
  }

  func testFeatureDecodeRejectsIncorrectLength() {
    XCTAssertThrowsError(try FeatureReportCodec.decode([UInt8](repeating: 0, count: 63))) {
      XCTAssertEqual(
        $0 as? HIDFrameCodecError,
        .invalidFrameLength(expected: 64, actual: 63)
      )
    }
  }

  func testFeatureDecodeRejectsChecksumCorruption() throws {
    let frame = try FeatureReportFrame(
      reportID: 0,
      protocolVersion: 1,
      messageType: 2,
      sequence: 0,
      payload: [1]
    )
    var bytes = FeatureReportCodec.encode(frame)
    bytes[8] ^= 0xFF

    XCTAssertThrowsError(try FeatureReportCodec.decode(bytes)) { error in
      guard case .checksumMismatch = error as? HIDFrameCodecError else {
        return XCTFail("expected checksum mismatch, got \(error)")
      }
    }
  }

  func testFeatureDecodeRejectsNonCanonicalPadding() throws {
    let frame = try FeatureReportFrame(
      reportID: 0,
      protocolVersion: 1,
      messageType: 2,
      sequence: 0,
      payload: [1]
    )
    var bytes = FeatureReportCodec.encode(frame)
    bytes[20] = 1
    refreshChecksum(&bytes)

    XCTAssertThrowsError(try FeatureReportCodec.decode(bytes)) { error in
      XCTAssertEqual(error as? HIDFrameCodecError, .nonZeroPadding(offset: 20))
    }
  }

  func testInterruptFrameRoundTripWithFragmentMetadata() throws {
    let frame = try InterruptReportFrame(
      reportID: 2,
      protocolVersion: 1,
      messageType: 9,
      flags: 1,
      sequence: 0xABCD,
      fragmentIndex: 1,
      fragmentCount: 3,
      payload: [10, 20, 30]
    )

    let bytes = InterruptReportCodec.encode(frame)

    XCTAssertEqual(bytes.count, 32)
    XCTAssertEqual(bytes[4], 0xCD)
    XCTAssertEqual(bytes[5], 0xAB)
    XCTAssertEqual(try InterruptReportCodec.decode(bytes), frame)
  }

  func testInterruptFrameSupportsMaximumPayload() throws {
    let frame = try InterruptReportFrame(
      reportID: 0,
      protocolVersion: 1,
      messageType: 1,
      sequence: 0,
      payload: [UInt8](repeating: 1, count: 21)
    )

    XCTAssertEqual(try InterruptReportCodec.decode(InterruptReportCodec.encode(frame)), frame)
  }

  func testInterruptFrameRejectsInvalidFragmentMetadata() {
    XCTAssertThrowsError(
      try InterruptReportFrame(
        reportID: 0,
        protocolVersion: 1,
        messageType: 1,
        sequence: 0,
        fragmentIndex: 1,
        fragmentCount: 1,
        payload: []
      )
    ) { error in
      XCTAssertEqual(error as? HIDFrameCodecError, .invalidFragment(index: 1, count: 1))
    }
  }

  func testInterruptDecodeChecksEncodedPayloadLengthBeforeSlicing() throws {
    let frame = try InterruptReportFrame(
      reportID: 0,
      protocolVersion: 1,
      messageType: 1,
      sequence: 0,
      payload: []
    )
    var bytes = InterruptReportCodec.encode(frame)
    bytes[8] = 22
    refreshChecksum(&bytes)

    XCTAssertThrowsError(try InterruptReportCodec.decode(bytes)) { error in
      XCTAssertEqual(error as? HIDFrameCodecError, .invalidPayloadLength(22))
    }
  }

  private func refreshChecksum(_ bytes: inout [UInt8]) {
    let offset = bytes.count - 2
    let checksum = FrameChecksum.crc16CCITT(bytes[..<offset])
    bytes[offset] = UInt8(truncatingIfNeeded: checksum)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: checksum >> 8)
  }
}
