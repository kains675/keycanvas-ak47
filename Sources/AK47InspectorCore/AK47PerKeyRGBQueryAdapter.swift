import Foundation
import IOKit.hid

public struct AK47PerKeyRGBQueryRequest: Equatable, Sendable {
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
      throw AK47PerKeyRGBQueryAdapterError.invalidRequest("unexpected product name")
    }
    guard locationID <= UInt64(UInt32.max) else {
      throw AK47PerKeyRGBQueryAdapterError.invalidRequest("location ID is out of range")
    }
    guard versionNumber == 0x0115 else {
      throw AK47PerKeyRGBQueryAdapterError.invalidRequest(
        "only the verified USB revision 0x0115 is enabled"
      )
    }
    if let serialNumber {
      guard !serialNumber.isEmpty, serialNumber.utf8.count <= 256 else {
        throw AK47PerKeyRGBQueryAdapterError.invalidRequest(
          "serial number is empty or too long"
        )
      }
    }
  }
}

/// One-use confirmation bound to one exact F5 target. Only another target in
/// this package (the confirmed Studio UI or opt-in hardware tests) can create it.
public final class AK47PerKeyRGBQueryAuthorization: @unchecked Sendable {
  private let request: AK47PerKeyRGBQueryRequest
  private let lock = NSLock()
  private var consumed = false

  package init(explicitlyConfirming request: AK47PerKeyRGBQueryRequest) {
    self.request = request
  }

  package func consume(for expected: AK47PerKeyRGBQueryRequest) throws {
    lock.lock()
    defer { lock.unlock() }
    guard request == expected else {
      throw AK47PerKeyRGBQueryAdapterError.authorizationMismatch
    }
    guard !consumed else {
      throw AK47PerKeyRGBQueryAdapterError.authorizationAlreadyConsumed
    }
    consumed = true
  }
}

public enum AK47PerKeyRGBQueryStage: Equatable, Sendable {
  case queryCommand
  case queryAcknowledgement
  case dataPacket(Int)
  case finishCommand
  case finishAcknowledgement

  fileprivate var description: String {
    switch self {
    case .queryCommand:
      "query command"
    case .queryAcknowledgement:
      "query acknowledgement"
    case .dataPacket(let packet):
      "data packet \(packet)"
    case .finishCommand:
      "finish command"
    case .finishAcknowledgement:
      "finish acknowledgement"
    }
  }
}

