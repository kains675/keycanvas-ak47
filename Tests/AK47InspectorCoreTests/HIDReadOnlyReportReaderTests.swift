import XCTest

@testable import AK47InspectorCore

final class HIDReadOnlyReportReaderTests: XCTestCase {
  func testFeatureRequestMatchesExactCommandCollection() throws {
    let request = HIDReadOnlyReportRequest(
      vendorID: 0x0C45,
      productID: 0x800A,
      product: "Archon AK47",
      locationID: 0x0210_0000,
      usagePage: 0xFF13,
      usage: 0x0001,
      reportType: .feature,
      expectedLength: 64
    )
    try request.validate()

    XCTAssertTrue(request.matches(commandRecord))
    XCTAssertFalse(request.matches(bulkRecord))
  }

  func testOutputRequestMatchesExactBulkCollection() throws {
    let request = HIDReadOnlyReportRequest(
      vendorID: 0x0C45,
      productID: 0x800A,
      product: "Archon AK47",
      locationID: 0x0210_0000,
      usagePage: 0xFF68,
      usage: 0x0061,
      reportType: .output,
      expectedLength: 4_096
    )
    try request.validate()

    XCTAssertTrue(request.matches(bulkRecord))
    XCTAssertFalse(request.matches(commandRecord))
  }

  func testLocationAndProductPreventCrossDeviceMatch() {
    let wrongLocation = HIDReadOnlyReportRequest(
      vendorID: 0x0C45,
      productID: 0x800A,
      product: "Archon AK47",
      locationID: 1,
      usagePage: 0xFF13,
      usage: 1,
      reportType: .feature,
      expectedLength: 64
    )
    let wrongProduct = HIDReadOnlyReportRequest(
      vendorID: 0x0C45,
      productID: 0x800A,
      product: "Different keyboard",
      locationID: 0x0210_0000,
      usagePage: 0xFF13,
      usage: 1,
      reportType: .feature,
      expectedLength: 64
    )

    XCTAssertFalse(wrongLocation.matches(commandRecord))
    XCTAssertFalse(wrongProduct.matches(commandRecord))
  }

  func testReadLimitsRejectOversizedReports() {
    let oversizedFeature = HIDReadOnlyReportRequest(
      vendorID: 1,
      productID: 2,
      usagePage: 3,
      usage: 4,
      reportType: .feature,
      expectedLength: 65
    )
    let oversizedOutput = HIDReadOnlyReportRequest(
      vendorID: 1,
      productID: 2,
      usagePage: 3,
      usage: 4,
      reportType: .output,
      expectedLength: 4_097
    )

    XCTAssertThrowsError(try oversizedFeature.validate())
    XCTAssertThrowsError(try oversizedOutput.validate())
  }

  private var commandRecord: HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: 0x0C45,
      productID: 0x800A,
      product: "Archon AK47",
      manufacturer: "SONiX",
      transport: "USB",
      locationID: 0x0210_0000,
      usagePage: 0xFF13,
      usage: 0x0001,
      maxInputReportSize: 64,
      maxOutputReportSize: 64,
      maxFeatureReportSize: 64
    )
  }

  private var bulkRecord: HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: 0x0C45,
      productID: 0x800A,
      product: "Archon AK47",
      manufacturer: "SONiX",
      transport: "USB",
      locationID: 0x0210_0000,
      usagePage: 0xFF68,
      usage: 0x0061,
      maxInputReportSize: 64,
      maxOutputReportSize: 4_096,
      maxFeatureReportSize: 0
    )
  }
}
