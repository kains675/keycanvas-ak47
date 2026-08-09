import Foundation
import IOKit.hid

public enum HIDReadOnlyReportType: String, Codable, Equatable, Sendable {
  case feature
  case output
}

/// Identifies one observable HID collection and one report that may be read.
///
/// The request deliberately has no write counterpart. A location identifier is
/// required when it is available so two identical keyboards are never merged.
public struct HIDReadOnlyReportRequest: Equatable, Sendable {
  public let vendorID: UInt64
  public let productID: UInt64
  public let product: String?
  public let locationID: UInt64?
  public let usagePage: UInt64
  public let usage: UInt64
  public let reportType: HIDReadOnlyReportType
  public let reportID: UInt8
  public let expectedLength: Int

  public init(
    vendorID: UInt64,
    productID: UInt64,
    product: String? = nil,
    locationID: UInt64? = nil,
    usagePage: UInt64,
    usage: UInt64,
    reportType: HIDReadOnlyReportType,
    reportID: UInt8 = 0,
    expectedLength: Int
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.locationID = locationID
    self.usagePage = usagePage
    self.usage = usage
    self.reportType = reportType
    self.reportID = reportID
    self.expectedLength = expectedLength
  }

  public func validate() throws {
    guard vendorID <= UInt64(UInt32.max), productID <= UInt64(UInt32.max) else {
      throw HIDReadOnlyReportError.invalidRequest("vendor and product IDs must fit in 32 bits")
    }
    guard usagePage <= UInt64(UInt32.max), usage <= UInt64(UInt32.max) else {
      throw HIDReadOnlyReportError.invalidRequest("usage values must fit in 32 bits")
    }
    let allowedLength = reportType == .feature ? 1...64 : 1...4_096
    guard allowedLength.contains(expectedLength) else {
      throw HIDReadOnlyReportError.invalidRequest(
        "\(reportType.rawValue) report length is outside the read-only limit"
      )
    }
  }

  public func matches(_ record: HIDCollectionRecord) -> Bool {
    guard record.vendorID == vendorID, record.productID == productID,
      record.usagePage == usagePage, record.usage == usage
    else {
      return false
    }
    if let product, record.product != product {
      return false
    }
    if let locationID, record.locationID != locationID {
      return false
    }
    switch reportType {
    case .feature:
      return record.maxFeatureReportSize == UInt64(expectedLength)
    case .output:
      return record.maxOutputReportSize == UInt64(expectedLength)
    }
  }
}

public struct HIDReadOnlyReport: Equatable, Sendable {
  public let reportType: HIDReadOnlyReportType
  public let reportID: UInt8
  public let bytes: [UInt8]

  public init(reportType: HIDReadOnlyReportType, reportID: UInt8, bytes: [UInt8]) {
    self.reportType = reportType
    self.reportID = reportID
    self.bytes = bytes
  }
}

public enum HIDReadOnlyReportError: Error, Equatable, LocalizedError, Sendable {
  case invalidRequest(String)
  case noMatchingCollection
  case ambiguousCollections(Int)
  case deviceBusy
  case openFailed(UInt32)
  case readFailed(UInt32)
  case invalidResponseLength(expected: Int, actual: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason):
      return "invalid read-only HID request: \(reason)"
    case .noMatchingCollection:
      return "no matching HID collection was found"
    case .ambiguousCollections(let count):
      return "refusing to read because \(count) HID collections match"
    case .deviceBusy:
      return "another HID diagnostic operation is already in progress"
    case .openFailed(let code):
      return String(format: "opening the HID collection failed (0x%08X)", code)
    case .readFailed(let code):
      return String(format: "reading the HID report failed (0x%08X)", code)
    case .invalidResponseLength(let expected, let actual):
      return "HID report length mismatch; expected \(expected), received \(actual)"
    }
  }
}

/// Performs one synchronous GetReport operation and immediately closes the
/// collection. Call this API away from the main actor because a device read can
/// block. No SetReport, output write, value mutation, seize, or retry is used.
public enum HIDReadOnlyReportReader {
  public static func read(_ request: HIDReadOnlyReportRequest) throws -> HIDReadOnlyReport {
    try request.validate()
    guard HIDDeviceOperationGate.acquire() else {
      throw HIDReadOnlyReportError.deviceBusy
    }
    defer { HIDDeviceOperationGate.release() }

    let manager = IOHIDManagerCreate(
      kCFAllocatorDefault,
      IOOptionBits(kIOHIDOptionsTypeNone)
    )
    let matching: [String: Any] = [
      kIOHIDVendorIDKey: NSNumber(value: request.vendorID),
      kIOHIDProductIDKey: NSNumber(value: request.productID),
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    guard let deviceSet = IOHIDManagerCopyDevices(manager),
      let devices = deviceSet as? Set<IOHIDDevice>
    else {
      throw HIDReadOnlyReportError.noMatchingCollection
    }

    let candidates = devices.filter { device in
      request.matches(record(for: device))
    }
    guard !candidates.isEmpty else {
      throw HIDReadOnlyReportError.noMatchingCollection
    }
    guard candidates.count == 1, let device = candidates.first else {
      throw HIDReadOnlyReportError.ambiguousCollections(candidates.count)
    }

    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw HIDReadOnlyReportError.openFailed(rawCode(openResult))
    }
    defer {
      _ = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    var bytes = [UInt8](repeating: 0, count: request.expectedLength)
    var reportLength = bytes.count
    let reportType: IOHIDReportType =
      request.reportType == .feature ? kIOHIDReportTypeFeature : kIOHIDReportTypeOutput
    let readResult = bytes.withUnsafeMutableBufferPointer { buffer in
      IOHIDDeviceGetReport(
        device,
        reportType,
        CFIndex(request.reportID),
        buffer.baseAddress!,
        &reportLength
      )
    }
    guard readResult == kIOReturnSuccess else {
      throw HIDReadOnlyReportError.readFailed(rawCode(readResult))
    }
    guard reportLength == request.expectedLength else {
      throw HIDReadOnlyReportError.invalidResponseLength(
        expected: request.expectedLength,
        actual: reportLength
      )
    }

    return HIDReadOnlyReport(
      reportType: request.reportType,
      reportID: request.reportID,
      bytes: Array(bytes.prefix(reportLength))
    )
  }

  private static func record(for device: IOHIDDevice) -> HIDCollectionRecord {
    HIDCollectionRecord(
      vendorID: numberProperty(kIOHIDVendorIDKey, device: device) ?? 0,
      productID: numberProperty(kIOHIDProductIDKey, device: device) ?? 0,
      product: stringProperty(kIOHIDProductKey, device: device),
      manufacturer: stringProperty(kIOHIDManufacturerKey, device: device),
      serialNumber: stringProperty(kIOHIDSerialNumberKey, device: device),
      transport: stringProperty(kIOHIDTransportKey, device: device),
      versionNumber: numberProperty(kIOHIDVersionNumberKey, device: device),
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

  private static func rawCode(_ result: IOReturn) -> UInt32 {
    UInt32(bitPattern: result)
  }
}