public enum AK47PerKeyRGBQueryAdapterError: Error, Equatable, LocalizedError, Sendable {
  case invalidRequest(String)
  case authorizationMismatch
  case authorizationAlreadyConsumed
  case noMatchingCollection
  case ambiguousCollections(Int)
  case unexpectedTopology(collections: Int)
  case deviceBusy
  case operationGatePoisoned
  case partialTransactionQuarantined(String)
  case quarantinePersistenceFailed
  case openFailed(UInt32)
  case sessionCancellationTimedOut
  case operationFailed(stage: AK47PerKeyRGBQueryStage, code: UInt32)
  case operationTimedOut(stage: AK47PerKeyRGBQueryStage)
  case acknowledgementRejected(stage: AK47PerKeyRGBQueryStage)
  case invalidReportLength(stage: AK47PerKeyRGBQueryStage, expected: Int, actual: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason):
      "invalid AK47 RGB query request: \(reason)"
    case .authorizationMismatch:
      "the one-use RGB query confirmation does not match this exact target"
    case .authorizationAlreadyConsumed:
      "the one-use RGB query confirmation was already consumed"
    case .noMatchingCollection:
      "the exact AK47 RGB command collection was not found"
    case .ambiguousCollections(let count):
      "refusing the RGB query because \(count) command collections match"
    case .unexpectedTopology(let collections):
      "refusing the RGB query because the wired AK47 exposes \(collections) unexpected HID collections"
    case .deviceBusy:
      "another HID diagnostic operation is already in progress"
    case .operationGatePoisoned:
      "AK47 HID operations are quarantined. Keep the selector in USB mode, disconnect the cable until the device is unpowered, refresh Device Inspector while it is absent, then reconnect at the original USB location and refresh again. Relaunching or switching to 2.4G/Bluetooth does not clear the quarantine."
    case .partialTransactionQuarantined(let cause):
      "AK47 RGB query state is uncertain after report submission (\(cause)). Keep the selector in USB mode, disconnect the cable until the device is unpowered, refresh Device Inspector while it is absent, then reconnect at the original USB location and refresh again. Relaunching alone does not clear the quarantine, and switching to 2.4G/Bluetooth is not recovery."
    case .quarantinePersistenceFailed:
      "KeyCanvas could not durably record the AK47 transaction marker, so no RGB query report was submitted. HID operations remain blocked in this process."
    case .openFailed(let code):
      String(format: "opening the AK47 command collection failed (0x%08X)", code)
    case .sessionCancellationTimedOut:
      "AK47 RGB query cancellation was not confirmed within 500 ms. Keep the selector in USB mode, disconnect the cable until the device is unpowered, refresh Device Inspector while it is absent, then reconnect at the original USB location and refresh again."
    case .operationFailed(let stage, let code):
      String(
        format: "AK47 RGB %@ failed (0x%08X)",
        stage.description,
        code
      )
    case .operationTimedOut(let stage):
      "AK47 RGB \(stage.description) exceeded the 360 ms timeout"
    case .acknowledgementRejected(let stage):
      "AK47 RGB \(stage.description) was rejected"
    case .invalidReportLength(let stage, let expected, let actual):
      "AK47 RGB \(stage.description) length mismatch; expected \(expected), received \(actual)"
    }
  }
}

protocol AK47FeatureReportSession {
  func setFeature(_ bytes: [UInt8], stage: AK47PerKeyRGBQueryStage) throws
  func getFeature(
    expectedLength: Int,
    stage: AK47PerKeyRGBQueryStage
  ) throws -> [UInt8]
}

enum AK47PerKeyRGBTransaction {
  typealias Sleep = (_ milliseconds: UInt32) -> Void

  static func execute(
    session: any AK47FeatureReportSession,
    sleep: Sleep
  ) throws -> AK47PerKeyRGBSnapshot {
    sleep(10)
    sleep(3)
    try session.setFeature(
      AK47PerKeyRGBQueryProtocol.queryPayload,
      stage: .queryCommand
    )

    sleep(5)
    let queryAcknowledgement = try session.getFeature(
      expectedLength: AK47PerKeyRGBQueryProtocol.reportLength,
      stage: .queryAcknowledgement
    )
    do {
      try AK47PerKeyRGBQueryProtocol.validateAcknowledgement(queryAcknowledgement)
    } catch {
      throw AK47PerKeyRGBQueryAdapterError.acknowledgementRejected(
        stage: .queryAcknowledgement
      )
    }

    var responsePackets: [[UInt8]] = []
    responsePackets.reserveCapacity(AK47PerKeyRGBQueryProtocol.responsePacketCount)
    for packetIndex in 0..<AK47PerKeyRGBQueryProtocol.responsePacketCount {
      sleep(3)
      responsePackets.append(
        try session.getFeature(
          expectedLength: AK47PerKeyRGBQueryProtocol.reportLength,
          stage: .dataPacket(packetIndex + 1)
        )
      )
    }

    let snapshot = try AK47PerKeyRGBQueryProtocol.parse(responsePackets: responsePackets)

    // The Windows utility parses the complete nine-report response before ending
    // the transaction. A rejected response is never followed by the finish command.
    sleep(35)
    try session.setFeature(
      AK47PerKeyRGBQueryProtocol.finishPayload,
      stage: .finishCommand
    )
    sleep(35)
    let finishAcknowledgement = try session.getFeature(
      expectedLength: AK47PerKeyRGBQueryProtocol.reportLength,
      stage: .finishAcknowledgement
    )
    do {
      try AK47PerKeyRGBQueryProtocol.validateAcknowledgement(finishAcknowledgement)
    } catch {
      throw AK47PerKeyRGBQueryAdapterError.acknowledgementRejected(
        stage: .finishAcknowledgement
      )
    }

    return snapshot
  }
}

