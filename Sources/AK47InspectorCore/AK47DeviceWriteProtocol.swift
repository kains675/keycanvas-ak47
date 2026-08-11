import Foundation

public struct AK47WiredDeviceTarget: Equatable, Sendable {
  public let product: String
  public let locationID: UInt64
  public let versionNumber: UInt64
  public let serialNumber: String?

  public init(
    product: String = "Archon AK47",
    locationID: UInt64,
    versionNumber: UInt64,
    serialNumber: String? = nil
  ) {
    self.product = product
    self.locationID = locationID
    self.versionNumber = versionNumber
    self.serialNumber = serialNumber
  }

  public func validate() throws {
    guard product == "Archon AK47" else {
      throw AK47DeviceWriteError.invalidTarget("unexpected product name")
    }
    guard locationID <= UInt64(UInt32.max) else {
      throw AK47DeviceWriteError.invalidTarget("location ID is out of range")
    }
    guard versionNumber == 0x0115 else {
      throw AK47DeviceWriteError.invalidTarget(
        "only the verified USB revision 0x0115 is enabled"
      )
    }
    if let serialNumber {
      guard !serialNumber.isEmpty, serialNumber.utf8.count <= 256 else {
        throw AK47DeviceWriteError.invalidTarget("serial number is empty or too long")
      }
    }
  }
}

public struct AK47ClockSyncValue: Equatable, Sendable {
  /// One-based `LCDViewList` selection used by the Windows utility.
  public let lcdItemNumber: UInt8
  public let year: Int
  public let month: Int
  public let day: Int
  public let hour: Int
  public let minute: Int
  public let second: Int
  /// Sunday is 0 and Saturday is 6, matching the AK47 Windows utility.
  public let weekday: Int

  public init(
    lcdItemNumber: UInt8 = 1,
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    weekday: Int
  ) {
    self.lcdItemNumber = lcdItemNumber
    self.year = year
    self.month = month
    self.day = day
    self.hour = hour
    self.minute = minute
    self.second = second
    self.weekday = weekday
  }

  public init(date: Date, lcdItemNumber: UInt8 = 1, calendar: Calendar = .current) throws {
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second, .weekday],
      from: date
    )
    guard let year = components.year,
      let month = components.month,
      let day = components.day,
      let hour = components.hour,
      let minute = components.minute,
      let second = components.second,
      let calendarWeekday = components.weekday
    else {
      throw AK47DeviceWriteError.invalidClock("calendar components are incomplete")
    }
    self.init(
      lcdItemNumber: lcdItemNumber,
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      weekday: calendarWeekday - 1
    )
    try validate()
  }

  public func validate() throws {
    guard (1...4).contains(lcdItemNumber) else {
      throw AK47DeviceWriteError.invalidClock("LCD item number must be 1...4")
    }
    guard (2000...2255).contains(year) else {
      throw AK47DeviceWriteError.invalidClock("year must be 2000...2255")
    }
    guard (1...12).contains(month) else {
      throw AK47DeviceWriteError.invalidClock("month must be 1...12")
    }
    guard (1...31).contains(day) else {
      throw AK47DeviceWriteError.invalidClock("day must be 1...31")
    }
    guard (0...23).contains(hour) else {
      throw AK47DeviceWriteError.invalidClock("hour must be 0...23")
    }
    guard (0...59).contains(minute), (0...59).contains(second) else {
      throw AK47DeviceWriteError.invalidClock("minute and second must be 0...59")
    }
    guard (0...6).contains(weekday) else {
      throw AK47DeviceWriteError.invalidClock("weekday must be 0...6")
    }
  }
}

public struct AK47OnboardLightingValue: Equatable, Sendable {
  public let mode: UInt8
  public let color: RGBColor
  public let colorful: Bool
  public let brightness: UInt8
  public let speed: UInt8
  public let direction: UInt8

  public init(
    mode: UInt8,
    color: RGBColor,
    colorful: Bool,
    brightness: UInt8,
    speed: UInt8,
    direction: UInt8
  ) {
    self.mode = mode
    self.color = color
    self.colorful = colorful
    self.brightness = brightness
    self.speed = speed
    self.direction = direction
  }

  public func validate() throws {
    guard mode <= 19 else {
      throw AK47DeviceWriteError.invalidLighting("mode must be 0...19")
    }
    guard (1...5).contains(brightness) else {
      throw AK47DeviceWriteError.invalidLighting("brightness must be 1...5")
    }
    guard (1...5).contains(speed) else {
      throw AK47DeviceWriteError.invalidLighting("speed must be 1...5")
    }
    guard direction <= 1 else {
      throw AK47DeviceWriteError.invalidLighting("direction must be 0 or 1")
    }
  }
}

