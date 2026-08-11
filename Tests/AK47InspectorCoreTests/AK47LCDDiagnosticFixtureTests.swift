import CryptoKit
import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47LCDDiagnosticFixtureTests: XCTestCase {
  func testCanonicalImageHasUnambiguousCornerOrientation() throws {
    let image = try AK47LCDDiagnosticFixture.makeImage()

    XCTAssertEqual(image.width, 240)
    XCTAssertEqual(image.height, 135)
    XCTAssertTrue(image.isOpaque)
    XCTAssertEqual(image.color(x: 0, y: 0), AK47LCDDiagnosticFixture.topLeftColor)
    XCTAssertEqual(image.color(x: 31, y: 31), AK47LCDDiagnosticFixture.topLeftColor)
    XCTAssertEqual(image.color(x: 32, y: 31), .black)
    XCTAssertEqual(image.color(x: 208, y: 0), AK47LCDDiagnosticFixture.topRightColor)
    XCTAssertEqual(image.color(x: 239, y: 31), AK47LCDDiagnosticFixture.topRightColor)
    XCTAssertEqual(image.color(x: 0, y: 103), AK47LCDDiagnosticFixture.bottomLeftColor)
    XCTAssertEqual(image.color(x: 31, y: 134), AK47LCDDiagnosticFixture.bottomLeftColor)
    XCTAssertEqual(image.color(x: 208, y: 103), AK47LCDDiagnosticFixture.bottomRightColor)
    XCTAssertEqual(image.color(x: 239, y: 134), AK47LCDDiagnosticFixture.bottomRightColor)
    XCTAssertEqual(image.color(x: 120, y: 67), .black)
  }

  func testEncodedFixtureMatchesCapturedOneFrameShapeAndGoldenHash() throws {
    let encoded = try AK47LCDDiagnosticFixture.encode()

    XCTAssertEqual(encoded.frameCount, 1)
    XCTAssertEqual(encoded.sourceDelaysMilliseconds, [100])
    XCTAssertEqual(encoded.encodedDeviceDelays, [0x32])
    XCTAssertEqual(encoded.unpaddedByteCount, 65_056)
    XCTAssertEqual(encoded.pageCount, 16)
    XCTAssertEqual(encoded.pages.count, 16)
    XCTAssertTrue(encoded.pages.allSatisfy { $0.count == 4_096 })
    XCTAssertEqual(encoded.data.count, 65_536)
    XCTAssertEqual(encoded.paddingByte, 0xFF)
    XCTAssertEqual(encoded.data[0], 1)
    XCTAssertEqual(encoded.data[1], 0x32)
    XCTAssertTrue(encoded.data[2..<256].allSatisfy { $0 == 0xFF })
    XCTAssertTrue(encoded.data[65_056..<65_536].allSatisfy { $0 == 0xFF })
    XCTAssertEqual(encoded.data[65_056..<65_536].count, 480)

    XCTAssertEqual(rgb565Bytes(in: encoded.data, x: 0, y: 0), [0x00, 0xF8])
    XCTAssertEqual(rgb565Bytes(in: encoded.data, x: 31, y: 31), [0x00, 0xF8])
    XCTAssertEqual(rgb565Bytes(in: encoded.data, x: 208, y: 0), [0xE0, 0x07])
    XCTAssertEqual(rgb565Bytes(in: encoded.data, x: 0, y: 103), [0x1F, 0x00])
    XCTAssertEqual(rgb565Bytes(in: encoded.data, x: 239, y: 134), [0xFF, 0xFF])
    XCTAssertEqual(rgb565Bytes(in: encoded.data, x: 120, y: 67), [0x00, 0x00])

    XCTAssertEqual(sha256Hex(encoded.data), AK47LCDDiagnosticFixture.expectedContainerSHA256)
  }

  private func rgb565Bytes(in container: Data, x: Int, y: Int) -> [UInt8] {
    let offset = 256 + (((y * AK47LCDFormat.canvasWidth) + x) * 2)
    return [container[offset], container[offset + 1]]
  }

  private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
