import Foundation

/// A standard CRC-16/CCITT-FALSE implementation used by the neutral frame models.
/// It is intentionally independent of any device-specific wire protocol.
public enum FrameChecksum {
  public static func crc16CCITT<S: Sequence>(_ bytes: S) -> UInt16
  where S.Element == UInt8 {
    var crc: UInt16 = 0xFFFF
    for byte in bytes {
      crc ^= UInt16(byte) << 8
      for _ in 0..<8 {
        if crc & 0x8000 != 0 {
          crc = (crc << 1) ^ 0x1021
        } else {
          crc <<= 1
        }
      }
    }
    return crc
  }
}

public enum HIDFrameCodecError: Error, Equatable, LocalizedError, Sendable {
  case invalidFrameLength(expected: Int, actual: Int)
  case payloadTooLarge(maximum: Int, actual: Int)
  case invalidPayloadLength(Int)
  case invalidFragment(index: UInt8, count: UInt8)
  case nonZeroReservedByte(offset: Int)
  case nonZeroPadding(offset: Int)
  case checksumMismatch(expected: UInt16, actual: UInt16)

  public var errorDescription: String? {
    switch self {
    case .invalidFrameLength(let expected, let actual):
      return "invalid frame length; expected \(expected), got \(actual)"
    case .payloadTooLarge(let maximum, let actual):
      return "payload is too large; maximum \(maximum), got \(actual)"
    case .invalidPayloadLength(let length):
      return "encoded payload length is invalid: \(length)"
    case .invalidFragment(let index, let count):
      return "invalid fragment index/count: \(index)/\(count)"
    case .nonZeroReservedByte(let offset):
      return "reserved frame byte at offset \(offset) is not zero"
    case .nonZeroPadding(let offset):
      return "frame padding at offset \(offset) is not zero"
    case .checksumMismatch(let expected, let actual):
      return String(
        format: "frame checksum mismatch; expected 0x%04X, got 0x%04X",
        expected,
        actual
      )
    }
  }
}

public struct FeatureReportFrame: Equatable, Sendable {
  public static let byteCount = 64
  public static let maximumPayloadSize = 54

  public let reportID: UInt8
  public let protocolVersion: UInt8
  public let messageType: UInt8
  public let flags: UInt8
  public let sequence: UInt16
  public let payload: [UInt8]

  public init(
    reportID: UInt8,
    protocolVersion: UInt8,
    messageType: UInt8,
    flags: UInt8 = 0,
    sequence: UInt16,
    payload: [UInt8]
  ) throws {
    guard payload.count <= Self.maximumPayloadSize else {
      throw HIDFrameCodecError.payloadTooLarge(
        maximum: Self.maximumPayloadSize,
        actual: payload.count
      )
    }
    self.reportID = reportID
    self.protocolVersion = protocolVersion
    self.messageType = messageType
    self.flags = flags
    self.sequence = sequence
    self.payload = payload
  }
}

public enum FeatureReportCodec {
  private static let payloadOffset = 8
  private static let checksumOffset = FeatureReportFrame.byteCount - 2

  public static func encode(_ frame: FeatureReportFrame) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: FeatureReportFrame.byteCount)
    bytes[0] = frame.reportID
    bytes[1] = frame.protocolVersion
    bytes[2] = frame.messageType
    bytes[3] = frame.flags
    writeLittleEndian(frame.sequence, to: &bytes, at: 4)
    bytes[6] = UInt8(frame.payload.count)
    bytes[7] = 0
    bytes.replaceSubrange(
      payloadOffset..<(payloadOffset + frame.payload.count),
      with: frame.payload
    )

    let checksum = FrameChecksum.crc16CCITT(bytes[..<checksumOffset])
    writeLittleEndian(checksum, to: &bytes, at: checksumOffset)
    return bytes
  }

  public static func decode(_ bytes: [UInt8]) throws -> FeatureReportFrame {
    guard bytes.count == FeatureReportFrame.byteCount else {
      throw HIDFrameCodecError.invalidFrameLength(
        expected: FeatureReportFrame.byteCount,
        actual: bytes.count
      )
    }
    guard bytes[7] == 0 else {
      throw HIDFrameCodecError.nonZeroReservedByte(offset: 7)
    }

    let payloadLength = Int(bytes[6])
    guard payloadLength <= FeatureReportFrame.maximumPayloadSize else {
      throw HIDFrameCodecError.invalidPayloadLength(payloadLength)
    }
    try validatePadding(
      bytes,
      from: payloadOffset + payloadLength,
      to: checksumOffset
    )
    try validateChecksum(bytes, checksumOffset: checksumOffset)

    return try FeatureReportFrame(
      reportID: bytes[0],
      protocolVersion: bytes[1],
      messageType: bytes[2],
      flags: bytes[3],
      sequence: readLittleEndian(bytes, at: 4),
      payload: Array(bytes[payloadOffset..<(payloadOffset + payloadLength)])
    )
  }
}