public enum AK47DeviceWriteKind: String, Equatable, Sendable {
  case clockSync
  case onboardLighting
  case perKeyRGB
}

/// A typed record that the caller showed an operation-specific warning and
/// received an explicit user action. It cannot authorize a different write kind.
public final class AK47DeviceWriteAuthorization: @unchecked Sendable {
  package let kind: AK47DeviceWriteKind
  private let lock = NSLock()
  private var consumed = false

  package init(explicitlyConfirming kind: AK47DeviceWriteKind) {
    self.kind = kind
  }

  package func consume(for expected: AK47DeviceWriteKind) throws {
    lock.lock()
    defer { lock.unlock() }
    guard kind == expected else {
      throw AK47DeviceWriteError.authorizationMismatch(expected: expected, actual: kind)
    }
    guard !consumed else {
      throw AK47DeviceWriteError.authorizationAlreadyConsumed(kind)
    }
    consumed = true
  }
}

public enum AK47DeviceWriteStage: Equatable, Sendable {
  case begin
  case selectClock
  case clockData
  case selectOnboardLighting
  case onboardLightingData
  case selectPerKeyRGB
  case perKeyRGBData(Int)
  case commit
  case finalize

  var description: String {
    switch self {
    case .begin: "begin"
    case .selectClock: "clock selector"
    case .clockData: "clock data"
    case .selectOnboardLighting: "lighting selector"
    case .onboardLightingData: "lighting data"
    case .selectPerKeyRGB: "per-key RGB selector"
    case .perKeyRGBData(let packet): "per-key RGB packet \(packet)"
    case .commit: "commit"
    case .finalize: "finalize"
    }
  }
}

public enum AK47DeviceWriteError: Error, Equatable, LocalizedError, Sendable {
  case invalidTarget(String)
  case invalidClock(String)
  case invalidLighting(String)
  case invalidPerKeyRGB(String)
  case authorizationMismatch(expected: AK47DeviceWriteKind, actual: AK47DeviceWriteKind)
  case authorizationAlreadyConsumed(AK47DeviceWriteKind)
  case noMatchingCollection
  case ambiguousCollections(Int)
  case unexpectedTopology(collections: Int)
  case deviceBusy
  case operationGatePoisoned
  case partialTransactionQuarantined(String)
  case quarantinePersistenceFailed
  case openFailed(UInt32)
  case sessionCancellationTimedOut
  case postflightIdentityLost
  case operationFailed(stage: AK47DeviceWriteStage, code: UInt32)
  case operationTimedOut(stage: AK47DeviceWriteStage)
  case acknowledgementRejected(stage: AK47DeviceWriteStage)
  case invalidReportLength(stage: AK47DeviceWriteStage, expected: Int, actual: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidTarget(let reason): "invalid AK47 target: \(reason)"
    case .invalidClock(let reason): "invalid AK47 clock value: \(reason)"
    case .invalidLighting(let reason): "invalid AK47 lighting value: \(reason)"
    case .invalidPerKeyRGB(let reason): "invalid AK47 per-key RGB value: \(reason)"
    case .authorizationMismatch(let expected, let actual):
      "AK47 \(actual.rawValue) authorization cannot run \(expected.rawValue)"
    case .authorizationAlreadyConsumed(let kind):
      "AK47 \(kind.rawValue) authorization was already consumed"
    case .noMatchingCollection: "the exact AK47 command collection was not found"
    case .ambiguousCollections(let count):
      "refusing the write because \(count) command collections match"
    case .unexpectedTopology(let collections):
      "refusing the write because the wired AK47 exposes \(collections) unexpected HID collections"
    case .deviceBusy: "another AK47 HID operation is already in progress"
    case .operationGatePoisoned:
      "AK47 HID operations are quarantined. Keep the selector in USB mode, disconnect the cable until the device is unpowered, refresh Device Inspector while it is absent, then reconnect at the original USB location and refresh again. Relaunching or switching to 2.4G/Bluetooth does not clear the quarantine."
    case .partialTransactionQuarantined(let cause):
      "AK47 transaction state is uncertain after report submission (\(cause)). Keep the selector in USB mode, disconnect the cable until the device is unpowered, refresh Device Inspector while it is absent, then reconnect at the original USB location and refresh again. Relaunching alone does not clear the quarantine, and switching to 2.4G/Bluetooth is not recovery."
    case .quarantinePersistenceFailed:
      "KeyCanvas could not durably record the AK47 transaction marker, so no report was submitted. HID operations remain blocked in this process."
    case .openFailed(let code):
      String(format: "opening the AK47 command collection failed (0x%08X)", code)
    case .sessionCancellationTimedOut:
      "AK47 HID cancellation was not confirmed within 500 ms. Keep the selector in USB mode, disconnect the cable until the device is unpowered, refresh Device Inspector while it is absent, then reconnect at the original USB location and refresh again."
    case .postflightIdentityLost:
      "the exact AK47 identity or four-collection topology was not present after the write"
    case .operationFailed(let stage, let code):
      String(format: "AK47 %@ failed (0x%08X)", stage.description, code)
    case .operationTimedOut(let stage):
      "AK47 \(stage.description) exceeded the 360 ms timeout"
    case .acknowledgementRejected(let stage):
      "AK47 \(stage.description) acknowledgement was rejected"
    case .invalidReportLength(let stage, let expected, let actual):
      "AK47 \(stage.description) length mismatch; expected \(expected), received \(actual)"
    }
  }
}

