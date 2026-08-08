import XCTest

@testable import AK47InspectorCore

final class HIDDeviceGroupingTests: XCTestCase {
  func testCollectionsAtSameLocationAreGroupedAndChannelsSelected() {
    let records = [
      record(location: 0x1010, page: 0x0001, usage: 0x0006),
      record(location: 0x1010, page: 0x000C, usage: 0x0001),
      record(location: 0x1010, page: 0xFF68, usage: 0x0061, output: 4_096),
      record(location: 0x1010, page: 0xFF13, usage: 0x0001, feature: 64),
    ]

    let groups = HIDPhysicalDeviceGrouper.group(records)

    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].identifier.basis, .location)
    XCTAssertEqual(groups[0].identifier.locationID, 0x1010)
    XCTAssertEqual(groups[0].collections.count, 4)
    XCTAssertEqual(groups[0].candidates.preferredCommand?.role, .vendorFeature64)
    XCTAssertEqual(groups[0].candidates.preferredBulkOutput?.role, .vendorOutput4096)
    XCTAssertTrue(groups[0].candidates.isComplete)
    XCTAssertFalse(groups[0].candidates.hasAmbiguity)
  }

  func testSameModelAtDifferentLocationsRemainsSeparate() {
    let records = [
      record(location: 1, page: 0xFF13, usage: 1, feature: 64),
      record(location: 2, page: 0xFF13, usage: 1, feature: 64),
    ]

    let groups = HIDPhysicalDeviceGrouper.group(records)

    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups.map(\.identifier.locationID), [1, 2])
  }

  func testSerialNumberIsFallbackCorrelationKey() {
    let records = [
      record(serial: " serial-a ", page: 0xFF13, usage: 1, feature: 64),
      record(serial: "serial-a", page: 0xFF68, usage: 0x61, output: 4_096),
    ]

    let groups = HIDPhysicalDeviceGrouper.group(records)

    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].identifier.basis, .serialNumber)
    XCTAssertEqual(groups[0].identifier.serialNumber, "serial-a")
    XCTAssertTrue(groups[0].candidates.isComplete)
  }

  func testMissingCorrelationPropertiesRemainSeparate() {
    let records = [
      record(page: 0xFF13, usage: 1, feature: 64),
      record(page: 0xFF68, usage: 0x61, output: 4_096),
    ]

    let groups = HIDPhysicalDeviceGrouper.group(records)

    XCTAssertEqual(groups.count, 2)
    XCTAssertTrue(groups.allSatisfy { $0.identifier.basis == .uncorrelated })
    XCTAssertTrue(groups.allSatisfy { $0.collections.count == 1 })
    XCTAssertFalse(groups.contains { $0.candidates.isComplete })
  }

  func testLocationNeverCombinesDifferentUSBIdentities() {
    let records = [
      record(vendor: 1, product: 2, location: 10, page: 0xFF13, usage: 1, feature: 64),
      record(vendor: 1, product: 3, location: 10, page: 0xFF68, usage: 0x61, output: 4_096),
    ]

    XCTAssertEqual(HIDPhysicalDeviceGrouper.group(records).count, 2)
  }

  func testNearMatchIsNotSelectedAsChannelCandidate() {
    let records = [
      record(location: 1, page: 0xFF13, usage: 1, feature: 63),
      record(location: 1, page: 0xFF68, usage: 0x61, output: 4_095),
    ]

    let candidates = HIDPhysicalDeviceGrouper.group(records)[0].candidates

    XCTAssertNil(candidates.preferredCommand)
    XCTAssertNil(candidates.preferredBulkOutput)
    XCTAssertFalse(candidates.isComplete)
  }

  func testAmbiguousCandidatesAreReportedAndOrderedDeterministically() {
    let records = [
      record(productName: "second", location: 1, page: 0xFF13, usage: 1, input: 32, feature: 64),
      record(productName: "first", location: 1, page: 0xFF13, usage: 1, input: 16, feature: 64),
    ]

    let candidates = HIDPhysicalDeviceGrouper.group(records)[0].candidates

    XCTAssertEqual(candidates.command.count, 2)
    XCTAssertEqual(candidates.preferredCommand?.product, "first")
    XCTAssertTrue(candidates.hasAmbiguity)
  }

  private func record(
    vendor: UInt64 = 0x1234,
    product: UInt64 = 0x5678,
    productName: String = "Test Device",
    serial: String? = nil,
    location: UInt64? = nil,
    page: UInt64?,
    usage: UInt64?,
    input: UInt64? = nil,
    output: UInt64? = nil,
    feature: UInt64? = nil
  ) -> HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: vendor,
      productID: product,
      product: productName,
      manufacturer: "Example",
      serialNumber: serial,
      transport: "USB",
      locationID: location,
      usagePage: page,
      usage: usage,
      maxInputReportSize: input,
      maxOutputReportSize: output,
      maxFeatureReportSize: feature
    )
  }
}
