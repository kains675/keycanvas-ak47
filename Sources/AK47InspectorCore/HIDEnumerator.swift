import Foundation
import IOKit.hid

public enum HIDEnumerator {
  public static let vendorID: UInt64 = 0x0C45
  public static let productID: UInt64 = 0x800A

  /// Enumerates matching top-level HID collections and reads registry properties only.
  /// The manager and devices are deliberately not opened.
  public static func enumerate() throws -> [HIDCollectionRecord] {
    let manager = IOHIDManagerCreate(
      kCFAllocatorDefault,
      IOOptionBits(kIOHIDOptionsTypeNone)
    )

    let matching: [String: Any] = [
      kIOHIDVendorIDKey: NSNumber(value: vendorID),
      kIOHIDProductIDKey: NSNumber(value: productID),
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    guard let deviceSet = IOHIDManagerCopyDevices(manager) else {
      return []
    }

    // Treat an unexpected bridge shape as an empty result instead of trapping.
    guard let devices = deviceSet as? Set<IOHIDDevice> else {
      return []
    }
    return
      devices
      .map(makeRecord)
      .sorted(by: stableOrder)
  }

  private static func makeRecord(device: IOHIDDevice) -> HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: numberProperty(kIOHIDVendorIDKey, device: device) ?? vendorID,
      productID: numberProperty(kIOHIDProductIDKey, device: device) ?? productID,
      product: stringProperty(kIOHIDProductKey, device: device),
      manufacturer: stringProperty(kIOHIDManufacturerKey, device: device),
      serialNumber: stringProperty(kIOHIDSerialNumberKey, device: device),
      transport: stringProperty(kIOHIDTransportKey, device: device),
      locationID: numberProperty(kIOHIDLocationIDKey, device: device),
      usagePage: numberProperty(kIOHIDPrimaryUsagePageKey, device: device),
      usage: numberProperty(kIOHIDPrimaryUsageKey, device: device),
      maxInputReportSize: numberProperty(kIOHIDMaxInputReportSizeKey, device: device),
      maxOutputReportSize: numberProperty(kIOHIDMaxOutputReportSizeKey, device: device),
      maxFeatureReportSize: numberProperty(kIOHIDMaxFeatureReportSizeKey, device: device)
    )
  }

  private static func numberProperty(_ key: String, device: IOHIDDevice) -> UInt64? {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.uint64Value
  }

  private static func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }

  private static func stableOrder(
    _ lhs: HIDCollectionRecord,
    _ rhs: HIDCollectionRecord
  ) -> Bool {
    let left = (
      lhs.locationID ?? UInt64.max,
      lhs.usagePage ?? UInt64.max,
      lhs.usage ?? UInt64.max,
      lhs.product ?? ""
    )
    let right = (
      rhs.locationID ?? UInt64.max,
      rhs.usagePage ?? UInt64.max,
      rhs.usage ?? UInt64.max,
      rhs.product ?? ""
    )
    return left < right
  }
}