protocol AK47WriteFeatureSession {
  func setFeature(_ bytes: [UInt8], stage: AK47DeviceWriteStage) throws
  func getFeature(expectedLength: Int, stage: AK47DeviceWriteStage) throws -> [UInt8]
}

struct AK47FeatureWriteStep: Equatable, Sendable {
  let stage: AK47DeviceWriteStage
  let payload: [UInt8]
  let readback: AK47FeatureReadbackPolicy
  let extraDelayAfterSetMilliseconds: UInt32

  init(
    stage: AK47DeviceWriteStage,
    payload: [UInt8],
    readback: AK47FeatureReadbackPolicy,
    extraDelayAfterSetMilliseconds: UInt32 = 0
  ) {
    self.stage = stage
    self.payload = payload
    self.readback = readback
    self.extraDelayAfterSetMilliseconds = extraDelayAfterSetMilliseconds
  }
}

enum AK47FeatureReadbackPolicy: Equatable, Sendable {
  case none
  case requireStatusOne
  case drain
}

enum AK47FeatureWriteStateMachine {
  typealias Sleep = (_ milliseconds: UInt32) -> Void

  static let commandDelayMilliseconds: UInt32 = 35
  static let reportLength = 64

  static func execute(
    steps: [AK47FeatureWriteStep],
    session: any AK47WriteFeatureSession,
    sleep: Sleep
  ) throws {
    for step in steps {
      guard step.payload.count == reportLength else {
        throw AK47DeviceWriteError.invalidReportLength(
          stage: step.stage,
          expected: reportLength,
          actual: step.payload.count
        )
      }

      sleep(commandDelayMilliseconds)
      try session.setFeature(step.payload, stage: step.stage)
      if step.extraDelayAfterSetMilliseconds > 0 {
        sleep(step.extraDelayAfterSetMilliseconds)
      }

      guard step.readback != .none else { continue }
      sleep(commandDelayMilliseconds)
      let readback = try session.getFeature(
        expectedLength: reportLength,
        stage: step.stage
      )
      guard readback.count == reportLength else {
        throw AK47DeviceWriteError.invalidReportLength(
          stage: step.stage,
          expected: reportLength,
          actual: readback.count
        )
      }
      guard step.readback != .requireStatusOne || readback[3] == 0x01 else {
        throw AK47DeviceWriteError.acknowledgementRejected(stage: step.stage)
      }
    }

    // The Windows utility keeps its HID handle alive after the final helper
    // returns. A one-shot macOS session instead closes immediately, so retain
    // one command interval after the final successful I/O before cancellation.
    sleep(commandDelayMilliseconds)
  }
}

public enum AK47DeviceWriteProtocol {
  public static let reportID: UInt8 = 0
  public static let reportLength = 64

  static var beginPayload: [UInt8] { commandPayload(0x18) }
  static var commitPayload: [UInt8] { commandPayload(0x02) }
  static var finalizePayload: [UInt8] { commandPayload(0xF0) }

  static func clockSteps(_ value: AK47ClockSyncValue) throws -> [AK47FeatureWriteStep] {
    try value.validate()
    var selector = commandPayload(0x28)
    selector[8] = 0x01

    var data = [UInt8](repeating: 0, count: reportLength)
    data[1] = value.lcdItemNumber
    data[2] = 0x5A
    data[3] = UInt8(value.year - 2000)
    data[4] = UInt8(value.month)
    data[5] = UInt8(value.day)
    data[6] = UInt8(value.hour)
    data[7] = UInt8(value.minute)
    data[8] = UInt8(value.second)
    data[10] = UInt8(value.weekday)
    data[62] = 0xAA
    data[63] = 0x55

    return [
      AK47FeatureWriteStep(stage: .begin, payload: beginPayload, readback: .requireStatusOne),
      AK47FeatureWriteStep(stage: .selectClock, payload: selector, readback: .requireStatusOne),
      AK47FeatureWriteStep(stage: .clockData, payload: data, readback: .drain),
      AK47FeatureWriteStep(stage: .commit, payload: commitPayload, readback: .requireStatusOne),
    ]
  }

