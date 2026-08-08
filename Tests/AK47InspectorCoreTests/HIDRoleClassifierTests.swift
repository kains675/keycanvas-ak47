import XCTest

@testable import AK47InspectorCore

final class HIDRoleClassifierTests: XCTestCase {
  func testKeyboardCollection() {
    XCTAssertEqual(
      classify(page: 0x0001, usage: 0x0006),
      .keyboard
    )
  }

  func testConsumerCollection() {
    XCTAssertEqual(
      classify(page: 0x000C, usage: 0x0001),
      .consumer
    )
  }

  func testVendorFeatureRoleRequires64ByteFeatureReport() {
    XCTAssertEqual(
      classify(page: 0xFF13, usage: 0x0001, feature: 64),
      .vendorFeature64
    )
    XCTAssertEqual(
      classify(page: 0xFF13, usage: 0x0001, feature: 63),
      .unknown
    )
    XCTAssertEqual(
      classify(page: 0xFF13, usage: 0x0001, feature: nil),
      .unknown
    )
  }

  func testVendorOutputRoleRequires4096ByteOutputReport() {
    XCTAssertEqual(
      classify(page: 0xFF68, usage: 0x0061, output: 4_096),
      .vendorOutput4096
    )
    XCTAssertEqual(
      classify(page: 0xFF68, usage: 0x0061, output: 4_095),
      .unknown
    )
    XCTAssertEqual(
      classify(page: 0xFF68, usage: 0x0061, output: nil),
      .unknown
    )
  }

  func testNearMatchesRemainUnknown() {
    XCTAssertEqual(classify(page: 0x0001, usage: 0x0005), .unknown)
    XCTAssertEqual(classify(page: 0x000D, usage: 0x0001), .unknown)
    XCTAssertEqual(classify(page: nil, usage: nil), .unknown)
  }

  private func classify(
    page: UInt64?,
    usage: UInt64?,
    input: UInt64? = nil,
    output: UInt64? = nil,
    feature: UInt64? = nil
  ) -> HIDRole {
    HIDRoleClassifier.classify(
      HIDCollectionDescriptor(
        usagePage: page,
        usage: usage,
        maxInputReportSize: input,
        maxOutputReportSize: output,
        maxFeatureReportSize: feature
      )
    )
  }
}
