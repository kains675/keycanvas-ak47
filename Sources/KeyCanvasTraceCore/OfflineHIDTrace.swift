import Foundation

public enum OfflineHIDTraceDirection: String, Codable, CaseIterable, Equatable, Sendable {
  case hostToDevice = "host-to-device"
  case deviceToHost = "device-to-host"
}

public enum OfflineHIDTransferKind: String, Codable, CaseIterable, Equatable, Sendable {
  case control
  case interrupt
  case bulk
}

enum OfflineHIDTraceOrigin: String, Decodable, Equatable, Sendable {
  case synthetic
  case authorizedPrivateObservation = "authorized-private-observation"
}

struct OfflineHIDTraceProvenance: Decodable, Equatable, Sendable {
  let origin: OfflineHIDTraceOrigin
  let authorizedUse: Bool
  let identifiersRemoved: Bool
  let absoluteTimestampsRemoved: Bool
  let firmwareTrafficExcluded: Bool

  init(
    origin: OfflineHIDTraceOrigin,
    authorizedUse: Bool,
    identifiersRemoved: Bool,
    absoluteTimestampsRemoved: Bool,
    firmwareTrafficExcluded: Bool
  ) {
    self.origin = origin
    self.authorizedUse = authorizedUse
    self.identifiersRemoved = identifiersRemoved
    self.absoluteTimestampsRemoved = absoluteTimestampsRemoved
    self.firmwareTrafficExcluded = firmwareTrafficExcluded
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case origin
    case authorizedUse
    case identifiersRemoved
    case absoluteTimestampsRemoved
    case firmwareTrafficExcluded
  }

  init(from decoder: Decoder) throws {
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      origin: try container.decode(OfflineHIDTraceOrigin.self, forKey: .origin),
      authorizedUse: try container.decode(Bool.self, forKey: .authorizedUse),
      identifiersRemoved: try container.decode(Bool.self, forKey: .identifiersRemoved),
      absoluteTimestampsRemoved: try container.decode(
        Bool.self, forKey: .absoluteTimestampsRemoved),
      firmwareTrafficExcluded: try container.decode(Bool.self, forKey: .firmwareTrafficExcluded)
    )
  }
}

/// One observed transfer from an offline trace file.
///
/// This type is input-only and intentionally has no conversion to an executable
/// transport request.
struct OfflineHIDTraceEvent: Decodable, Equatable, Sendable {
  let index: Int
  let offsetMicros: UInt64?
  let direction: OfflineHIDTraceDirection
  let transfer: OfflineHIDTransferKind
  let reportID: UInt8
  let bytes: [UInt8]

  init(
    index: Int,
    offsetMicros: UInt64? = nil,
    direction: OfflineHIDTraceDirection,
    transfer: OfflineHIDTransferKind,
    reportID: UInt8,
    bytes: [UInt8]
  ) {
    self.index = index
    self.offsetMicros = offsetMicros
    self.direction = direction
    self.transfer = transfer
    self.reportID = reportID
    self.bytes = bytes
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case index
    case offsetMicros
    case direction
    case transfer
    case reportID
    case bytesHex
  }

  init(from decoder: Decoder) throws {
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let index = try container.decode(Int.self, forKey: .index)
    let encodedBytes = try container.decode(String.self, forKey: .bytesHex)
    self.init(
      index: index,
      offsetMicros: try container.decodeIfPresent(UInt64.self, forKey: .offsetMicros),
      direction: try container.decode(OfflineHIDTraceDirection.self, forKey: .direction),
      transfer: try container.decode(OfflineHIDTransferKind.self, forKey: .transfer),
      reportID: try container.decode(UInt8.self, forKey: .reportID),
      bytes: try OfflineHIDHex.decode(encodedBytes, eventIndex: index)
    )
  }
}