  static func onboardLightingSteps(_ value: AK47OnboardLightingValue) throws
    -> [AK47FeatureWriteStep]
  {
    try value.validate()
    var selector = commandPayload(0x13)
    selector[8] = 0x01

    var data = [UInt8](repeating: 0, count: reportLength)
    data[0] = value.mode
    if value.mode != 0 {
      data[1] = value.color.red
      data[2] = value.color.green
      data[3] = value.color.blue
      data[8] = value.colorful ? 1 : 0
      data[9] = value.brightness
      data[10] = value.speed
      data[11] = value.direction
    }
    data[14] = 0xAA
    data[15] = 0x55

    return [
      AK47FeatureWriteStep(stage: .begin, payload: beginPayload, readback: .requireStatusOne),
      AK47FeatureWriteStep(
        stage: .selectOnboardLighting,
        payload: selector,
        readback: .requireStatusOne
      ),
      AK47FeatureWriteStep(
        stage: .onboardLightingData,
        payload: data,
        readback: .none
      ),
      AK47FeatureWriteStep(stage: .commit, payload: commitPayload, readback: .requireStatusOne),
      AK47FeatureWriteStep(
        stage: .finalize,
        payload: finalizePayload,
        readback: .none
      ),
    ]
  }

  static func perKeyRGBSteps(
    brightness: UInt8,
    values: [AK47PerKeyRGBValue]
  ) throws -> [AK47FeatureWriteStep] {
    guard (1...5).contains(brightness) else {
      throw AK47DeviceWriteError.invalidPerKeyRGB("brightness must be 1...5")
    }
    let expectedIndices = Set(AK47PerKeyRGBQueryProtocol.lightIndices)
    let suppliedIndices = values.map(\.lightIndex)
    guard suppliedIndices.count == expectedIndices.count,
      Set(suppliedIndices) == expectedIndices,
      Set(suppliedIndices).count == suppliedIndices.count
    else {
      throw AK47DeviceWriteError.invalidPerKeyRGB(
        "all 84 verified light indices must appear exactly once"
      )
    }

    var brightnessData = [UInt8](repeating: 0, count: reportLength)
    brightnessData[0] = 0x80
    brightnessData[9] = brightness
    brightnessData[14] = 0xAA
    brightnessData[15] = 0x55

    var selector = commandPayload(0x23)
    selector[8] = 0x09

    var data = [UInt8](repeating: 0, count: reportLength * 9)
    for value in values {
      let offset = value.lightIndex * 4
      data[offset] = UInt8(value.lightIndex)
      data[offset + 1] = value.color.red
      data[offset + 2] = value.color.green
      data[offset + 3] = value.color.blue
    }
    data[574] = 0xAA
    data[575] = 0x55

    var steps: [AK47FeatureWriteStep] = [
      AK47FeatureWriteStep(stage: .begin, payload: beginPayload, readback: .requireStatusOne),
      AK47FeatureWriteStep(
        stage: .selectOnboardLighting,
        payload: {
          var payload = commandPayload(0x13)
          payload[8] = 0x01
          return payload
        }(),
        readback: .requireStatusOne
      ),
      AK47FeatureWriteStep(
        stage: .onboardLightingData,
        payload: brightnessData,
        readback: .none
      ),
      AK47FeatureWriteStep(stage: .commit, payload: commitPayload, readback: .requireStatusOne),
      AK47FeatureWriteStep(
        stage: .finalize,
        payload: finalizePayload,
        readback: .none
      ),
      AK47FeatureWriteStep(stage: .begin, payload: beginPayload, readback: .requireStatusOne),
      AK47FeatureWriteStep(
        stage: .selectPerKeyRGB,
        payload: selector,
        readback: .requireStatusOne
      ),
    ]

    for packet in 0..<9 {
      let range = (packet * reportLength)..<((packet + 1) * reportLength)
      steps.append(
        AK47FeatureWriteStep(
          stage: .perKeyRGBData(packet + 1),
          payload: Array(data[range]),
          readback: .none,
          // The Windows bulk helper sleeps after every packet. Sleeps before
          // packets 2...9 already provide that interval; packet 9 needs an
          // explicit trailing interval before the commit helper's own delay.
          extraDelayAfterSetMilliseconds: packet == 8 ? 35 : 0
        )
      )
    }
    steps.append(
      AK47FeatureWriteStep(stage: .commit, payload: commitPayload, readback: .requireStatusOne)
    )
    steps.append(
      AK47FeatureWriteStep(
        stage: .finalize,
        payload: finalizePayload,
        readback: .requireStatusOne
      )
    )
    return steps
  }

  static func commandPayload(_ command: UInt8) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: reportLength)
    bytes[0] = 0x04
    bytes[1] = command
    return bytes
  }
}
