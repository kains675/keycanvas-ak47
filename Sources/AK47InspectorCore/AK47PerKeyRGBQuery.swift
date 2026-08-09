import Foundation

public struct AK47PerKeyRGBValue: Equatable, Sendable {
  public let lightIndex: Int
  public let color: RGBColor

  public init(lightIndex: Int, color: RGBColor) {
    self.lightIndex = lightIndex
    self.color = color
  }
}

public struct AK47PerKeyRGBSnapshot: Equatable, Sendable {
  public let values: [AK47PerKeyRGBValue]

  public init(values: [AK47PerKeyRGBValue]) {
    self.values = values
  }

  public var nonzeroColorCount: Int {
    values.count { value in
      value.color.red != 0 || value.color.green != 0 || value.color.blue != 0
    }
  }

  public var distinctColorCount: Int {
    Set(values.map { "\($0.color.red):\($0.color.green):\($0.color.blue)" }).count
  }
}

public enum AK47PerKeyRGBQueryError: Error, Equatable, LocalizedError, Sendable {
  case invalidAcknowledgementLength(expected: Int, actual: Int)
  case acknowledgementRejected
  case invalidPacketCount(expected: Int, actual: Int)
  case invalidPacketLength(packet: Int, expected: Int, actual: Int)
  case invalidSlotIndex(lightIndex: Int, observed: UInt8)

  public var errorDescription: String? {
    switch self {
    case .invalidAcknowledgementLength(let expected, let actual):
      "RGB query acknowledgement length mismatch; expected \(expected), received \(actual)"
    case .acknowledgementRejected:
      "the keyboard rejected the RGB query acknowledgement"
    case .invalidPacketCount(let expected, let actual):
      "RGB query packet count mismatch; expected \(expected), received \(actual)"
    case .invalidPacketLength(let packet, let expected, let actual):
      "RGB packet \(packet) length mismatch; expected \(expected), received \(actual)"
    case .invalidSlotIndex(let lightIndex, let observed):
      "RGB slot \(lightIndex) reported unexpected index \(observed)"
    }
  }
}

public enum AK47PerKeyRGBQueryProtocol {
  public static let reportID: UInt8 = 0
  public static let reportLength = 64
  public static let responsePacketCount = 9
  public static let queryCommand: UInt8 = 0xF5
  public static let finishCommand: UInt8 = 0x02

  public static let lightIndices: [Int] =
    Array(1...13)
    + Array(19...31)
    + Array(37...49)
    + Array(55...67)
    + Array(73...85)
    + Array(91...103)
    + Array(116...121)

  public static var queryPayload: [UInt8] {
    var bytes = [UInt8](repeating: 0, count: reportLength)
    bytes[0] = 0x04
    bytes[1] = queryCommand
    bytes[8] = UInt8(responsePacketCount)
    return bytes
  }

  public static var finishPayload: [UInt8] {
    var bytes = [UInt8](repeating: 0, count: reportLength)
    bytes[0] = 0x04
    bytes[1] = finishCommand
    return bytes
  }

  public static func validateAcknowledgement(_ bytes: [UInt8]) throws {
    guard bytes.count == reportLength else {
      throw AK47PerKeyRGBQueryError.invalidAcknowledgementLength(
        expected: reportLength,
        actual: bytes.count
      )
    }
    guard bytes[3] == 0x01 else {
      throw AK47PerKeyRGBQueryError.acknowledgementRejected
    }
  }

  public static func parse(responsePackets: [[UInt8]]) throws -> AK47PerKeyRGBSnapshot {
    guard responsePackets.count == responsePacketCount else {
      throw AK47PerKeyRGBQueryError.invalidPacketCount(
        expected: responsePacketCount,
        actual: responsePackets.count
      )
    }
    for (packet, bytes) in responsePackets.enumerated() where bytes.count != reportLength {
      throw AK47PerKeyRGBQueryError.invalidPacketLength(
        packet: packet,
        expected: reportLength,
        actual: bytes.count
      )
    }

    let combined = responsePackets.flatMap { $0 }
    let values = try lightIndices.map { lightIndex in
      let offset = lightIndex * 4
      let observedIndex = combined[offset]
      guard observedIndex == 0 || Int(observedIndex) == lightIndex else {
        throw AK47PerKeyRGBQueryError.invalidSlotIndex(
          lightIndex: lightIndex,
          observed: observedIndex
        )
      }
      return AK47PerKeyRGBValue(
        lightIndex: lightIndex,
        color: RGBColor(
          red: combined[offset + 1],
          green: combined[offset + 2],
          blue: combined[offset + 3]
        )
      )
    }
    return AK47PerKeyRGBSnapshot(values: values)
  }
}
