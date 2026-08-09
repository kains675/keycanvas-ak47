import Foundation
import IOKit.hid

public enum AK47DeviceWriteAdapter {
  public static func synchronizeClock(
    target: AK47WiredDeviceTarget,
    value: AK47ClockSyncValue,
    authorization: AK47DeviceWriteAuthorization
  ) throws {
    try requireAuthorization(authorization, for: .clockSync)
    let steps = try AK47DeviceWriteProtocol.clockSteps(value)
    try perform(target: target, steps: steps)
  }

  public static func applyOnboardLighting(
    target: AK47WiredDeviceTarget,
    value: AK47OnboardLightingValue,
    authorization: AK47DeviceWriteAuthorization
  ) throws {
    try requireAuthorization(authorization, for: .onboardLighting)
    let steps = try AK47DeviceWriteProtocol.onboardLightingSteps(value)
    try perform(target: target, steps: steps)
  }

  public static func applyPerKeyRGB(
    target: AK47WiredDeviceTarget,
    brightness: UInt8,
    values: [AK47PerKeyRGBValue],
    authorization: AK47DeviceWriteAuthorization
  ) throws {
    try requireAuthorization(authorization, for: .perKeyRGB)
    let steps = try AK47DeviceWriteProtocol.perKeyRGBSteps(
      brightness: brightness,
      values: values
    )
    try perform(target: target, steps: steps)
  }

  private static func requireAuthorization(
    _ authorization: AK47DeviceWriteAuthorization,
    for kind: AK47DeviceWriteKind
  ) throws {
    try authorization.consume(for: kind)
  }

