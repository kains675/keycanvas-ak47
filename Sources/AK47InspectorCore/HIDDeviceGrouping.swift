import Foundation

public enum HIDPhysicalIdentityBasis: String, Codable, Equatable, Sendable {
  case location
  case serialNumber = "serial-number"
  case uncorrelated
}

/// A conservative identity for a physical HID device.
///
/// A location identifier is preferred because all top-level collections exposed by
/// one USB device normally share it. A non-empty serial number is the fallback. When
/// neither property is available, collections deliberately remain separate rather
/// than risking the merger of two identical keyboards.
public struct HIDPhysicalDeviceIdentifier: Codable, Equatable, Sendable {
  public let basis: HIDPhysicalIdentityBasis
  public let vendorID: UInt64
  public let productID: UInt64
  public let locationID: UInt64?
  public let serialNumber: String?
  public let uncorrelatedOrdinal: Int?

  fileprivate init(
    basis: HIDPhysicalIdentityBasis,
    vendorID: UInt64,
    productID: UInt64,
    locationID: UInt64? = nil,
    serialNumber: String? = nil,
    uncorrelatedOrdinal: Int? = nil
  ) {
    self.basis = basis
    self.vendorID = vendorID
    self.productID = productID
    self.locationID = locationID
    self.serialNumber = serialNumber
    self.uncorrelatedOrdinal = uncorrelatedOrdinal
  }
}

public struct HIDChannelCandidates: Equatable, Sendable {
  public let command: [HIDCollectionRecord]
  public let bulkOutput: [HIDCollectionRecord]

  public var preferredCommand: HIDCollectionRecord? { command.first }
  public var preferredBulkOutput: HIDCollectionRecord? { bulkOutput.first }
  public var hasAmbiguity: Bool { command.count > 1 || bulkOutput.count > 1 }
  public var isComplete: Bool { preferredCommand != nil && preferredBulkOutput != nil }

  fileprivate init(collections: [HIDCollectionRecord]) {
    command =
      collections
      .filter { record in
        record.role == .vendorFeature64 && record.maxFeatureReportSize == 64
      }
      .sorted(by: HIDPhysicalDeviceGrouper.candidateOrder)
    bulkOutput =
      collections
      .filter { record in
        record.role == .vendorOutput4096 && record.maxOutputReportSize == 4_096
      }
      .sorted(by: HIDPhysicalDeviceGrouper.candidateOrder)
  }
}

public struct HIDPhysicalDeviceGroup: Equatable, Sendable {
  public let identifier: HIDPhysicalDeviceIdentifier
  public let collections: [HIDCollectionRecord]
  public let candidates: HIDChannelCandidates

  fileprivate init(
    identifier: HIDPhysicalDeviceIdentifier,
    collections: [HIDCollectionRecord]
  ) {
    let ordered = collections.sorted(by: HIDPhysicalDeviceGrouper.collectionOrder)
    self.identifier = identifier
    self.collections = ordered
    self.candidates = HIDChannelCandidates(collections: ordered)
  }
}

public enum HIDPhysicalDeviceGrouper {
  public static func group(_ collections: [HIDCollectionRecord]) -> [HIDPhysicalDeviceGroup] {
    var correlated: [CorrelationKey: [HIDCollectionRecord]] = [:]
    var order: [CorrelationKey] = []
    var uncorrelated: [(Int, HIDCollectionRecord)] = []

    for (ordinal, collection) in collections.enumerated() {
      guard let key = correlationKey(for: collection) else {
        uncorrelated.append((ordinal, collection))
        continue
      }

      if correlated[key] == nil {
        order.append(key)
      }
      correlated[key, default: []].append(collection)
    }

    let grouped = order.compactMap { key -> HIDPhysicalDeviceGroup? in
      guard let records = correlated[key], let first = records.first else {
        return nil
      }
      return HIDPhysicalDeviceGroup(
        identifier: identifier(for: key, fallback: first),
        collections: records
      )
    }

    let unresolved = uncorrelated.map { ordinal, collection in
      HIDPhysicalDeviceGroup(
        identifier: HIDPhysicalDeviceIdentifier(
          basis: .uncorrelated,
          vendorID: collection.vendorID,
          productID: collection.productID,
          uncorrelatedOrdinal: ordinal
        ),
        collections: [collection]
      )
    }

    return (grouped + unresolved).sorted(by: groupOrder)
  }