public enum AK47PerKeyRGBQueryAdapter {
  public static func query(
    _ request: AK47PerKeyRGBQueryRequest,
    authorization: AK47PerKeyRGBQueryAuthorization
  ) throws
    -> AK47PerKeyRGBSnapshot
  {
    try request.validate()
    try authorization.consume(for: request)
    let quarantineTarget = HIDDeviceQuarantineIdentity(request: request)
    switch HIDDeviceOperationGate.acquireResult(for: quarantineTarget) {
    case .acquired:
      break
    case .busy:
      throw AK47PerKeyRGBQueryAdapterError.deviceBusy
    case .quarantined:
      throw AK47PerKeyRGBQueryAdapterError.operationGatePoisoned
    }
    let transactionEvidence = HIDDeviceOperationGate.makeTransactionEvidence()
    var gateFinalized = false
    defer {
      if !gateFinalized {
        try? HIDDeviceOperationGate.finish(
          succeeded: false,
          evidence: transactionEvidence
        )
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
      throw AK47PerKeyRGBQueryAdapterError.noMatchingCollection
    }

    let physicalCollections = Array(
      devices.filter { device in
        matchesIdentity(device, request: request)
      })
    guard hasExpectedTopology(physicalCollections) else {
      throw AK47PerKeyRGBQueryAdapterError.unexpectedTopology(
        collections: physicalCollections.count
      )
    }

    let candidates = physicalCollections.filter { device in
      matchesCommandCollection(device)
    }
    guard !candidates.isEmpty else {
      throw AK47PerKeyRGBQueryAdapterError.noMatchingCollection
    }
    guard candidates.count == 1, let device = candidates.first else {
      throw AK47PerKeyRGBQueryAdapterError.ambiguousCollections(candidates.count)
    }

    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw AK47PerKeyRGBQueryAdapterError.openFailed(rawCode(openResult))
    }
    let session = SystemAK47FeatureReportSession(
      device: device,
      transactionEvidence: transactionEvidence
    )
    let snapshot: AK47PerKeyRGBSnapshot
    do {
      do {
        snapshot = try AK47PerKeyRGBTransaction.execute(
          session: session,
          sleep: { milliseconds in
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000)
          }
        )
      } catch let transactionError {
        do {
          try session.cancel()
          if !transactionEvidence.hasSubmittedReport {
            Thread.sleep(forTimeInterval: 0.05)
            if (try? verifyPostflight(request: request)) != nil {
              transactionEvidence.recordSafePreSubmissionCleanup()
            }
          }
        } catch {
          transactionEvidence.recordUnconfirmedCancellation()
        }
        throw transactionError
      }
      do {
        try session.cancel()
      } catch {
        transactionEvidence.recordUnconfirmedCancellation()
        throw error
      }
      Thread.sleep(forTimeInterval: 0.05)
      try verifyPostflight(request: request)
    } catch {
      let operationError = errorForFailedTransaction(error, evidence: transactionEvidence)
      do {
        try HIDDeviceOperationGate.finish(
          succeeded: false,
          evidence: transactionEvidence
        )
        gateFinalized = true
      } catch {
        gateFinalized = true
        throw AK47PerKeyRGBQueryAdapterError.partialTransactionQuarantined(
          "durable quarantine finalization failed after: \(operationError.localizedDescription)"
        )
      }
      throw operationError
    }
    do {
      try HIDDeviceOperationGate.finish(
        succeeded: true,
        evidence: transactionEvidence
      )
      gateFinalized = true
    } catch {
      gateFinalized = true
      throw AK47PerKeyRGBQueryAdapterError.partialTransactionQuarantined(
        "the RGB query completed, but durable marker cleanup failed"
      )
    }
    return snapshot
  }

  static func errorForFailedTransaction(
    _ error: Error,
    evidence: HIDDeviceTransactionEvidence
  ) -> Error {
    guard evidence.failureRequiresPhysicalRecovery else { return error }
    if let queryError = error as? AK47PerKeyRGBQueryAdapterError,
      case .partialTransactionQuarantined = queryError
    {
      return error
    }
    return AK47PerKeyRGBQueryAdapterError.partialTransactionQuarantined(
      error.localizedDescription
    )
  }

  private static func matchesIdentity(
    _ device: IOHIDDevice,
    request: AK47PerKeyRGBQueryRequest
  ) -> Bool {
    numberProperty(kIOHIDVendorIDKey, device: device) == HIDEnumerator.vendorID
      && numberProperty(kIOHIDProductIDKey, device: device) == HIDEnumerator.productID
      && stringProperty(kIOHIDProductKey, device: device) == request.product
      && stringProperty(kIOHIDTransportKey, device: device) == "USB"
      && numberProperty(kIOHIDLocationIDKey, device: device) == request.locationID
      && numberProperty(kIOHIDVersionNumberKey, device: device) == request.versionNumber
      && (request.serialNumber == nil
        || stringProperty(kIOHIDSerialNumberKey, device: device) == request.serialNumber)
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

  private static func verifyPostflight(
    request: AK47PerKeyRGBQueryRequest
  ) throws {
    let records = try HIDEnumerator.enumerate().filter { record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == request.product
        && record.transport == "USB"
        && record.locationID == request.locationID
        && record.versionNumber == request.versionNumber
        && (request.serialNumber == nil || record.serialNumber == request.serialNumber)
    }
    let signatures = Set(
      records.compactMap { record -> AK47RGBQueryCollectionSignature? in
        guard let usagePage = record.usagePage,
          let usage = record.usage,
          let input = record.maxInputReportSize,
          let output = record.maxOutputReportSize,
          let feature = record.maxFeatureReportSize
        else { return nil }
        return AK47RGBQueryCollectionSignature(
          usagePage: usagePage,
          usage: usage,
          input: input,
          output: output,
          feature: feature
        )
      })
    let expected: Set<AK47RGBQueryCollectionSignature> = [
      AK47RGBQueryCollectionSignature(
        usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
      AK47RGBQueryCollectionSignature(
        usagePage: 0x000C, usage: 0x0001, input: 16, output: 1, feature: 1),
      AK47RGBQueryCollectionSignature(
        usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64, feature: 64),
      AK47RGBQueryCollectionSignature(
        usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096, feature: 0),
    ]
    guard records.count == 4, signatures == expected else {
      throw AK47PerKeyRGBQueryAdapterError.unexpectedTopology(
        collections: records.count
      )
    }
  }
}

private struct AK47RGBQueryCollectionSignature: Hashable {
  let usagePage: UInt64
  let usage: UInt64
  let input: UInt64
  let output: UInt64
  let feature: UInt64
}

private final class AsyncFeatureReportOperation: @unchecked Sendable {
  let capacity: Int
  let buffer: UnsafeMutablePointer<UInt8>
  let reportLength: UnsafeMutablePointer<CFIndex>
  let completion = DispatchSemaphore(value: 0)
  var result: IOReturn = kIOReturnError
  var completedLength: Int = 0

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

private let asyncFeatureReportCallback: IOHIDReportCallback = {
  context,
  result,
  _,
  _,
  _,
  _,
  reportLength in
  guard let context else { return }
  let operation = Unmanaged<AsyncFeatureReportOperation>
    .fromOpaque(context)
    .takeRetainedValue()
  operation.complete(result: result, reportLength: reportLength)
}

private final class SystemAK47FeatureReportSession: AK47FeatureReportSession {
  private static let operationTimeoutMilliseconds: CFTimeInterval = 360
  private static let callbackWaitMilliseconds = 500

  private let device: IOHIDDevice
  private let transactionEvidence: HIDDeviceTransactionEvidence
  private let cancellationComplete = DispatchSemaphore(value: 0)
  private enum CancellationState {
    case active
    case confirmed
    case timedOut
  }

  private var cancellationState = CancellationState.active

  init(
    device: IOHIDDevice,
    transactionEvidence: HIDDeviceTransactionEvidence
  ) {
    self.device = device
    self.transactionEvidence = transactionEvidence
    let callbackQueue = DispatchQueue(label: "io.keycanvas.ak47.rgb-query")
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
      throw AK47PerKeyRGBQueryAdapterError.sessionCancellationTimedOut
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
      throw AK47PerKeyRGBQueryAdapterError.sessionCancellationTimedOut
    }
    cancellationState = .confirmed
  }

  func setFeature(_ bytes: [UInt8], stage: AK47PerKeyRGBQueryStage) throws {
    guard bytes.count == AK47PerKeyRGBQueryProtocol.reportLength else {
      throw AK47PerKeyRGBQueryAdapterError.invalidReportLength(
        stage: stage,
        expected: AK47PerKeyRGBQueryProtocol.reportLength,
        actual: bytes.count
      )
    }
    do {
      try transactionEvidence.prepareForSubmission()
    } catch {
      throw AK47PerKeyRGBQueryAdapterError.quarantinePersistenceFailed
    }
    let operation = AsyncFeatureReportOperation(bytes: bytes)
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submissionResult = IOHIDDeviceSetReportWithCallback(
      device,
      kIOHIDReportTypeFeature,
      CFIndex(AK47PerKeyRGBQueryProtocol.reportID),
      operation.buffer,
      bytes.count,
      Self.operationTimeoutMilliseconds,
      asyncFeatureReportCallback,
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
    stage: AK47PerKeyRGBQueryStage
  ) throws -> [UInt8] {
    do {
      try transactionEvidence.prepareForSubmission()
    } catch {
      throw AK47PerKeyRGBQueryAdapterError.quarantinePersistenceFailed
    }
    let operation = AsyncFeatureReportOperation(
      bytes: [UInt8](repeating: 0, count: expectedLength)
    )
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submissionResult = IOHIDDeviceGetReportWithCallback(
      device,
      kIOHIDReportTypeFeature,
      CFIndex(AK47PerKeyRGBQueryProtocol.reportID),
      operation.buffer,
      operation.reportLength,
      Self.operationTimeoutMilliseconds,
      asyncFeatureReportCallback,
      context
    )
    try awaitCompletion(
      operation,
      context: context,
      submissionResult: submissionResult,
      stage: stage
    )
    guard operation.completedLength == expectedLength else {
      throw AK47PerKeyRGBQueryAdapterError.invalidReportLength(
        stage: stage,
        expected: expectedLength,
        actual: operation.completedLength
      )
    }
    return operation.bytes(count: operation.completedLength)
  }

  private func awaitCompletion(
    _ operation: AsyncFeatureReportOperation,
    context: UnsafeMutableRawPointer,
    submissionResult: IOReturn,
    stage: AK47PerKeyRGBQueryStage
  ) throws {
    guard submissionResult == kIOReturnSuccess else {
      Unmanaged<AsyncFeatureReportOperation>.fromOpaque(context).release()
      throw AK47PerKeyRGBQueryAdapterError.operationFailed(
        stage: stage,
        code: UInt32(bitPattern: submissionResult)
      )
    }
    transactionEvidence.recordSubmittedReport()
    guard
      operation.completion.wait(
        timeout: .now() + .milliseconds(Self.callbackWaitMilliseconds)
      ) == .success
    else {
      throw AK47PerKeyRGBQueryAdapterError.operationTimedOut(stage: stage)
    }
    guard operation.result == kIOReturnSuccess else {
      if operation.result == kIOReturnTimeout {
        throw AK47PerKeyRGBQueryAdapterError.operationTimedOut(stage: stage)
      }
      throw AK47PerKeyRGBQueryAdapterError.operationFailed(
        stage: stage,
        code: UInt32(bitPattern: operation.result)
      )
    }
  }
}