  private static func perform(
    target: AK47WiredDeviceTarget,
    steps: [AK47FeatureWriteStep]
  ) throws {
    try target.validate()
    guard HIDDeviceOperationGate.acquire() else {
      if HIDDeviceOperationGate.isPoisoned {
        throw AK47DeviceWriteError.operationGatePoisoned
      }
      throw AK47DeviceWriteError.deviceBusy
    }
    var mustPoisonGate = false
    defer {
      if mustPoisonGate {
        HIDDeviceOperationGate.poison()
      } else {
        HIDDeviceOperationGate.release()
      }
    }

    let manager = IOHIDManagerCreate(
      kCFAllocatorDefault,
      IOOptionBits(kIOHIDOptionsTypeNone)
    )
    IOHIDManagerSetDeviceMatching(
      manager,
      [
        kIOHIDVendorIDKey: NSNumber(value: HIDEnumerator.vendorID),
        kIOHIDProductIDKey: NSNumber(value: HIDEnumerator.productID),
      ] as CFDictionary
    )
    guard let deviceSet = IOHIDManagerCopyDevices(manager),
      let devices = deviceSet as? Set<IOHIDDevice>
    else {
      throw AK47DeviceWriteError.noMatchingCollection
    }

    let physicalCollections = Array(
      devices.filter { device in
        matchesIdentity(device, target: target)
      })
    guard hasExpectedTopology(physicalCollections) else {
      throw AK47DeviceWriteError.unexpectedTopology(
        collections: physicalCollections.count
      )
    }

    let candidates = physicalCollections.filter(matchesCommandCollection)
    guard !candidates.isEmpty else {
      throw AK47DeviceWriteError.noMatchingCollection
    }
    guard candidates.count == 1, let device = candidates.first else {
      throw AK47DeviceWriteError.ambiguousCollections(candidates.count)
    }

    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw AK47DeviceWriteError.openFailed(rawCode(openResult))
    }
    let session = SystemAK47WriteFeatureSession(device: device)
    do {
      try AK47FeatureWriteStateMachine.execute(
        steps: steps,
        session: session,
        sleep: { milliseconds in
          Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000)
        }
      )
    } catch {
      do {
        try session.cancel()
      } catch {
        mustPoisonGate = true
        throw error
      }
      throw error
    }
    do {
      try session.cancel()
    } catch {
      mustPoisonGate = true
      throw error
    }
    Thread.sleep(forTimeInterval: 0.05)
    try verifyPostflight(target: target)
  }

  private static func matchesIdentity(
    _ device: IOHIDDevice,
    target: AK47WiredDeviceTarget
  ) -> Bool {
    numberProperty(kIOHIDVendorIDKey, device: device) == HIDEnumerator.vendorID
      && numberProperty(kIOHIDProductIDKey, device: device) == HIDEnumerator.productID
      && stringProperty(kIOHIDProductKey, device: device) == target.product
      && stringProperty(kIOHIDTransportKey, device: device) == "USB"
      && numberProperty(kIOHIDLocationIDKey, device: device) == target.locationID
      && numberProperty(kIOHIDVersionNumberKey, device: device) == target.versionNumber
  }

  private static func matchesCommandCollection(_ device: IOHIDDevice) -> Bool {
    numberProperty(kIOHIDPrimaryUsagePageKey, device: device) == 0xFF13
      && numberProperty(kIOHIDPrimaryUsageKey, device: device) == 0x0001
      && numberProperty(kIOHIDMaxInputReportSizeKey, device: device) == 64
      && numberProperty(kIOHIDMaxOutputReportSizeKey, device: device) == 64
      && numberProperty(kIOHIDMaxFeatureReportSizeKey, device: device) == 64
  }

  private static func hasExpectedTopology(_ devices: [IOHIDDevice]) -> Bool {
    guard devices.count == 4 else { return false }
    return containsCollection(
      devices,
      usagePage: 0x0001,
      usage: 0x0006,
      input: 8,
      output: 1,
      feature: 0
    )
      && containsCollection(
        devices,
        usagePage: 0x000C,
        usage: 0x0001,
        input: 16,
        output: 1,
        feature: 1
      )
      && devices.contains(where: matchesCommandCollection)
      && containsCollection(
        devices,
        usagePage: 0xFF68,
        usage: 0x0061,
        input: 64,
        output: 4_096,
        feature: 0
      )
  }

  private static func containsCollection(
    _ devices: [IOHIDDevice],
    usagePage: UInt64,
    usage: UInt64,
    input: UInt64,
    output: UInt64,
    feature: UInt64
  ) -> Bool {
    devices.contains { device in
      numberProperty(kIOHIDPrimaryUsagePageKey, device: device) == usagePage
        && numberProperty(kIOHIDPrimaryUsageKey, device: device) == usage
        && numberProperty(kIOHIDMaxInputReportSizeKey, device: device) == input
        && numberProperty(kIOHIDMaxOutputReportSizeKey, device: device) == output
        && numberProperty(kIOHIDMaxFeatureReportSizeKey, device: device) == feature
    }
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

  private static func verifyPostflight(target: AK47WiredDeviceTarget) throws {
    let records = try HIDEnumerator.enumerate().filter { record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == target.product
        && record.transport == "USB"
        && record.locationID == target.locationID
        && record.versionNumber == target.versionNumber
    }
    let signatures = Set(
      records.compactMap { record -> CollectionSignature? in
        guard let usagePage = record.usagePage,
          let usage = record.usage,
          let input = record.maxInputReportSize,
          let output = record.maxOutputReportSize,
          let feature = record.maxFeatureReportSize
        else {
          return nil
        }
        return CollectionSignature(
          usagePage: usagePage,
          usage: usage,
          input: input,
          output: output,
          feature: feature
        )
      })
    let expected: Set<CollectionSignature> = [
      CollectionSignature(usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
      CollectionSignature(usagePage: 0x000C, usage: 0x0001, input: 16, output: 1, feature: 1),
      CollectionSignature(usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64, feature: 64),
      CollectionSignature(usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096, feature: 0),
    ]
    guard records.count == 4, signatures == expected else {
      throw AK47DeviceWriteError.postflightIdentityLost
    }
  }
}

private struct CollectionSignature: Hashable {
  let usagePage: UInt64
  let usage: UInt64
  let input: UInt64
  let output: UInt64
  let feature: UInt64
}

private final class AK47WriteAsyncFeatureOperation: @unchecked Sendable {
  let capacity: Int
  let buffer: UnsafeMutablePointer<UInt8>
  let reportLength: UnsafeMutablePointer<CFIndex>
  let completion = DispatchSemaphore(value: 0)
  var result: IOReturn = kIOReturnError
  var completedLength = 0

  init(bytes: [UInt8]) {
    capacity = bytes.count
    buffer = .allocate(capacity: bytes.count)
    buffer.initialize(from: bytes, count: bytes.count)
    reportLength = .allocate(capacity: 1)
    reportLength.initialize(to: bytes.count)
  }

  deinit {
    buffer.deinitialize(count: capacity)
    buffer.deallocate()
    reportLength.deinitialize(count: 1)
    reportLength.deallocate()
  }

  func complete(result: IOReturn, reportLength: CFIndex) {
    self.result = result
    completedLength = reportLength
    completion.signal()
  }

  func bytes(count: Int) -> [UInt8] {
    Array(UnsafeBufferPointer(start: buffer, count: count))
  }
}

private let ak47WriteFeatureReportCallback: IOHIDReportCallback = {
  context,
  result,
  _,
  _,
  _,
  _,
  reportLength in
  guard let context else { return }
  let operation = Unmanaged<AK47WriteAsyncFeatureOperation>
    .fromOpaque(context)
    .takeRetainedValue()
  operation.complete(result: result, reportLength: reportLength)
}

private final class SystemAK47WriteFeatureSession: AK47WriteFeatureSession {
  private static let operationTimeoutMilliseconds: CFTimeInterval = 360
  private static let callbackWaitMilliseconds = 500

  private let device: IOHIDDevice
  private let cancellationComplete = DispatchSemaphore(value: 0)
  private enum CancellationState {
    case active
    case confirmed
    case timedOut
  }

  private var cancellationState = CancellationState.active

  init(device: IOHIDDevice) {
    self.device = device
    let callbackQueue = DispatchQueue(label: "io.keycanvas.ak47.verified-writes")
    let cancellationComplete = cancellationComplete
    IOHIDDeviceSetDispatchQueue(device, callbackQueue)
    IOHIDDeviceSetCancelHandler(device) {
      _ = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
      cancellationComplete.signal()
    }
    IOHIDDeviceActivate(device)
  }

  func cancel() throws {
    switch cancellationState {
    case .confirmed:
      return
    case .timedOut:
      throw AK47DeviceWriteError.sessionCancellationTimedOut
    case .active:
      break
    }
    IOHIDDeviceCancel(device)
    guard
      cancellationComplete.wait(
        timeout: .now() + .milliseconds(Self.callbackWaitMilliseconds)
      ) == .success
    else {
      cancellationState = .timedOut
      throw AK47DeviceWriteError.sessionCancellationTimedOut
    }
    cancellationState = .confirmed
  }

  func setFeature(_ bytes: [UInt8], stage: AK47DeviceWriteStage) throws {
    guard bytes.count == AK47DeviceWriteProtocol.reportLength else {
      throw AK47DeviceWriteError.invalidReportLength(
        stage: stage,
        expected: AK47DeviceWriteProtocol.reportLength,
        actual: bytes.count
      )
    }
    let operation = AK47WriteAsyncFeatureOperation(bytes: bytes)
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submissionResult = IOHIDDeviceSetReportWithCallback(
      device,
      kIOHIDReportTypeFeature,
      CFIndex(AK47DeviceWriteProtocol.reportID),
      operation.buffer,
      bytes.count,
      Self.operationTimeoutMilliseconds,
      ak47WriteFeatureReportCallback,
      context
    )
    try awaitCompletion(
      operation,
      context: context,
      submissionResult: submissionResult,
      stage: stage
    )
  }

  func getFeature(
    expectedLength: Int,
    stage: AK47DeviceWriteStage
  ) throws -> [UInt8] {
    let operation = AK47WriteAsyncFeatureOperation(
      bytes: [UInt8](repeating: 0, count: expectedLength)
    )
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submissionResult = IOHIDDeviceGetReportWithCallback(
      device,
      kIOHIDReportTypeFeature,
      CFIndex(AK47DeviceWriteProtocol.reportID),
      operation.buffer,
      operation.reportLength,
      Self.operationTimeoutMilliseconds,
      ak47WriteFeatureReportCallback,
      context
    )
    try awaitCompletion(
      operation,
      context: context,
      submissionResult: submissionResult,
      stage: stage
    )
    guard operation.completedLength == expectedLength else {
      throw AK47DeviceWriteError.invalidReportLength(
        stage: stage,
        expected: expectedLength,
        actual: operation.completedLength
      )
    }
    return operation.bytes(count: operation.completedLength)
  }

  private func awaitCompletion(
    _ operation: AK47WriteAsyncFeatureOperation,
    context: UnsafeMutableRawPointer,
    submissionResult: IOReturn,
    stage: AK47DeviceWriteStage
  ) throws {
    guard submissionResult == kIOReturnSuccess else {
      Unmanaged<AK47WriteAsyncFeatureOperation>.fromOpaque(context).release()
      throw AK47DeviceWriteError.operationFailed(
        stage: stage,
        code: UInt32(bitPattern: submissionResult)
      )
    }
    guard
      operation.completion.wait(
        timeout: .now() + .milliseconds(Self.callbackWaitMilliseconds)
      ) == .success
    else {
      throw AK47DeviceWriteError.operationTimedOut(stage: stage)
    }
    guard operation.result == kIOReturnSuccess else {
      if operation.result == kIOReturnTimeout {
        throw AK47DeviceWriteError.operationTimedOut(stage: stage)
      }
      throw AK47DeviceWriteError.operationFailed(
        stage: stage,
        code: UInt32(bitPattern: operation.result)
      )
    }
  }
}