  fileprivate static func collectionOrder(
    _ lhs: HIDCollectionRecord,
    _ rhs: HIDCollectionRecord
  ) -> Bool {
    collectionSortKey(lhs) < collectionSortKey(rhs)
  }

  fileprivate static func candidateOrder(
    _ lhs: HIDCollectionRecord,
    _ rhs: HIDCollectionRecord
  ) -> Bool {
    candidateSortKey(lhs) < candidateSortKey(rhs)
  }

  private enum CorrelationKey: Hashable {
    case location(vendorID: UInt64, productID: UInt64, locationID: UInt64)
    case serial(vendorID: UInt64, productID: UInt64, serialNumber: String)
  }

  private static func correlationKey(for record: HIDCollectionRecord) -> CorrelationKey? {
    if let locationID = record.locationID {
      return .location(
        vendorID: record.vendorID,
        productID: record.productID,
        locationID: locationID
      )
    }

    if let serialNumber = normalizedSerialNumber(record.serialNumber) {
      return .serial(
        vendorID: record.vendorID,
        productID: record.productID,
        serialNumber: serialNumber
      )
    }

    return nil
  }

  private static func identifier(
    for key: CorrelationKey,
    fallback: HIDCollectionRecord
  ) -> HIDPhysicalDeviceIdentifier {
    switch key {
    case .location(let vendorID, let productID, let locationID):
      return HIDPhysicalDeviceIdentifier(
        basis: .location,
        vendorID: vendorID,
        productID: productID,
        locationID: locationID,
        serialNumber: normalizedSerialNumber(fallback.serialNumber)
      )
    case .serial(let vendorID, let productID, let serialNumber):
      return HIDPhysicalDeviceIdentifier(
        basis: .serialNumber,
        vendorID: vendorID,
        productID: productID,
        serialNumber: serialNumber
      )
    }
  }

  private static func normalizedSerialNumber(_ serialNumber: String?) -> String? {
    guard let value = serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private static func collectionSortKey(
    _ record: HIDCollectionRecord
  ) -> (UInt64, UInt64, UInt64, UInt64, UInt64, String) {
    (
      rolePriority(record.role),
      record.usagePage ?? UInt64.max,
      record.usage ?? UInt64.max,
      record.maxFeatureReportSize ?? UInt64.max,
      record.maxOutputReportSize ?? UInt64.max,
      record.product ?? ""
    )
  }

  private static func candidateSortKey(
    _ record: HIDCollectionRecord
  ) -> (UInt64, UInt64, UInt64, UInt64, String) {
    (
      record.maxInputReportSize ?? UInt64.max,
      record.usagePage ?? UInt64.max,
      record.usage ?? UInt64.max,
      record.locationID ?? UInt64.max,
      record.product ?? ""
    )
  }

  private static func rolePriority(_ role: HIDRole) -> UInt64 {
    switch role {
    case .vendorFeature64: return 0
    case .vendorOutput4096: return 1
    case .keyboard: return 2
    case .consumer: return 3
    case .unknown: return 4
    }
  }

  private static func groupOrder(
    _ lhs: HIDPhysicalDeviceGroup,
    _ rhs: HIDPhysicalDeviceGroup
  ) -> Bool {
    groupSortKey(lhs.identifier) < groupSortKey(rhs.identifier)
  }

  private static func groupSortKey(
    _ identifier: HIDPhysicalDeviceIdentifier
  ) -> (UInt64, UInt64, UInt64, String, Int) {
    (
      identifier.vendorID,
      identifier.productID,
      identifier.locationID ?? UInt64.max,
      identifier.serialNumber ?? "",
      identifier.uncorrelatedOrdinal ?? -1
    )
  }
}