/// A strictly validated, input-only offline observation.
///
/// Public construction is intentionally limited to `Decodable` so callers cannot
/// bypass provenance and sequence checks with a programmatic initializer.
public struct OfflineHIDTrace: Decodable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let label: String
  let provenance: OfflineHIDTraceProvenance
  let events: [OfflineHIDTraceEvent]

  init(
    schemaVersion: Int = OfflineHIDTrace.currentSchemaVersion,
    label: String,
    provenance: OfflineHIDTraceProvenance,
    events: [OfflineHIDTraceEvent]
  ) {
    self.schemaVersion = schemaVersion
    self.label = label
    self.provenance = provenance
    self.events = events
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case label
    case provenance
    case events
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let trace = OfflineHIDTrace(
      schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
      label: try container.decode(String.self, forKey: .label),
      provenance: try container.decode(OfflineHIDTraceProvenance.self, forKey: .provenance),
      events: try container.decode([OfflineHIDTraceEvent].self, forKey: .events)
    )
    try OfflineHIDTraceValidator.validate(trace)
    self = trace
  }
}

public enum OfflineHIDTraceError: Error, Equatable, LocalizedError, Sendable {
  case documentTooLarge(maximum: Int, actual: Int)
  case unsupportedSchemaVersion(Int)
  case invalidLabel(String)
  case unsafeProvenance(field: String)
  case tooManyEvents(maximum: Int, actual: Int)
  case nonSequentialIndex(expected: Int, actual: Int)
  case firstTimestampMustBeZero(actual: UInt64)
  case timestampOutOfRange(index: Int, maximum: UInt64, actual: UInt64)
  case nonMonotonicTimestamp(index: Int, previous: UInt64, actual: UInt64)
  case payloadTooLarge(index: Int, maximum: Int, actual: Int)
  case totalPayloadTooLarge(maximum: Int, actual: Int)
  case invalidHex(index: Int, reason: String)

  public var errorDescription: String? {
    switch self {
    case .documentTooLarge(let maximum, let actual):
      return "trace document is too large; maximum \(maximum) bytes, got \(actual)"
    case .unsupportedSchemaVersion(let version):
      return "unsupported offline trace schema version: \(version)"
    case .invalidLabel(let reason):
      return "invalid offline trace label: \(reason)"
    case .unsafeProvenance(let field):
      return "offline trace provenance requires \(field) to be true"
    case .tooManyEvents(let maximum, let actual):
      return "too many trace events; maximum \(maximum), got \(actual)"
    case .nonSequentialIndex(let expected, let actual):
      return "trace event index is not sequential; expected \(expected), got \(actual)"
    case .firstTimestampMustBeZero(let actual):
      return "the first present trace timestamp must be zero; got \(actual)"
    case .timestampOutOfRange(let index, let maximum, let actual):
      return "trace timestamp at event \(index) exceeds \(maximum); got \(actual)"
    case .nonMonotonicTimestamp(let index, let previous, let actual):
      return
        "trace timestamp decreased at event \(index); previous \(previous), got \(actual)"
    case .payloadTooLarge(let index, let maximum, let actual):
      return
        "trace event \(index) payload is too large; maximum \(maximum), got \(actual)"
    case .totalPayloadTooLarge(let maximum, let actual):
      return "trace payload total is too large; maximum \(maximum), got \(actual)"
    case .invalidHex(let index, let reason):
      return "trace event \(index) has invalid bytesHex: \(reason)"
    }
  }
}

enum OfflineHIDTraceValidator {
  static let maximumDocumentBytes = 2 * 1_024 * 1_024
  static let maximumLabelBytes = 128
  static let maximumEventCount = 10_000
  static let maximumPayloadBytes = 4_096
  static let maximumTotalPayloadBytes = 2 * 1_024 * 1_024
  static let maximumOffsetMicros: UInt64 = 3_600_000_000

  static func validate(_ trace: OfflineHIDTrace) throws {
    guard trace.schemaVersion == OfflineHIDTrace.currentSchemaVersion else {
      throw OfflineHIDTraceError.unsupportedSchemaVersion(trace.schemaVersion)
    }

    let trimmedLabel = trace.label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedLabel.isEmpty else {
      throw OfflineHIDTraceError.invalidLabel("label must not be empty")
    }
    guard trace.label.utf8.count <= maximumLabelBytes else {
      throw OfflineHIDTraceError.invalidLabel(
        "label must be at most \(maximumLabelBytes) UTF-8 bytes"
      )
    }
    guard !trace.label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw OfflineHIDTraceError.invalidLabel("control characters are not allowed")
    }

