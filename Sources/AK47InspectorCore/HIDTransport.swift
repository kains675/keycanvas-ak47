import Foundation

public enum HIDWritePurpose: String, Codable, Equatable, Sendable {
  case configuration
  case firmwareUpdate = "firmware-update"
}

public enum HIDCapability: String, Codable, Hashable, Sendable {
  case inspect
  case configurationWrite = "configuration-write"
  case firmwareUpdate = "firmware-update"
}

public struct HIDCapabilityPolicy: Equatable, Sendable {
  public let allowed: Set<HIDCapability>

  /// Creates a read-only policy. Write and firmware capabilities must be granted
  /// explicitly by constructing a policy with the corresponding flags enabled.
  public init(
    allowConfigurationWrites: Bool = false,
    allowFirmwareUpdates: Bool = false
  ) {
    var capabilities: Set<HIDCapability> = [.inspect]
    if allowConfigurationWrites {
      capabilities.insert(.configurationWrite)
    }
    if allowFirmwareUpdates {
      capabilities.insert(.firmwareUpdate)
    }
    self.allowed = capabilities
  }

  public func authorize(_ capability: HIDCapability) throws {
    guard allowed.contains(capability) else {
      throw HIDTransportError.capabilityDenied(capability)
    }
  }
}

public enum HIDTransportRequest: Equatable, Sendable {
  case readFeature(reportID: UInt8, expectedLength: Int)
  case writeFeature(reportID: UInt8, bytes: [UInt8], purpose: HIDWritePurpose)
  case writeOutput(reportID: UInt8, bytes: [UInt8], purpose: HIDWritePurpose)

  public var requiredCapability: HIDCapability {
    switch self {
    case .readFeature:
      return .inspect
    case .writeFeature(_, _, let purpose), .writeOutput(_, _, let purpose):
      switch purpose {
      case .configuration: return .configurationWrite
      case .firmwareUpdate: return .firmwareUpdate
      }
    }
  }

  public func validate() throws {
    switch self {
    case .readFeature(_, let expectedLength):
      guard (1...64).contains(expectedLength) else {
        throw HIDTransportError.invalidRequest(
          "feature read length must be between 1 and 64 bytes"
        )
      }
    case .writeFeature(_, let bytes, _):
      guard !bytes.isEmpty, bytes.count <= 64 else {
        throw HIDTransportError.invalidRequest(
          "feature write must contain between 1 and 64 bytes"
        )
      }
    case .writeOutput(_, let bytes, _):
      guard !bytes.isEmpty, bytes.count <= 4_096 else {
        throw HIDTransportError.invalidRequest(
          "output write must contain between 1 and 4096 bytes"
        )
      }
    }
  }
}

public struct HIDTransportResponse: Equatable, Sendable {
  public let bytes: [UInt8]

  public init(bytes: [UInt8] = []) {
    self.bytes = bytes
  }
}

public enum HIDTransportError: Error, Equatable, LocalizedError, Sendable {
  case invalidRequest(String)
  case invalidResponse(expectedLength: Int, actualLength: Int)
  case capabilityDenied(HIDCapability)
  case noScriptedResponse
  case unexpectedRequest(expected: HIDTransportRequest, actual: HIDTransportRequest)
  case scriptedFailure(String)

  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason):
      return "invalid HID transport request: \(reason)"
    case .invalidResponse(let expectedLength, let actualLength):
      return
        "invalid HID transport response length; expected \(expectedLength), got \(actualLength)"
    case .capabilityDenied(let capability):
      return "HID capability is denied by policy: \(capability.rawValue)"
    case .noScriptedResponse:
      return "mock HID transport has no scripted response"
    case .unexpectedRequest(let expected, let actual):
      return "mock HID transport expected \(expected) but received \(actual)"
    case .scriptedFailure(let message):
      return "mock HID transport failure: \(message)"
    }
  }
}

/// Abstracts report I/O without supplying a hardware implementation.
///
/// The Core target intentionally provides only an in-memory mock and a capability
/// wrapper. A platform adapter can conform later, at an application boundary.
public protocol HIDTransport: AnyObject, Sendable {
  func perform(_ request: HIDTransportRequest) throws -> HIDTransportResponse
}

public final class CapabilityGatedHIDTransport: HIDTransport, @unchecked Sendable {
  public let policy: HIDCapabilityPolicy
  private let underlying: any HIDTransport

  public init(
    underlying: any HIDTransport,
    policy: HIDCapabilityPolicy = HIDCapabilityPolicy()
  ) {
    self.underlying = underlying
    self.policy = policy
  }

  public func perform(_ request: HIDTransportRequest) throws -> HIDTransportResponse {
    try request.validate()
    try policy.authorize(request.requiredCapability)

    let response = try underlying.perform(request)
    if case .readFeature(_, let expectedLength) = request,
      response.bytes.count != expectedLength
    {
      throw HIDTransportError.invalidResponse(
        expectedLength: expectedLength,
        actualLength: response.bytes.count
      )
    }
    return response
  }
}

public struct MockHIDTransportStep: Equatable, Sendable {
  public enum Outcome: Equatable, Sendable {
    case response(HIDTransportResponse)
    case failure(String)
  }

  public let expectedRequest: HIDTransportRequest?
  public let outcome: Outcome

  public init(
    expectedRequest: HIDTransportRequest? = nil,
    response: HIDTransportResponse
  ) {
    self.expectedRequest = expectedRequest
    self.outcome = .response(response)
  }

  public init(
    expectedRequest: HIDTransportRequest? = nil,
    failure message: String
  ) {
    self.expectedRequest = expectedRequest
    self.outcome = .failure(message)
  }
}

/// An in-memory transport for tests and UI prototyping. It never opens a HID device.
public final class MockHIDTransport: HIDTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var steps: [MockHIDTransportStep]
  private var requests: [HIDTransportRequest] = []

  public init(steps: [MockHIDTransportStep] = []) {
    self.steps = steps
  }

  public var performedRequests: [HIDTransportRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }

  public var remainingStepCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return steps.count
  }

  public func enqueue(_ step: MockHIDTransportStep) {
    lock.lock()
    defer { lock.unlock() }
    steps.append(step)
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    steps.removeAll()
    requests.removeAll()
  }

  public func perform(_ request: HIDTransportRequest) throws -> HIDTransportResponse {
    try request.validate()

    let step: MockHIDTransportStep
    lock.lock()
    requests.append(request)
    guard let first = steps.first else {
      lock.unlock()
      throw HIDTransportError.noScriptedResponse
    }
    if let expected = first.expectedRequest, expected != request {
      lock.unlock()
      throw HIDTransportError.unexpectedRequest(expected: expected, actual: request)
    }
    step = steps.removeFirst()
    lock.unlock()

    switch step.outcome {
    case .response(let response):
      return response
    case .failure(let message):
      throw HIDTransportError.scriptedFailure(message)
    }
  }
}
