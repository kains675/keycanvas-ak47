import XCTest

@testable import AK47InspectorCore

final class AK47PerKeyRGBQueryTests: XCTestCase {
  func testProtocolShapeAnd84SparseIndices() {
    XCTAssertEqual(AK47PerKeyRGBQueryProtocol.lightIndices.count, 84)
    XCTAssertEqual(Set(AK47PerKeyRGBQueryProtocol.lightIndices).count, 84)
    XCTAssertEqual(AK47PerKeyRGBQueryProtocol.lightIndices.first, 1)
    XCTAssertEqual(AK47PerKeyRGBQueryProtocol.lightIndices.last, 121)

    let query = AK47PerKeyRGBQueryProtocol.queryPayload
    XCTAssertEqual(query.count, 64)
    XCTAssertEqual(query[0], 0x04)
    XCTAssertEqual(query[1], 0xF5)
    XCTAssertEqual(query[8], 0x09)
    XCTAssertEqual(query.filter { $0 != 0 }.count, 3)

    let finish = AK47PerKeyRGBQueryProtocol.finishPayload
    XCTAssertEqual(finish.count, 64)
    XCTAssertEqual(finish[0], 0x04)
    XCTAssertEqual(finish[1], 0x02)
    XCTAssertEqual(finish.filter { $0 != 0 }.count, 2)
  }

  func testParsesNinePacketsBySparseLightIndex() throws {
    let packets = syntheticPackets()
    let snapshot = try AK47PerKeyRGBQueryProtocol.parse(responsePackets: packets)

    XCTAssertEqual(snapshot.values.count, 84)
    XCTAssertEqual(snapshot.nonzeroColorCount, 84)
    XCTAssertEqual(snapshot.values.first?.lightIndex, 1)
    XCTAssertEqual(snapshot.values.first?.color, RGBColor(red: 1, green: 2, blue: 3))
    XCTAssertEqual(
      snapshot.values.last?.color,
      RGBColor(red: 121, green: 122, blue: 123)
    )
  }

  func testAllowsZeroSlotMarkersButRejectsUnexpectedNonzeroIndex() throws {
    var packets = syntheticPackets(includeIndices: false)
    XCTAssertNoThrow(try AK47PerKeyRGBQueryProtocol.parse(responsePackets: packets))

    let lightIndex = 55
    packets[lightIndex / 16][4 * (lightIndex % 16)] = 54
    XCTAssertThrowsError(try AK47PerKeyRGBQueryProtocol.parse(responsePackets: packets)) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryError,
        .invalidSlotIndex(lightIndex: lightIndex, observed: 54)
      )
    }
  }

  func testRejectsPacketCountAndLength() {
    XCTAssertThrowsError(
      try AK47PerKeyRGBQueryProtocol.parse(
        responsePackets: Array(syntheticPackets().prefix(8))
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryError,
        .invalidPacketCount(expected: 9, actual: 8)
      )
    }

    var packets = syntheticPackets()
    packets[4].removeLast()
    XCTAssertThrowsError(try AK47PerKeyRGBQueryProtocol.parse(responsePackets: packets)) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryError,
        .invalidPacketLength(packet: 4, expected: 64, actual: 63)
      )
    }
  }

  func testAcknowledgementRequires64BytesAndAcceptedStatus() throws {
    var acknowledgement = [UInt8](repeating: 0, count: 64)
    acknowledgement[3] = 1
    XCTAssertNoThrow(
      try AK47PerKeyRGBQueryProtocol.validateAcknowledgement(acknowledgement)
    )

    acknowledgement[3] = 0
    XCTAssertThrowsError(
      try AK47PerKeyRGBQueryProtocol.validateAcknowledgement(acknowledgement)
    ) {
      XCTAssertEqual($0 as? AK47PerKeyRGBQueryError, .acknowledgementRejected)
    }
    XCTAssertThrowsError(
      try AK47PerKeyRGBQueryProtocol.validateAcknowledgement(Array(acknowledgement.prefix(8)))
    ) {
      XCTAssertEqual(
        $0 as? AK47PerKeyRGBQueryError,
        .invalidAcknowledgementLength(expected: 64, actual: 8)
      )
    }
  }

  private func syntheticPackets(includeIndices: Bool = true) -> [[UInt8]] {
    var packets = Array(
      repeating: [UInt8](repeating: 0, count: 64),
      count: AK47PerKeyRGBQueryProtocol.responsePacketCount
    )
    for lightIndex in AK47PerKeyRGBQueryProtocol.lightIndices {
      let packet = lightIndex / 16
      let offset = 4 * (lightIndex % 16)
      packets[packet][offset] = includeIndices ? UInt8(lightIndex) : 0
      packets[packet][offset + 1] = UInt8(lightIndex)
      packets[packet][offset + 2] = UInt8(lightIndex + 1)
      packets[packet][offset + 3] = UInt8(lightIndex + 2)
    }
    return packets
  }
}