    for (field, value) in [
      ("authorizedUse", trace.provenance.authorizedUse),
      ("identifiersRemoved", trace.provenance.identifiersRemoved),
      ("absoluteTimestampsRemoved", trace.provenance.absoluteTimestampsRemoved),
      ("firmwareTrafficExcluded", trace.provenance.firmwareTrafficExcluded),
    ] where !value {
      throw OfflineHIDTraceError.unsafeProvenance(field: field)
    }

    guard trace.events.count <= maximumEventCount else {
      throw OfflineHIDTraceError.tooManyEvents(
        maximum: maximumEventCount,
        actual: trace.events.count
      )
    }

    var previousTimestamp: UInt64?
    var hasTimestamp = false
    var totalPayloadBytes = 0
    for (expectedIndex, event) in trace.events.enumerated() {
      guard event.index == expectedIndex else {
        throw OfflineHIDTraceError.nonSequentialIndex(
          expected: expectedIndex,
          actual: event.index
        )
      }
      guard event.bytes.count <= maximumPayloadBytes else {
        throw OfflineHIDTraceError.payloadTooLarge(
          index: event.index,
          maximum: maximumPayloadBytes,
          actual: event.bytes.count
        )
      }

      totalPayloadBytes += event.bytes.count
      guard totalPayloadBytes <= maximumTotalPayloadBytes else {
        throw OfflineHIDTraceError.totalPayloadTooLarge(
          maximum: maximumTotalPayloadBytes,
          actual: totalPayloadBytes
        )
      }

      if let timestamp = event.offsetMicros {
        if !hasTimestamp {
          guard timestamp == 0 else {
            throw OfflineHIDTraceError.firstTimestampMustBeZero(actual: timestamp)
          }
          hasTimestamp = true
        }
        guard timestamp <= maximumOffsetMicros else {
          throw OfflineHIDTraceError.timestampOutOfRange(
            index: event.index,
            maximum: maximumOffsetMicros,
            actual: timestamp
          )
        }
        if let previousTimestamp, timestamp < previousTimestamp {
          throw OfflineHIDTraceError.nonMonotonicTimestamp(
            index: event.index,
            previous: previousTimestamp,
            actual: timestamp
          )
        }
        previousTimestamp = timestamp
      }
    }
  }
}

private enum OfflineHIDHex {
  static func decode(_ value: String, eventIndex: Int) throws -> [UInt8] {
    let encoded = Array(value.utf8)
    guard encoded.count <= OfflineHIDTraceValidator.maximumPayloadBytes * 2 else {
      throw OfflineHIDTraceError.payloadTooLarge(
        index: eventIndex,
        maximum: OfflineHIDTraceValidator.maximumPayloadBytes,
        actual: encoded.count / 2
      )
    }
    guard encoded.count.isMultiple(of: 2) else {
      throw OfflineHIDTraceError.invalidHex(
        index: eventIndex,
        reason: "hex text must contain an even number of characters"
      )
    }

    var decoded: [UInt8] = []
    decoded.reserveCapacity(encoded.count / 2)
    for offset in stride(from: 0, to: encoded.count, by: 2) {
      guard let high = nibble(encoded[offset]), let low = nibble(encoded[offset + 1]) else {
        throw OfflineHIDTraceError.invalidHex(
          index: eventIndex,
          reason: "only lowercase ASCII hexadecimal characters are allowed"
        )
      }
      decoded.append((high << 4) | low)
    }
    return decoded
  }

  private static func nibble(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: return byte - 48
    case 97...102: return byte - 97 + 10
    default: return nil
    }
  }
}

private struct OfflineHIDAnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
  let container = try decoder.container(keyedBy: OfflineHIDAnyCodingKey.self)
  let allowedKeys = Set(allowed)
  let unknownKeys = container.allKeys.map(\.stringValue).filter { !allowedKeys.contains($0) }
  guard unknownKeys.isEmpty else {
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: decoder.codingPath,
        debugDescription: "unknown key(s): \(unknownKeys.sorted().joined(separator: ", "))"
      )
    )
  }
}
