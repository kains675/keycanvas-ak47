import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47DeviceWriteHardwareTests: XCTestCase {
  func testAuthorizedClockSynchronization() throws {
    try requireAuthorization(
      key: "KEYCANVAS_AK47_CLOCK_SYNC",
      phrase: "RUN_CLOCK_ON_0C45_800A_0115"
    )
    let target = try exactTarget()
    let value = try AK47ClockSyncValue(date: Date(), lcdItemNumber: 1)

    try AK47DeviceWriteAdapter.synchronizeClock(
      target: target,
      value: value,
      authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .clockSync)
    )

    XCTAssertEqual(try exactRecords(at: target.locationID).count, 4)
    print(
      "Authorized AK47 clock synchronization completed with required ACKs accepted and clock data readback drained."
    )
  }

  func testAuthorizedStaticLightingApply() throws {
    try requireAuthorization(
      key: "KEYCANVAS_AK47_STATIC_APPLY",
      phrase: "RUN_STATIC_ON_0C45_800A_0115"
    )
    let target = try exactTarget()
    let value = AK47OnboardLightingValue(
      mode: 1,
      color: AK47InspectorCore.RGBColor(red: 32, green: 128, blue: 224),
      colorful: false,
      brightness: 3,
      speed: 3,
      direction: 0
    )

    try AK47DeviceWriteAdapter.applyOnboardLighting(
      target: target,
      value: value,
      authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .onboardLighting)
    )

    XCTAssertEqual(try exactRecords(at: target.locationID).count, 4)
    print("Authorized AK47 Static mode 1 apply completed with required ACKs accepted.")
  }

  func testAuthorizedLaunchLightingApply() throws {
    try requireAuthorization(
      key: "KEYCANVAS_AK47_MODE14_APPLY",
      phrase: "RUN_MODE14_ON_0C45_800A_0115"
    )
    let target = try exactTarget()
    let value = AK47OnboardLightingValue(
      mode: 14,
      color: AK47InspectorCore.RGBColor(red: 32, green: 128, blue: 224),
      colorful: false,
      brightness: 3,
      speed: 3,
      direction: 0
    )

    try AK47DeviceWriteAdapter.applyOnboardLighting(
      target: target,
      value: value,
      authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .onboardLighting)
    )

    XCTAssertEqual(try exactRecords(at: target.locationID).count, 4)
    print("Authorized AK47 Launch mode 14 apply completed with required ACKs accepted.")
  }

  func testAuthorizedPerKeyRGBApplyAndBrightnessAdjustedReadback() throws {
    try requireAuthorization(
      key: "KEYCANVAS_AK47_PER_KEY_APPLY",
      phrase: "RUN_PER_KEY_ON_0C45_800A_0115"
    )
    let target = try exactTarget()
    let values = AK47PerKeyRGBQueryProtocol.lightIndices.enumerated().map { offset, lightIndex in
      let palette = [
        AK47InspectorCore.RGBColor(red: 24, green: 104, blue: 224),
        AK47InspectorCore.RGBColor(red: 80, green: 210, blue: 170),
        AK47InspectorCore.RGBColor(red: 176, green: 96, blue: 240),
      ]
      return AK47PerKeyRGBValue(lightIndex: lightIndex, color: palette[offset % palette.count])
    }

    try AK47DeviceWriteAdapter.applyPerKeyRGB(
      target: target,
      brightness: 3,
      values: values,
      authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .perKeyRGB)
    )

    let request = AK47PerKeyRGBQueryRequest(
      locationID: target.locationID,
      versionNumber: target.versionNumber,
      serialNumber: target.serialNumber
    )
    let snapshot = try AK47PerKeyRGBQueryAdapter.query(
      request,
      authorization: AK47PerKeyRGBQueryAuthorization(
        explicitlyConfirming: request
      )
    )
    let expectedReadbackPalette = [
      AK47InspectorCore.RGBColor(red: 15, green: 67, blue: 146),
      AK47InspectorCore.RGBColor(red: 51, green: 137, blue: 111),
      AK47InspectorCore.RGBColor(red: 114, green: 62, blue: 156),
    ]
    XCTAssertEqual(snapshot.values.map(\.lightIndex), values.map(\.lightIndex))
    XCTAssertEqual(
      snapshot.values.map(\.color),
      snapshot.values.indices.map { expectedReadbackPalette[$0 % expectedReadbackPalette.count] }
    )
    XCTAssertEqual(snapshot.nonzeroColorCount, 84)
    XCTAssertEqual(snapshot.distinctColorCount, 3)
    XCTAssertEqual(try exactRecords(at: target.locationID).count, 4)
    print(
      "Authorized AK47 84-key RGB apply completed; F5 preserved every key assignment and returned the three brightness-adjusted colors observed at level 3."
    )
  }

  private func requireAuthorization(key: String, phrase: String) throws {
    guard ProcessInfo.processInfo.environment[key] == phrase else {
      throw XCTSkip("Set the operation-specific hardware authorization phrase to run this test.")
    }
  }

  private func exactTarget() throws -> AK47WiredDeviceTarget {
    let records = try HIDEnumerator.enumerate()
    let commands = records.filter { record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == "Archon AK47"
        && record.transport == "USB"
        && record.versionNumber == 0x0115
        && record.usagePage == 0xFF13
        && record.usage == 0x0001
        && record.maxInputReportSize == 64
        && record.maxOutputReportSize == 64
        && record.maxFeatureReportSize == 64
    }
    guard commands.count == 1, let locationID = commands[0].locationID else {
      throw AK47DeviceWriteError.noMatchingCollection
    }
    let target = AK47WiredDeviceTarget(locationID: locationID, versionNumber: 0x0115)
    guard try exactRecords(at: locationID).count == 4 else {
      throw AK47DeviceWriteError.unexpectedTopology(
        collections: try exactRecords(at: locationID).count
      )
    }
    return target
  }

  private func exactRecords(at locationID: UInt64) throws -> [HIDCollectionRecord] {
    try HIDEnumerator.enumerate().filter { record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == "Archon AK47"
        && record.transport == "USB"
        && record.versionNumber == 0x0115
        && record.locationID == locationID
    }
  }
}