public struct InterruptReportFrame: Equatable, Sendable {
  public static let byteCount = 32
  public static let maximumPayloadSize = 21

  public let reportID: UInt8
  public let protocolVersion: UInt8
  public let messageType: UInt8
  public let flags: UInt8
  public let sequence: UInt16
  public let fragmentIndex: UInt8
  public let fragmentCount: UInt8
  public let payload: [UInt8]

  public init(
    reportID: UInt8,
    protocolVersion: UInt8,
    messageType: UInt8,
    flags: UInt8 = 0,
    sequence: UInt16,
    fragmentIndex: UInt8 = 0,
    fragmentCount: UInt8 = 1,
    payload: [UInt8]
  ) throws {
    guard payload.count <= Self.maximumPayloadSize else {
      throw HIDFrameCodecError.payloadTooLarge(
        maximum: Self.maximumPayloadSize,
        actual: payload.count
      )
    }
    guard fragmentCount > 0, fragmentIndex < fragmentCount else {
      throw HIDFrameCodecError.invalidFragment(
        index: fragmentIndex,
        count: fragmentCount
      )
    }
    self.reportID = reportID
    self.protocolVersion = protocolVersion
    self.messageType = messageType
    self.flags = flags
    self.sequence = sequence
    self.fragmentIndex = fragmentIndex
    self.fragmentCount = fragmentCount
    self.payload = payload
  }
}

public enum InterruptReportCodec {
  private static let payloadOffset = 9
  private static let checksumOffset = InterruptReportFrame.byteCount - 2

  public static func encode(_ frame: InterruptReportFrame) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: InterruptReportFrame.byteCount)
    bytes[0] = frame.reportID
    bytes[1] = frame.protocolVersion
    bytes[2] = frame.messageType
    bytes[3] = frame.flags
    writeLittleEndian(frame.sequence, to: &bytes, at: 4)
    bytes[6] = frame.fragmentIndex
    bytes[7] = frame.fragmentCount
    bytes[8] = UInt8(frame.payload.count)
    bytes.replaceSubrange(
      payloadOffset..<(payloadOffset + frame.payload.count),
      with: frame.payload
    )

    let checksum = FrameChecksum.crc16CCITT(bytes[..<checksumOffset])
    writeLittleEndian(checksum, to: &bytes, at: checksumOffset)
    return bytes
  }

  public static func decode(_ bytes: [UInt8]) throws -> InterruptReportFrame {
    guard bytes.count == InterruptReportFrame.byteCount else {
      throw HIDFrameCodecError.invalidFrameLength(
        expected: InterruptReportFrame.byteCount,
        actual: bytes.count
      )
    }

    let payloadLength = Int(bytes[8])
    guard payloadLength <= InterruptReportFrame.maximumPayloadSize else {
      throw HIDFrameCodecError.invalidPayloadLength(payloadLength)
    }
    let fragmentIndex = bytes[6]
    let fragmentCount = bytes[7]
    guard fragmentCount > 0, fragmentIndex < fragmentCount else {
      throw HIDFrameCodecError.invalidFragment(
        index: fragmentIndex,
        count: fragmentCount
      )
    }
    try validatePadding(
      bytes,
      from: payloadOffset + payloadLength,
      to: checksumOffset
    )
    try validateChecksum(bytes, checksumOffset: checksumOffset)

    return try InterruptReportFrame(
      reportID: bytes[0],
      protocolVersion: bytes[1],
      messageType: bytes[2],
      flags: bytes[3],
      sequence: readLittleEndian(bytes, at: 4),
      fragmentIndex: fragmentIndex,
      fragmentCount: fragmentCount,
      payload: Array(bytes[payloadOffset..<(payloadOffset + payloadLength)])
    )
  }
}

private func writeLittleEndian(_ value: UInt16, to bytes: inout [UInt8], at offset: Int) {
  bytes[offset] = UInt8(truncatingIfNeeded: value)
  bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
}

private func readLittleEndian(_ bytes: [UInt8], at offset: Int) -> UInt16 {
  UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

private func validatePadding(_ bytes: [UInt8], from start: Int, to end: Int) throws {
  guard start < end else { return }
  if let offset = bytes[start..<end].firstIndex(where: { $0 != 0 }) {
    throw HIDFrameCodecError.nonZeroPadding(offset: offset)
  }
}

private func validateChecksum(_ bytes: [UInt8], checksumOffset: Int) throws {
  let expected = FrameChecksum.crc16CCITT(bytes[..<checksumOffset])
  let actual = readLittleEndian(bytes, at: checksumOffset)
  guard expected == actual else {
    throw HIDFrameCodecError.checksumMismatch(expected: expected, actual: actual)
  }
}
