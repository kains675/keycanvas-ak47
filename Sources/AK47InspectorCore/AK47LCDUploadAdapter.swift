import CryptoKit
import Foundation
import IOKit.hid

/// Errors from the deliberately narrow, first-device LCD experiment.
public enum AK47LCDUploadAdapterError: Error, Equatable, LocalizedError, Sendable {
  case authorizationMismatch
  case authorizationAlreadyConsumed
  case liveFrameCountNotEnabled(Int)
  case livePageCountNotEnabled(Int)
  case liveContainerLengthNotEnabled(Int)
  case fixtureNotAllowlisted
  case qualifiedFrameCountNotEnabled(Int)
  case qualifiedPageCountMismatch(expected: Int, actual: Int)
  case qualifiedContainerLengthMismatch(expected: Int, actual: Int)
  case qualifiedTransferEndMismatch(expected: UInt64, actual: UInt64)
  case qualificationReceiptNotRecordedAfterSuccessfulTransfer
  case qualificationLeaseFinalizationFailed
  case noMatchingFeatureCollection
  case noMatchingOutputCollection
  case ambiguousFeatureCollections(Int)
  case ambiguousOutputCollections(Int)
  case unexpectedTopology(collections: Int)
  case usbAncestryMismatch
  case deviceBusy
  case operationGateQuarantined
  case quarantinePersistenceFailed
  case openFailed(collection: String, code: UInt32)
  case operationFailed(stage: AK47LCDUploadStage, code: UInt32)
  case operationTimedOut(stage: AK47LCDUploadStage)
  case shortWrite(stage: AK47LCDUploadStage, expected: Int, actual: Int)
  case unexpectedCompletion(stage: AK47LCDUploadStage)
  case inputCallbackNotPrepared
  case inputCallbackGenerationMismatch
  case unexpectedInputAcknowledgement
  case inputReportIDMismatch(UInt32)
  case inputReportFailed(code: UInt32)
  case inputReportTypeMismatch
  case lifecycleHazard
  case sessionCancellationTimedOut
  case postflightIdentityLost
  case partialTransactionQuarantined(String)

  public var errorDescription: String? {
    switch self {
    case .authorizationMismatch:
      "The LCD authorization does not match this exact target and container."
    case .authorizationAlreadyConsumed:
      "The one-use LCD authorization was already consumed."
    case .liveFrameCountNotEnabled(let count):
      "The first LCD experiment accepts exactly one frame; got \(count)."
    case .livePageCountNotEnabled(let count):
      "The first LCD experiment accepts exactly 16 pages; got \(count)."
    case .liveContainerLengthNotEnabled(let count):
      "The first LCD experiment accepts exactly 65536 bytes; got \(count)."
    case .fixtureNotAllowlisted:
      "Only the reviewed four-corner diagnostic fixture is enabled for the first LCD experiment."
    case .qualifiedFrameCountNotEnabled(let count):
      "The qualified LCD path accepts 1...40 frames; got \(count)."
    case .qualifiedPageCountMismatch(let expected, let actual):
      "The qualified LCD container must use the minimal \(expected) pages; got \(actual)."
    case .qualifiedContainerLengthMismatch(let expected, let actual):
      "The qualified LCD container must contain exactly \(expected) padded bytes; got \(actual)."
    case .qualifiedTransferEndMismatch(let expected, let actual):
      String(
        format: "The qualified LCD transfer end must be 0x%llX; got 0x%llX.",
        expected,
        actual
      )
    case .qualificationReceiptNotRecordedAfterSuccessfulTransfer:
      "The canonical LCD transfer completed, but its qualification candidate could not be recorded durably. The 1...40-frame path remains locked."
    case .qualificationLeaseFinalizationFailed:
      "The LCD transfer lease could not be finalized durably. The qualified path remains locked."
    case .noMatchingFeatureCollection:
      "The exact AK47 FF13 command collection was not found."
    case .noMatchingOutputCollection:
      "The exact AK47 FF68 LCD collection was not found."
    case .ambiguousFeatureCollections(let count):
      "Refusing the LCD experiment because \(count) FF13 command collections match."
    case .ambiguousOutputCollections(let count):
      "Refusing the LCD experiment because \(count) FF68 LCD collections match."
    case .unexpectedTopology(let collections):
      "Refusing the LCD experiment because the wired AK47 exposes \(collections) unexpected HID collections."
    case .usbAncestryMismatch:
      "The FF13/FF68 collections do not prove interface 3/interface 2 under one exact physical USB parent."
    case .deviceBusy:
      "Another AK47 HID operation is already in progress."
    case .operationGateQuarantined:
      "AK47 HID operations are quarantined until the required USB-mode cable-removal recovery observations are complete."
    case .quarantinePersistenceFailed:
      "KeyCanvas could not durably arm the AK47 transaction marker, so no report was submitted."
    case .openFailed(let collection, let code):
      String(format: "Opening the AK47 %@ collection failed (0x%08X).", collection, code)
    case .operationFailed(let stage, let code):
      String(format: "AK47 LCD %@ failed (0x%08X).", stage.description, code)
    case .operationTimedOut(let stage):
      "AK47 LCD \(stage.description) exceeded its bounded timeout."
    case .shortWrite(let stage, let expected, let actual):
      "AK47 LCD \(stage.description) wrote \(actual) bytes instead of \(expected)."
    case .unexpectedCompletion(let stage):
      "AK47 LCD \(stage.description) completed with an unexpected report type or ID."
    case .inputCallbackNotPrepared:
      "The persistent LCD input callback was not prepared before the output report."
    case .inputCallbackGenerationMismatch:
      "The LCD input acknowledgement belongs to a different output generation."
    case .unexpectedInputAcknowledgement:
      "The LCD collection produced an unsolicited, duplicate, or stale input acknowledgement."
    case .inputReportIDMismatch(let reportID):
      "The AK47 LCD input callback returned report ID \(reportID) instead of 0."
    case .inputReportFailed(let code):
      String(format: "The AK47 LCD input callback failed (0x%08X).", code)
    case .inputReportTypeMismatch:
      "The AK47 LCD callback returned a non-input report."
    case .lifecycleHazard:
      "The LCD transfer was interrupted by a termination, sleep, or power-off lifecycle hazard."
    case .sessionCancellationTimedOut:
      "AK47 LCD HID cancellation was not confirmed within 500 ms."
    case .postflightIdentityLost:
      "The exact AK47 identity or four-collection topology was not present after the LCD attempt."
    case .partialTransactionQuarantined(let cause):
      "AK47 LCD transaction state is uncertain after report submission (\(cause)). Keep the selector in USB mode, disconnect the cable until the device is unpowered and absent, then complete exact reappearance recovery."
    }
  }
}

/// A package-created authorization bound to one exact plan fingerprint.
///
/// The Studio app may create this only after its operation-specific warning.
/// Reusing it, or substituting a different target/container, is rejected.
public final class AK47LCDUploadAuthorization: @unchecked Sendable {
  private let lock = NSLock()
  private let fingerprint: Data
  private var consumed = false

  package init(explicitlyConfirming plan: AK47LCDUploadPlan) {
    fingerprint = AK47LCDUploadPlanFingerprint.make(plan)
  }

  package func consume(for plan: AK47LCDUploadPlan) throws {
    let requestedFingerprint = AK47LCDUploadPlanFingerprint.make(plan)
    lock.lock()
    defer { lock.unlock() }
    guard fingerprint == requestedFingerprint else {
      throw AK47LCDUploadAdapterError.authorizationMismatch
    }
    guard !consumed else {
      throw AK47LCDUploadAdapterError.authorizationAlreadyConsumed
    }
    consumed = true
  }
}

/// A separate one-use authority for an immutable qualified editor snapshot.
/// It cannot authorize the canonical first experiment and is consumed before
/// the durable qualification lease is claimed.
public final class AK47LCDQualifiedUploadAuthorization: @unchecked Sendable {
  private let lock = NSLock()
  private let fingerprint: Data
  private var consumed = false

  package init(explicitlyConfirming plan: AK47LCDUploadPlan) {
    fingerprint = AK47LCDUploadPlanFingerprint.make(plan)
  }

  package func consume(for plan: AK47LCDUploadPlan) throws {
    let requestedFingerprint = AK47LCDUploadPlanFingerprint.make(plan)
    lock.lock()
    defer { lock.unlock() }
    guard fingerprint == requestedFingerprint else {
      throw AK47LCDUploadAdapterError.authorizationMismatch
    }
    guard !consumed else {
      throw AK47LCDUploadAdapterError.authorizationAlreadyConsumed
    }
    consumed = true
  }
}

enum AK47LCDUploadPlanFingerprint {
  static func make(_ plan: AK47LCDUploadPlan) -> Data {
    var bytes = Data("KeyCanvas.AK47.LCD.plan.v1".utf8)
    append(plan.target.product, to: &bytes)
    append(plan.target.locationID, to: &bytes)
    append(plan.target.versionNumber, to: &bytes)
    append(plan.target.serialNumber, to: &bytes)

    let container = plan.container
    append(container.frameCount, to: &bytes)
    append(container.unpaddedByteCount, to: &bytes)
    append(container.pageCount, to: &bytes)
    append(container.paddingByte, to: &bytes)
    append(container.partitionBudgetByteCount, to: &bytes)
    append(container.sourceDelaysMilliseconds, to: &bytes)
    append(container.encodedDeviceDelays, to: &bytes)
    append(container.nominalEncodedDelaysMilliseconds, to: &bytes)
    append(container.effectiveDeviceDelaysMilliseconds, to: &bytes)
    append(container.firmwareMinimumAppliedFrameIndices, to: &bytes)
    append(container.data.count, to: &bytes)
    bytes.append(container.data)
    return Data(SHA256.hash(data: bytes))
  }

  static func hex(_ plan: AK47LCDUploadPlan) -> String {
    make(plan).map { String(format: "%02x", $0) }.joined()
  }

  private static func append(_ value: String, to data: inout Data) {
    let encoded = Data(value.utf8)
    append(encoded.count, to: &data)
    data.append(encoded)
  }

  private static func append(_ value: String?, to data: inout Data) {
    guard let value else {
      data.append(0)
      return
    }
    data.append(1)
    append(value, to: &data)
  }

  private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
  }

  private static func append<T: FixedWidthInteger>(_ values: [T], to data: inout Data) {
    append(values.count, to: &data)
    for value in values { append(value, to: &data) }
  }
}

protocol AK47LCDUploadLifecycleSession: AK47LCDUploadSession {
  func cancel() throws
}

protocol AK47LCDUploadSystemDriving: AnyObject {
  func makeSession(
    target: AK47WiredDeviceTarget,
    evidence: HIDDeviceTransactionEvidence
  ) throws -> any AK47LCDUploadLifecycleSession
  func verifyPostflight(target: AK47WiredDeviceTarget) throws
}

protocol AK47LCDUploadOperationGating: AnyObject {
  func acquire(target: HIDDeviceQuarantineIdentity) -> HIDDeviceOperationGateAcquireResult
  func acquire(
    target: HIDDeviceQuarantineIdentity,
    qualificationAdmission: AK47LCDQualificationGateAdmission?
  ) -> HIDDeviceOperationGateAcquireResult
  func makeEvidence() -> HIDDeviceTransactionEvidence
  func finish(succeeded: Bool, evidence: HIDDeviceTransactionEvidence) throws
}

protocol AK47LCDUploadActivityHolding: AnyObject {
  func end()
}

protocol AK47LCDUploadActivityProviding: AnyObject {
  func begin() -> any AK47LCDUploadActivityHolding
}

/// Process-wide lifecycle interlock for the single active LCD transaction.
/// App lifecycle observers call `recordLifecycleHazard()` before allowing
/// termination, system sleep, or power-off handling to continue.
package enum AK47LCDUploadLifecycleInterlock {
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var active: (generation: UInt64, evidence: HIDDeviceTransactionEvidence)?
    private var hazard = false

    var isActive: Bool {
      lock.lock()
      defer { lock.unlock() }
      return active != nil
    }

    func begin(evidence: HIDDeviceTransactionEvidence) throws -> UInt64 {
      lock.lock()
      defer { lock.unlock() }
      guard active == nil else { throw AK47LCDUploadAdapterError.deviceBusy }
      generation &+= 1
      active = (generation, evidence)
      hazard = false
      return generation
    }

    @discardableResult
    func recordHazard() -> Bool {
      lock.lock()
      guard let evidence = active?.evidence else {
        lock.unlock()
        return false
      }
      hazard = true
      lock.unlock()
      // Record outside the interlock lock; the evidence object is independently
      // synchronized and this immediately prevents successful marker cleanup.
      evidence.recordUnconfirmedCancellation()
      return true
    }

    func check() throws {
      lock.lock()
      let blocked = active != nil && hazard
      lock.unlock()
      if blocked { throw AK47LCDUploadAdapterError.lifecycleHazard }
    }

    func end(generation: UInt64) {
      lock.lock()
      if active?.generation == generation {
        active = nil
        hazard = false
      }
      lock.unlock()
    }

    func claimSuccess(
      generation: UInt64,
      finalize: () throws -> Void
    ) throws {
      lock.lock()
      guard active?.generation == generation, !hazard else {
        lock.unlock()
        throw AK47LCDUploadAdapterError.lifecycleHazard
      }
      do {
        // Keep the lifecycle lock through durable gate cleanup. A concurrent
        // hazard either wins before this claim (and blocks success) or waits
        // until the active transfer has been atomically retired.
        try finalize()
        active = nil
        hazard = false
        lock.unlock()
      } catch {
        lock.unlock()
        throw error
      }
    }
  }

  private static let state = State()

  package static var isTransferActive: Bool { state.isActive }

  @discardableResult
  package static func recordLifecycleHazard() -> Bool { state.recordHazard() }

  static func begin(evidence: HIDDeviceTransactionEvidence) throws -> UInt64 {
    try state.begin(evidence: evidence)
  }

  static func check() throws { try state.check() }

  static func claimSuccess(
    generation: UInt64,
    finalize: () throws -> Void
  ) throws {
    try state.claimSuccess(generation: generation, finalize: finalize)
  }

  static func end(generation: UInt64) { state.end(generation: generation) }
}

public enum AK47LCDUploadAdapter {
  /// SHA-256 of the project-authored 240×135 black diagnostic frame with
  /// 32×32 red/green/blue/white corner blocks and a 100 ms source delay.
  public static let firstExperimentContainerSHA256 =
    AK47LCDDiagnosticFixture.expectedContainerSHA256

  public static let enabledFrameCount = 1
  public static let enabledPageCount = 16
  public static let enabledContainerByteCount = 65_536
  public static let qualifiedMaximumFrameCount = 40
  public static let qualifiedMaximumPageCount = 633
  public static let qualifiedMaximumContainerByteCount = 2_592_768
  public static let qualifiedTransferEndAddressExclusive: UInt64 = 0x9B_9000

  /// Encodes the immutable editor snapshot with the same bounded budget and FF
  /// padding contract that the qualified live adapter independently enforces.
  public static func encodeQualifiedAnimation(
    _ project: AK47LCDAnimationProject
  ) throws -> AK47LCDEncodedContainer {
    guard (1...qualifiedMaximumFrameCount).contains(project.frames.count) else {
      throw AK47LCDUploadAdapterError.qualifiedFrameCountNotEnabled(project.frames.count)
    }
    return try AK47LCDContainerEncoder.encode(
      project: project,
      configuration: AK47LCDContainerEncoderConfiguration(
        partitionBudgetByteCount: qualifiedMaximumContainerByteCount,
        pagePadding: .erasedFlash
      )
    )
  }

  /// Runs only the fixed, one-frame diagnostic experiment. This synchronous
  /// entry point must be called from a worker queue, never an IOHID callback
  /// queue or the main actor. The Studio call site supplies only the canonical
  /// fixture after its separate one-use destructive confirmation.
  public static func uploadSingleFrame(
    plan: AK47LCDUploadPlan,
    authorization: AK47LCDUploadAuthorization,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void = { _, _ in }
  ) throws {
    try performCanonical(
      plan: plan,
      authorization: authorization,
      qualification: SystemAK47LCDExtendedUploadQualificationService(),
      driver: SystemAK47LCDUploadDriver(),
      gate: SystemAK47LCDUploadGate(),
      activityProvider: SystemAK47LCDUploadActivityProvider(),
      sleep: { milliseconds in
        Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000)
      },
      progress: progress
    )
  }

  /// Returns the immutable values the final confirmation sheet must show.
  /// The same exact checks run again before the adapter claims a live lease.
  public static func makeQualifiedPlanSummary(
    _ plan: AK47LCDUploadPlan
  ) throws -> AK47LCDQualifiedUploadPlanSummary {
    try AK47LCDUploadPreflight.validateStructuralModel(plan)
    try validateQualifiedAnimation(plan)
    return AK47LCDQualifiedUploadPlanSummary(plan: plan)
  }

  /// Runs a qualified 1...40-frame immutable editor snapshot. A durable
  /// qualification lease is claimed before any HID handle/report path can be
  /// reached, and host success remains pending until a separate visual result.
  public static func uploadQualifiedAnimation(
    plan: AK47LCDUploadPlan,
    authorization: AK47LCDQualifiedUploadAuthorization,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void = { _, _ in }
  ) throws {
    try performQualified(
      plan: plan,
      authorization: authorization,
      qualification: SystemAK47LCDExtendedUploadQualificationService(),
      driver: SystemAK47LCDUploadDriver(),
      gate: SystemAK47LCDUploadGate(),
      activityProvider: SystemAK47LCDUploadActivityProvider(),
      sleep: { milliseconds in
        Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000)
      },
      progress: progress
    )
  }

  static func perform(
    plan: AK47LCDUploadPlan,
    authorization: AK47LCDUploadAuthorization,
    driver: any AK47LCDUploadSystemDriving,
    gate: any AK47LCDUploadOperationGating,
    activityProvider: any AK47LCDUploadActivityProviding,
    sleep: @escaping AK47LCDUploadStateMachine.Sleep,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void = { _, _ in }
  ) throws {
    try authorization.consume(for: plan)
    try AK47LCDUploadPreflight.validateStructuralModel(plan)
    try validateFirstExperiment(plan)

    try performValidatedTransfer(
      plan: plan,
      driver: driver,
      gate: gate,
      activityProvider: activityProvider,
      sleep: sleep,
      progress: progress
    )
  }

  static func performCanonical(
    plan: AK47LCDUploadPlan,
    authorization: AK47LCDUploadAuthorization,
    qualification: any AK47LCDExtendedUploadQualificationServicing,
    driver: any AK47LCDUploadSystemDriving,
    gate: any AK47LCDUploadOperationGating,
    activityProvider: any AK47LCDUploadActivityProviding,
    sleep: @escaping AK47LCDUploadStateMachine.Sleep,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void = { _, _ in }
  ) throws {
    try AK47LCDUploadPreflight.validateStructuralModel(plan)
    try validateFirstExperiment(plan)
    try authorization.consume(for: plan)
    let lease = try qualification.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    do {
      try performValidatedTransfer(
        plan: plan,
        qualificationAdmission: lease.gateAdmission,
        driver: driver,
        gate: gate,
        activityProvider: activityProvider,
        sleep: sleep,
        progress: progress
      )
    } catch {
      let outcome: AK47LCDQualifiedUploadLeaseOutcome
      if let adapterError = error as? AK47LCDUploadAdapterError,
        case .partialTransactionQuarantined = adapterError
      {
        outcome = .submittedOrUncertainFailure
      } else {
        outcome = .failedBeforeSubmissionWithConfirmedCleanup
      }
      do {
        try qualification.finishCanonicalTransfer(lease, plan: plan, outcome: outcome)
      } catch {
        throw AK47LCDUploadAdapterError.qualificationLeaseFinalizationFailed
      }
      throw error
    }
    do {
      try qualification.finishCanonicalTransfer(lease, plan: plan, outcome: .succeeded)
    } catch {
      throw AK47LCDUploadAdapterError.qualificationReceiptNotRecordedAfterSuccessfulTransfer
    }
  }

  static func performQualified(
    plan: AK47LCDUploadPlan,
    authorization: AK47LCDQualifiedUploadAuthorization,
    qualification: any AK47LCDExtendedUploadQualificationServicing,
    driver: any AK47LCDUploadSystemDriving,
    gate: any AK47LCDUploadOperationGating,
    activityProvider: any AK47LCDUploadActivityProviding,
    sleep: @escaping AK47LCDUploadStateMachine.Sleep,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void = { _, _ in }
  ) throws {
    try AK47LCDUploadPreflight.validateStructuralModel(plan)
    try validateQualifiedAnimation(plan)
    try authorization.consume(for: plan)

    let lease = try qualification.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: AK47LCDUploadPlanFingerprint.hex(plan)
    )
    do {
      try performValidatedTransfer(
        plan: plan,
        qualificationAdmission: lease.gateAdmission,
        driver: driver,
        gate: gate,
        activityProvider: activityProvider,
        sleep: sleep,
        progress: progress
      )
    } catch {
      let outcome: AK47LCDQualifiedUploadLeaseOutcome
      if let adapterError = error as? AK47LCDUploadAdapterError,
        case .partialTransactionQuarantined = adapterError
      {
        outcome = .submittedOrUncertainFailure
      } else {
        outcome = .failedBeforeSubmissionWithConfirmedCleanup
      }
      do {
        try qualification.finishQualifiedLease(lease, outcome: outcome)
      } catch {
        throw AK47LCDUploadAdapterError.qualificationLeaseFinalizationFailed
      }
      throw error
    }

    do {
      try qualification.finishQualifiedLease(lease, outcome: .succeeded)
    } catch {
      throw AK47LCDUploadAdapterError.qualificationLeaseFinalizationFailed
    }
  }

  private static func performValidatedTransfer(
    plan: AK47LCDUploadPlan,
    qualificationAdmission: AK47LCDQualificationGateAdmission? = nil,
    driver: any AK47LCDUploadSystemDriving,
    gate: any AK47LCDUploadOperationGating,
    activityProvider: any AK47LCDUploadActivityProviding,
    sleep: @escaping AK47LCDUploadStateMachine.Sleep,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void
  ) throws {

    let activity = activityProvider.begin()
    defer { activity.end() }

    let targetIdentity = HIDDeviceQuarantineIdentity(target: plan.target)
    switch gate.acquire(
      target: targetIdentity,
      qualificationAdmission: qualificationAdmission
    ) {
    case .acquired:
      break
    case .busy:
      throw AK47LCDUploadAdapterError.deviceBusy
    case .quarantined:
      throw AK47LCDUploadAdapterError.operationGateQuarantined
    }

    let evidence = gate.makeEvidence()
    var gateFinalized = false
    defer {
      if !gateFinalized {
        try? gate.finish(succeeded: false, evidence: evidence)
      }
    }
    let lifecycleGeneration = try AK47LCDUploadLifecycleInterlock.begin(evidence: evidence)
    defer { AK47LCDUploadLifecycleInterlock.end(generation: lifecycleGeneration) }

    do {
      try AK47LCDUploadLifecycleInterlock.check()
      let session = try driver.makeSession(target: plan.target, evidence: evidence)
      do {
        try AK47LCDUploadStateMachine.execute(
          plan: plan,
          session: session,
          sleep: sleep,
          progress: progress
        )
      } catch let transactionError {
        do {
          try session.cancel()
          if !evidence.hasSubmittedReport {
            sleep(50)
            if (try? driver.verifyPostflight(target: plan.target)) != nil {
              evidence.recordSafePreSubmissionCleanup()
            }
          }
        } catch {
          evidence.recordUnconfirmedCancellation()
        }
        throw transactionError
      }

      do {
        try session.cancel()
      } catch {
        evidence.recordUnconfirmedCancellation()
        throw error
      }
      sleep(50)
      try driver.verifyPostflight(target: plan.target)
      try AK47LCDUploadLifecycleInterlock.check()
    } catch {
      let operationError = errorForFailedTransaction(error, evidence: evidence)
      do {
        try gate.finish(succeeded: false, evidence: evidence)
        gateFinalized = true
      } catch {
        gateFinalized = true
        throw AK47LCDUploadAdapterError.partialTransactionQuarantined(
          "durable quarantine finalization failed after: \(operationError.localizedDescription)"
        )
      }
      throw operationError
    }

    var successfulGateFinishAttempted = false
    do {
      try AK47LCDUploadLifecycleInterlock.claimSuccess(
        generation: lifecycleGeneration
      ) {
        successfulGateFinishAttempted = true
        try gate.finish(succeeded: true, evidence: evidence)
      }
      gateFinalized = true
    } catch {
      if successfulGateFinishAttempted {
        gateFinalized = true
        throw AK47LCDUploadAdapterError.partialTransactionQuarantined(
          "the transfer completed, but durable marker cleanup failed"
        )
      }
      let operationError = errorForFailedTransaction(error, evidence: evidence)
      do {
        try gate.finish(succeeded: false, evidence: evidence)
        gateFinalized = true
      } catch {
        gateFinalized = true
        throw AK47LCDUploadAdapterError.partialTransactionQuarantined(
          "durable quarantine finalization failed after: \(operationError.localizedDescription)"
        )
      }
      throw operationError
    }
  }

  static func validateFirstExperiment(_ plan: AK47LCDUploadPlan) throws {
    guard plan.container.frameCount == enabledFrameCount else {
      throw AK47LCDUploadAdapterError.liveFrameCountNotEnabled(plan.container.frameCount)
    }
    guard plan.container.pageCount == enabledPageCount else {
      throw AK47LCDUploadAdapterError.livePageCountNotEnabled(plan.container.pageCount)
    }
    guard plan.container.data.count == enabledContainerByteCount else {
      throw AK47LCDUploadAdapterError.liveContainerLengthNotEnabled(plan.container.data.count)
    }
    let digest = AK47LCDUploadDigest.sha256Hex(plan.container.data)
    guard digest == firstExperimentContainerSHA256 else {
      throw AK47LCDUploadAdapterError.fixtureNotAllowlisted
    }
  }

  static func validateQualifiedAnimation(_ plan: AK47LCDUploadPlan) throws {
    let container = plan.container
    guard (1...qualifiedMaximumFrameCount).contains(container.frameCount) else {
      throw AK47LCDUploadAdapterError.qualifiedFrameCountNotEnabled(container.frameCount)
    }

    let (frameBytes, frameOverflow) = container.frameCount.multipliedReportingOverflow(
      by: AK47LCDFormat.rgb565FrameByteCount
    )
    let (rawByteCount, rawOverflow) = AK47LCDFormat.headerByteCount
      .addingReportingOverflow(frameBytes)
    guard !frameOverflow, !rawOverflow else {
      throw AK47LCDUploadError.transferAddressOverflow
    }
    let (roundingNumerator, roundingOverflow) = rawByteCount.addingReportingOverflow(
      AK47LCDFormat.transferPageByteCount - 1
    )
    guard !roundingOverflow else { throw AK47LCDUploadError.transferAddressOverflow }
    let expectedPageCount = roundingNumerator / AK47LCDFormat.transferPageByteCount
    guard container.pageCount == expectedPageCount else {
      throw AK47LCDUploadAdapterError.qualifiedPageCountMismatch(
        expected: expectedPageCount,
        actual: container.pageCount
      )
    }
    guard expectedPageCount <= qualifiedMaximumPageCount else {
      throw AK47LCDUploadAdapterError.qualifiedPageCountMismatch(
        expected: qualifiedMaximumPageCount,
        actual: expectedPageCount
      )
    }
    let (expectedByteCount, paddedOverflow) = expectedPageCount.multipliedReportingOverflow(
      by: AK47LCDFormat.transferPageByteCount
    )
    guard !paddedOverflow else { throw AK47LCDUploadError.transferAddressOverflow }
    guard expectedByteCount <= qualifiedMaximumContainerByteCount,
      container.partitionBudgetByteCount <= qualifiedMaximumContainerByteCount
    else {
      throw AK47LCDUploadError.partitionBudgetMismatch
    }
    guard container.data.count == expectedByteCount else {
      throw AK47LCDUploadAdapterError.qualifiedContainerLengthMismatch(
        expected: expectedByteCount,
        actual: container.data.count
      )
    }
    let (actualEnd, endOverflow) = AK47LCDUploadPreflight.externalFlashStartAddress
      .addingReportingOverflow(UInt64(container.data.count))
    guard !endOverflow else { throw AK47LCDUploadError.transferAddressOverflow }
    let expectedEnd = AK47LCDUploadPreflight.externalFlashStartAddress + UInt64(expectedByteCount)
    guard actualEnd == expectedEnd, actualEnd <= qualifiedTransferEndAddressExclusive else {
      throw AK47LCDUploadAdapterError.qualifiedTransferEndMismatch(
        expected: min(expectedEnd, qualifiedTransferEndAddressExclusive),
        actual: actualEnd
      )
    }

    var expectedMinimumIndices: [Int] = []
    for index in 0..<container.frameCount {
      let sourceDelay: AK47LCDSourceDelay
      let deviceDelay: AK47LCDDeviceDelay
      do {
        sourceDelay = try AK47LCDSourceDelay(
          milliseconds: container.sourceDelaysMilliseconds[index]
        )
        deviceDelay = try AK47LCDDeviceDelay(verifiedSourceDelay: sourceDelay)
      } catch {
        throw AK47LCDUploadError.delayMetadataMismatch
      }
      guard container.encodedDeviceDelays[index] == deviceDelay.rawValue,
        container.nominalEncodedDelaysMilliseconds[index] == deviceDelay.nominalMilliseconds,
        container.effectiveDeviceDelaysMilliseconds[index]
          == deviceDelay.effectiveFirmwareMilliseconds
      else {
        throw AK47LCDUploadError.delayMetadataMismatch
      }
      if deviceDelay.usesFirmwareMinimum { expectedMinimumIndices.append(index) }
    }
    guard container.firmwareMinimumAppliedFrameIndices == expectedMinimumIndices else {
      throw AK47LCDUploadError.delayMetadataMismatch
    }
  }

  static func errorForFailedTransaction(
    _ error: Error,
    evidence: HIDDeviceTransactionEvidence
  ) -> Error {
    guard evidence.failureRequiresPhysicalRecovery else { return error }
    if let adapterError = error as? AK47LCDUploadAdapterError,
      case .partialTransactionQuarantined = adapterError
    {
      return error
    }
    return AK47LCDUploadAdapterError.partialTransactionQuarantined(error.localizedDescription)
  }
}

private final class SystemAK47LCDUploadActivity: AK47LCDUploadActivityHolding {
  private let lock = NSLock()
  private var token: NSObjectProtocol?

  init() {
    token = ProcessInfo.processInfo.beginActivity(
      options: [
        .userInitiated,
        .idleSystemSleepDisabled,
        .suddenTerminationDisabled,
        .automaticTerminationDisabled,
      ],
      reason: "KeyCanvas bounded AK47 LCD transfer"
    )
  }

  func end() {
    lock.lock()
    let current = token
    token = nil
    lock.unlock()
    if let current { ProcessInfo.processInfo.endActivity(current) }
  }

  deinit { end() }
}

private final class SystemAK47LCDUploadActivityProvider: AK47LCDUploadActivityProviding {
  func begin() -> any AK47LCDUploadActivityHolding {
    SystemAK47LCDUploadActivity()
  }
}

private final class SystemAK47LCDUploadGate: AK47LCDUploadOperationGating {
  func acquire(target: HIDDeviceQuarantineIdentity) -> HIDDeviceOperationGateAcquireResult {
    HIDDeviceOperationGate.acquireResult(for: target)
  }

  func acquire(
    target: HIDDeviceQuarantineIdentity,
    qualificationAdmission: AK47LCDQualificationGateAdmission?
  ) -> HIDDeviceOperationGateAcquireResult {
    HIDDeviceOperationGate.acquireResult(
      for: target,
      qualificationAdmission: qualificationAdmission
    )
  }

  func makeEvidence() -> HIDDeviceTransactionEvidence {
    HIDDeviceOperationGate.makeTransactionEvidence()
  }

  func finish(succeeded: Bool, evidence: HIDDeviceTransactionEvidence) throws {
    try HIDDeviceOperationGate.finish(succeeded: succeeded, evidence: evidence)
  }
}

private final class SystemAK47LCDExtendedUploadQualificationService:
  AK47LCDExtendedUploadQualificationServicing
{
  func claimCanonicalTransfer(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDCanonicalTransferLease {
    try AK47LCDExtendedUploadQualification.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: planFingerprintSHA256
    )
  }

  func finishCanonicalTransfer(
    _ lease: AK47LCDCanonicalTransferLease,
    plan: AK47LCDUploadPlan,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws {
    try AK47LCDExtendedUploadQualification.finishCanonicalTransfer(
      lease,
      plan: plan,
      outcome: outcome
    )
  }

  func claimQualifiedLease(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDQualifiedUploadLease {
    try AK47LCDExtendedUploadQualification.claimQualifiedLease(
      plan: plan,
      planFingerprintSHA256: planFingerprintSHA256
    )
  }

  func finishQualifiedLease(
    _ lease: AK47LCDQualifiedUploadLease,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws {
    try AK47LCDExtendedUploadQualification.finishQualifiedLease(lease, outcome: outcome)
  }
}

struct AK47LCDUSBAncestryProof: Equatable, Sendable {
  let interfaceNumber: UInt64?
  let physicalParentRegistryID: UInt64
  let vendorID: UInt64
  let productID: UInt64
  let locationID: UInt64
}

struct AK47LCDSystemTopology {
  struct Selection: Equatable {
    let featureIndex: Int
    let outputIndex: Int
  }

  private struct Signature: Hashable {
    let usagePage: UInt64
    let usage: UInt64
    let input: UInt64
    let output: UInt64
    let feature: UInt64
  }

  private static let expected: Set<Signature> = [
    Signature(usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
    Signature(usagePage: 0x000C, usage: 0x0001, input: 16, output: 1, feature: 1),
    Signature(usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64, feature: 64),
    Signature(usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096, feature: 0),
  ]

  static func select(
    records: [HIDCollectionRecord],
    ancestryProofs: [AK47LCDUSBAncestryProof],
    target: AK47WiredDeviceTarget
  ) throws -> Selection {
    try target.validate()
    guard ancestryProofs.count == records.count else {
      throw AK47LCDUploadAdapterError.usbAncestryMismatch
    }
    let exact = records.enumerated().filter { _, record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == target.product
        && record.transport == "USB"
        && record.locationID == target.locationID
        && record.versionNumber == target.versionNumber
        && (target.serialNumber == nil || record.serialNumber == target.serialNumber)
    }
    guard exact.count == 4 else {
      throw AK47LCDUploadAdapterError.unexpectedTopology(collections: exact.count)
    }
    guard Set(exact.map { $0.element.serialNumber }).count == 1 else {
      throw AK47LCDUploadAdapterError.unexpectedTopology(collections: exact.count)
    }

    let signatures = Set(
      exact.compactMap { _, record -> Signature? in
        guard let usagePage = record.usagePage,
          let usage = record.usage,
          let input = record.maxInputReportSize,
          let output = record.maxOutputReportSize,
          let feature = record.maxFeatureReportSize
        else { return nil }
        return Signature(
          usagePage: usagePage,
          usage: usage,
          input: input,
          output: output,
          feature: feature
        )
      })
    guard signatures == expected else {
      throw AK47LCDUploadAdapterError.unexpectedTopology(collections: exact.count)
    }

    let features = exact.filter { _, record in
      record.usagePage == 0xFF13 && record.usage == 0x0001
        && record.maxInputReportSize == 64 && record.maxOutputReportSize == 64
        && record.maxFeatureReportSize == 64
    }
    let outputs = exact.filter { _, record in
      record.usagePage == 0xFF68 && record.usage == 0x0061
        && record.maxInputReportSize == 64 && record.maxOutputReportSize == 4_096
        && record.maxFeatureReportSize == 0
    }
    guard !features.isEmpty else {
      throw AK47LCDUploadAdapterError.noMatchingFeatureCollection
    }
    guard features.count == 1 else {
      throw AK47LCDUploadAdapterError.ambiguousFeatureCollections(features.count)
    }
    guard !outputs.isEmpty else {
      throw AK47LCDUploadAdapterError.noMatchingOutputCollection
    }
    guard outputs.count == 1 else {
      throw AK47LCDUploadAdapterError.ambiguousOutputCollections(outputs.count)
    }
    let featureIndex = features[0].offset
    let outputIndex = outputs[0].offset
    let featureProof = ancestryProofs[featureIndex]
    let outputProof = ancestryProofs[outputIndex]
    guard featureProof.interfaceNumber == 3,
      outputProof.interfaceNumber == 2,
      featureProof.physicalParentRegistryID == outputProof.physicalParentRegistryID,
      featureProof.vendorID == HIDEnumerator.vendorID,
      outputProof.vendorID == HIDEnumerator.vendorID,
      featureProof.productID == HIDEnumerator.productID,
      outputProof.productID == HIDEnumerator.productID,
      featureProof.locationID == target.locationID,
      outputProof.locationID == target.locationID
    else {
      throw AK47LCDUploadAdapterError.usbAncestryMismatch
    }
    return Selection(featureIndex: featureIndex, outputIndex: outputIndex)
  }
}

private enum SystemAK47LCDUSBAncestryInspector {
  static func inspect(_ device: IOHIDDevice) throws -> AK47LCDUSBAncestryProof {
    let service = IOHIDDeviceGetService(device)
    guard service != 0 else { throw AK47LCDUploadAdapterError.usbAncestryMismatch }

    var current = service
    var ownsCurrent = false
    var interfaceNumber: UInt64?
    defer {
      if ownsCurrent { IOObjectRelease(current) }
    }

    for _ in 0..<32 {
      if interfaceNumber == nil {
        interfaceNumber = numberProperty("bInterfaceNumber", entry: current)
      }
      if IOObjectConformsTo(current, "IOUSBHostDevice") != 0 {
        var registryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(current, &registryID) == kIOReturnSuccess,
          let vendorID = numberProperty("idVendor", entry: current),
          let productID = numberProperty("idProduct", entry: current),
          let locationID = numberProperty("locationID", entry: current)
        else {
          throw AK47LCDUploadAdapterError.usbAncestryMismatch
        }
        return AK47LCDUSBAncestryProof(
          interfaceNumber: interfaceNumber,
          physicalParentRegistryID: registryID,
          vendorID: vendorID,
          productID: productID,
          locationID: locationID
        )
      }

      var parent: io_registry_entry_t = 0
      guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == kIOReturnSuccess,
        parent != 0
      else {
        throw AK47LCDUploadAdapterError.usbAncestryMismatch
      }
      if ownsCurrent { IOObjectRelease(current) }
      current = parent
      ownsCurrent = true
    }
    throw AK47LCDUploadAdapterError.usbAncestryMismatch
  }

  private static func numberProperty(_ key: String, entry: io_registry_entry_t) -> UInt64? {
    guard
      let value = IORegistryEntryCreateCFProperty(
        entry,
        key as CFString,
        kCFAllocatorDefault,
        IOOptionBits(0)
      )?.takeRetainedValue() as? NSNumber
    else { return nil }
    return value.uint64Value
  }
}

private final class SystemAK47LCDUploadDriver: AK47LCDUploadSystemDriving {
  func makeSession(
    target: AK47WiredDeviceTarget,
    evidence: HIDDeviceTransactionEvidence
  ) throws -> any AK47LCDUploadLifecycleSession {
    let orderedDevices = try Self.matchingDevices()
    let records = orderedDevices.map(Self.makeRecord)
    let ancestryProofs = try orderedDevices.map(SystemAK47LCDUSBAncestryInspector.inspect)
    let selection = try AK47LCDSystemTopology.select(
      records: records,
      ancestryProofs: ancestryProofs,
      target: target
    )
    let featureDevice = orderedDevices[selection.featureIndex]
    let outputDevice = orderedDevices[selection.outputIndex]

    let featureOpen = IOHIDDeviceOpen(featureDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    guard featureOpen == kIOReturnSuccess else {
      throw AK47LCDUploadAdapterError.openFailed(
        collection: "FF13",
        code: UInt32(bitPattern: featureOpen)
      )
    }
    let outputOpen = IOHIDDeviceOpen(outputDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    guard outputOpen == kIOReturnSuccess else {
      _ = IOHIDDeviceClose(featureDevice, IOOptionBits(kIOHIDOptionsTypeNone))
      throw AK47LCDUploadAdapterError.openFailed(
        collection: "FF68",
        code: UInt32(bitPattern: outputOpen)
      )
    }
    return SystemAK47LCDUploadSession(
      featureDevice: featureDevice,
      outputDevice: outputDevice,
      evidence: evidence
    )
  }

  func verifyPostflight(target: AK47WiredDeviceTarget) throws {
    do {
      let devices = try Self.matchingDevices()
      _ = try AK47LCDSystemTopology.select(
        records: devices.map(Self.makeRecord),
        ancestryProofs: try devices.map(SystemAK47LCDUSBAncestryInspector.inspect),
        target: target
      )
    } catch {
      throw AK47LCDUploadAdapterError.postflightIdentityLost
    }
  }

  private static func matchingDevices() throws -> [IOHIDDevice] {
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
      throw AK47LCDUploadAdapterError.noMatchingFeatureCollection
    }
    return Array(devices)
  }

  private static func makeRecord(_ device: IOHIDDevice) -> HIDCollectionRecord {
    HIDCollectionRecord(
      // Missing registry identity must fail closed; never synthesize the
      // expected VID/PID for a partially described collection.
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
}

private final class AK47LCDAsyncReportOperation: @unchecked Sendable {
  let capacity: Int
  let buffer: UnsafeMutablePointer<UInt8>
  let reportLength: UnsafeMutablePointer<CFIndex>
  let completion = DispatchSemaphore(value: 0)
  var result: IOReturn = kIOReturnError
  var completedLength = 0
  var completedType = kIOHIDReportTypeInput
  var completedReportID: UInt32 = UInt32.max

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

  func complete(
    result: IOReturn,
    reportType: IOHIDReportType,
    reportID: UInt32,
    reportLength: CFIndex
  ) {
    self.result = result
    completedType = reportType
    completedReportID = reportID
    completedLength = reportLength
    completion.signal()
  }

  func bytes(count: Int) -> [UInt8] {
    Array(UnsafeBufferPointer(start: buffer, count: count))
  }
}

enum AK47LCDAsyncReportCompletionDirection: Equatable {
  case set
  case get
}

/// Validates only fields whose callback contract carries completion meaning.
/// The asynchronous HID Set API takes the submitted byte count as an input
/// argument, but its generic completion callback does not define the
/// callback `reportLength` as a transferred-byte count. macOS returns zero for
/// successful Feature SET completions on the verified path. GET completion
/// length still describes the returned buffer and remains exact-checked.
enum AK47LCDAsyncReportCompletionValidator {
  static func validate(
    stage: AK47LCDUploadStage,
    completedType: IOHIDReportType,
    completedReportID: UInt32,
    completedLength: Int,
    expectedType: IOHIDReportType,
    expectedLength: Int,
    direction: AK47LCDAsyncReportCompletionDirection
  ) throws {
    guard completedType == expectedType,
      completedReportID == UInt32(AK47LCDUploadStateMachine.reportID)
    else {
      throw AK47LCDUploadAdapterError.unexpectedCompletion(stage: stage)
    }
    guard direction == .get else { return }
    guard completedLength == expectedLength else {
      throw AK47LCDUploadError.invalidReportLength(
        stage: stage,
        expected: expectedLength,
        actual: completedLength
      )
    }
  }
}

private let ak47LCDAsyncReportCallback: IOHIDReportCallback = {
  context,
  result,
  _sender,
  reportType,
  reportID,
  _report,
  reportLength in
  guard let context else { return }
  let operation = Unmanaged<AK47LCDAsyncReportOperation>
    .fromOpaque(context)
    .takeRetainedValue()
  operation.complete(
    result: result,
    reportType: reportType,
    reportID: reportID,
    reportLength: reportLength
  )
}

final class AK47LCDInputReportDispatcher: @unchecked Sendable {
  enum PendingState {
    case prepared
    case submitted
    case completed
  }

  final class Pending: @unchecked Sendable {
    let generation: UInt64
    let completion = DispatchSemaphore(value: 0)
    var state: PendingState = .prepared
    var result: Result<AK47LCDInputAcknowledgement, Error>?

    init(generation: UInt64) { self.generation = generation }
  }

  static let reportLength = 64
  let buffer: UnsafeMutablePointer<UInt8>
  private let lock = NSLock()
  private var nextGeneration: UInt64 = 0
  private var pending: Pending?
  private var fatalInputError: Error?

  init() {
    buffer = .allocate(capacity: Self.reportLength)
    buffer.initialize(repeating: 0, count: Self.reportLength)
  }

  deinit {
    buffer.deinitialize(count: Self.reportLength)
    buffer.deallocate()
  }

  func prepareForOutput() throws -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    if let fatalInputError { throw fatalInputError }
    guard pending == nil else {
      throw AK47LCDUploadAdapterError.inputCallbackGenerationMismatch
    }
    nextGeneration &+= 1
    let item = Pending(generation: nextGeneration)
    pending = item
    return item.generation
  }

  func markSubmitted(generation: UInt64) throws {
    lock.lock()
    defer { lock.unlock() }
    if let fatalInputError { throw fatalInputError }
    guard let pending, pending.generation == generation, pending.state == .prepared else {
      throw AK47LCDUploadAdapterError.inputCallbackGenerationMismatch
    }
    pending.state = .submitted
  }

  func cancel(generation: UInt64) {
    lock.lock()
    if pending?.generation == generation { pending = nil }
    lock.unlock()
  }

  func receive(
    result: IOReturn,
    reportType: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
  ) {
    lock.lock()
    guard let pending else {
      latchUnexpectedInputLocked()
      lock.unlock()
      return
    }
    guard pending.state == .submitted, pending.result == nil else {
      latchUnexpectedInputLocked()
      lock.unlock()
      return
    }

    if result != kIOReturnSuccess {
      pending.result = .failure(
        AK47LCDUploadAdapterError.inputReportFailed(code: UInt32(bitPattern: result))
      )
    } else if reportType != kIOHIDReportTypeInput {
      pending.result = .failure(AK47LCDUploadAdapterError.inputReportTypeMismatch)
    } else if reportID != UInt32(AK47LCDUploadStateMachine.reportID) {
      pending.result = .failure(AK47LCDUploadAdapterError.inputReportIDMismatch(reportID))
    } else if reportLength < 0 || reportLength > Self.reportLength {
      pending.result = .success(
        AK47LCDInputAcknowledgement(reportID: AK47LCDUploadStateMachine.reportID, bytes: [])
      )
    } else {
      pending.result = .success(
        AK47LCDInputAcknowledgement(
          reportID: AK47LCDUploadStateMachine.reportID,
          bytes: Array(UnsafeBufferPointer(start: report, count: reportLength))
        )
      )
    }
    pending.state = .completed
    lock.unlock()
    pending.completion.signal()
  }

  func deviceRemoved(result: IOReturn) {
    lock.lock()
    guard let pending, pending.result == nil else {
      fatalInputError = AK47LCDUploadAdapterError.inputReportFailed(
        code: UInt32(bitPattern: result)
      )
      lock.unlock()
      return
    }
    pending.result = .failure(
      AK47LCDUploadAdapterError.inputReportFailed(code: UInt32(bitPattern: result))
    )
    pending.state = .completed
    lock.unlock()
    pending.completion.signal()
  }

  func wait(generation: UInt64, timeoutMilliseconds: Int) throws
    -> AK47LCDInputAcknowledgement
  {
    lock.lock()
    guard let item = pending, item.generation == generation else {
      lock.unlock()
      throw AK47LCDUploadAdapterError.inputCallbackGenerationMismatch
    }
    lock.unlock()

    guard item.completion.wait(timeout: .now() + .milliseconds(timeoutMilliseconds)) == .success
    else {
      cancel(generation: generation)
      throw AK47LCDUploadAdapterError.operationTimedOut(stage: .page(Int(generation - 1)))
    }
    lock.lock()
    if let fatalInputError {
      pending = nil
      lock.unlock()
      throw fatalInputError
    }
    guard let current = pending, current === item, let result = item.result else {
      lock.unlock()
      throw AK47LCDUploadAdapterError.inputCallbackGenerationMismatch
    }
    pending = nil
    lock.unlock()
    return try result.get()
  }

  func checkForUnexpectedInput() throws {
    lock.lock()
    let error = fatalInputError
    lock.unlock()
    if let error { throw error }
  }

  private func latchUnexpectedInputLocked() {
    guard fatalInputError == nil else { return }
    fatalInputError = AK47LCDUploadAdapterError.unexpectedInputAcknowledgement
  }
}

private let ak47LCDInputReportCallback: IOHIDReportCallback = {
  context,
  result,
  _sender,
  reportType,
  reportID,
  report,
  reportLength in
  guard let context else { return }
  Unmanaged<AK47LCDInputReportDispatcher>
    .fromOpaque(context)
    .takeUnretainedValue()
    .receive(
      result: result,
      reportType: reportType,
      reportID: reportID,
      report: report,
      reportLength: reportLength
    )
}

private let ak47LCDRemovalCallback: IOHIDCallback = { context, result, _sender in
  guard let context else { return }
  Unmanaged<AK47LCDInputReportDispatcher>
    .fromOpaque(context)
    .takeUnretainedValue()
    .deviceRemoved(result: result)
}

/// Serializes the last safety checks with the actual report submission. Any
/// input/removal callback already queued runs first; none can interleave between
/// the fatal-state check and the caller's submission closure.
enum AK47LCDCallbackSubmissionBarrier {
  static func sync<T>(
    queue: DispatchQueue,
    dispatcher: AK47LCDInputReportDispatcher,
    submit: () throws -> T
  ) throws -> T {
    var outcome: Result<T, Error>?
    queue.sync {
      do {
        try AK47LCDUploadLifecycleInterlock.check()
        try dispatcher.checkForUnexpectedInput()
        outcome = .success(try submit())
      } catch {
        outcome = .failure(error)
      }
    }
    guard let outcome else {
      throw AK47LCDUploadAdapterError.unexpectedInputAcknowledgement
    }
    return try outcome.get()
  }
}

private final class SystemAK47LCDUploadSession: AK47LCDUploadLifecycleSession {
  private static let operationTimeoutMilliseconds: CFTimeInterval = 360
  private static let completionWaitMilliseconds = 500
  private static let inputWaitMilliseconds = 300

  private let featureDevice: IOHIDDevice
  private let outputDevice: IOHIDDevice
  private let evidence: HIDDeviceTransactionEvidence
  private let callbackQueue = DispatchQueue(label: "io.keycanvas.ak47.lcd-upload-callbacks")
  private let inputDispatcher = AK47LCDInputReportDispatcher()
  private let featureCancellation = DispatchSemaphore(value: 0)
  private let outputCancellation = DispatchSemaphore(value: 0)
  private var activeOutputGeneration: UInt64?
  private enum CancellationState { case active, confirmed, timedOut }
  private var cancellationState = CancellationState.active

  init(
    featureDevice: IOHIDDevice,
    outputDevice: IOHIDDevice,
    evidence: HIDDeviceTransactionEvidence
  ) {
    self.featureDevice = featureDevice
    self.outputDevice = outputDevice
    self.evidence = evidence

    let featureContext = Unmanaged.passRetained(inputDispatcher).toOpaque()
    let outputContext = Unmanaged.passRetained(inputDispatcher).toOpaque()
    let featureCancellation = featureCancellation
    let outputCancellation = outputCancellation

    IOHIDDeviceSetDispatchQueue(featureDevice, callbackQueue)
    IOHIDDeviceRegisterRemovalCallback(featureDevice, ak47LCDRemovalCallback, featureContext)
    IOHIDDeviceSetCancelHandler(featureDevice) {
      _ = IOHIDDeviceClose(featureDevice, IOOptionBits(kIOHIDOptionsTypeNone))
      Unmanaged<AK47LCDInputReportDispatcher>.fromOpaque(featureContext).release()
      featureCancellation.signal()
    }

    IOHIDDeviceSetDispatchQueue(outputDevice, callbackQueue)
    IOHIDDeviceRegisterRemovalCallback(outputDevice, ak47LCDRemovalCallback, outputContext)
    IOHIDDeviceRegisterInputReportCallback(
      outputDevice,
      inputDispatcher.buffer,
      AK47LCDInputReportDispatcher.reportLength,
      ak47LCDInputReportCallback,
      outputContext
    )
    IOHIDDeviceSetCancelHandler(outputDevice) {
      _ = IOHIDDeviceClose(outputDevice, IOOptionBits(kIOHIDOptionsTypeNone))
      Unmanaged<AK47LCDInputReportDispatcher>.fromOpaque(outputContext).release()
      outputCancellation.signal()
    }

    // Every Register call above intentionally precedes activation. The public
    // HID collection maps logical FF68 Output/Input reports to the captured
    // transport, but this code neither selects nor claims numeric USB endpoints.
    IOHIDDeviceActivate(featureDevice)
    IOHIDDeviceActivate(outputDevice)
  }

  func cancel() throws {
    switch cancellationState {
    case .confirmed: return
    case .timedOut: throw AK47LCDUploadAdapterError.sessionCancellationTimedOut
    case .active: break
    }
    IOHIDDeviceCancel(featureDevice)
    IOHIDDeviceCancel(outputDevice)
    let deadline = DispatchTime.now() + .milliseconds(Self.completionWaitMilliseconds)
    let featureResult = featureCancellation.wait(timeout: deadline)
    let outputResult = outputCancellation.wait(timeout: deadline)
    guard featureResult == .success, outputResult == .success else {
      cancellationState = .timedOut
      throw AK47LCDUploadAdapterError.sessionCancellationTimedOut
    }
    cancellationState = .confirmed
    // Both cancel handlers run only after the serial callback queue drains.
    // A duplicate final ACK queued before cancellation is therefore fatal.
    try inputDispatcher.checkForUnexpectedInput()
    try AK47LCDUploadLifecycleInterlock.check()
  }

  func setFeature(_ bytes: [UInt8], stage: AK47LCDUploadStage) throws {
    guard bytes.count == AK47LCDUploadStateMachine.featureReportLength else {
      throw AK47LCDUploadError.invalidReportLength(
        stage: stage,
        expected: AK47LCDUploadStateMachine.featureReportLength,
        actual: bytes.count
      )
    }
    let operation = AK47LCDAsyncReportOperation(bytes: bytes)
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submission: IOReturn
    do {
      submission = try AK47LCDCallbackSubmissionBarrier.sync(
        queue: callbackQueue,
        dispatcher: inputDispatcher
      ) {
        try prepareDurableEvidence()
        let result = IOHIDDeviceSetReportWithCallback(
          featureDevice,
          kIOHIDReportTypeFeature,
          CFIndex(AK47LCDUploadStateMachine.reportID),
          operation.buffer,
          bytes.count,
          Self.operationTimeoutMilliseconds,
          ak47LCDAsyncReportCallback,
          context
        )
        if result == kIOReturnSuccess { evidence.recordSubmittedReport() }
        return result
      }
    } catch {
      Unmanaged<AK47LCDAsyncReportOperation>.fromOpaque(context).release()
      throw error
    }
    try awaitCompletion(
      operation,
      context: context,
      submission: submission,
      expectedType: kIOHIDReportTypeFeature,
      expectedLength: bytes.count,
      direction: .set,
      stage: stage
    )
  }

  func getFeature(expectedLength: Int, stage: AK47LCDUploadStage) throws -> [UInt8] {
    let operation = AK47LCDAsyncReportOperation(
      bytes: [UInt8](repeating: 0, count: expectedLength)
    )
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submission: IOReturn
    do {
      submission = try AK47LCDCallbackSubmissionBarrier.sync(
        queue: callbackQueue,
        dispatcher: inputDispatcher
      ) {
        try prepareDurableEvidence()
        let result = IOHIDDeviceGetReportWithCallback(
          featureDevice,
          kIOHIDReportTypeFeature,
          CFIndex(AK47LCDUploadStateMachine.reportID),
          operation.buffer,
          operation.reportLength,
          Self.operationTimeoutMilliseconds,
          ak47LCDAsyncReportCallback,
          context
        )
        if result == kIOReturnSuccess { evidence.recordSubmittedReport() }
        return result
      }
    } catch {
      Unmanaged<AK47LCDAsyncReportOperation>.fromOpaque(context).release()
      throw error
    }
    try awaitCompletion(
      operation,
      context: context,
      submission: submission,
      expectedType: kIOHIDReportTypeFeature,
      expectedLength: expectedLength,
      direction: .get,
      stage: stage
    )
    return operation.bytes(count: operation.completedLength)
  }

  func setOutput(
    _ bytes: [UInt8],
    reportID: UInt8,
    stage: AK47LCDUploadStage
  ) throws {
    guard reportID == AK47LCDUploadStateMachine.reportID else {
      throw AK47LCDUploadError.outputReportIDMismatch(stage: stage, actual: reportID)
    }
    guard bytes.count == AK47LCDUploadStateMachine.outputReportLength else {
      throw AK47LCDUploadError.invalidReportLength(
        stage: stage,
        expected: AK47LCDUploadStateMachine.outputReportLength,
        actual: bytes.count
      )
    }
    let operation = AK47LCDAsyncReportOperation(bytes: bytes)
    let context = Unmanaged.passRetained(operation).toOpaque()
    let submission: IOReturn
    let generation: UInt64
    var submissionWasAccepted = false
    do {
      (submission, generation) = try AK47LCDCallbackSubmissionBarrier.sync(
        queue: callbackQueue,
        dispatcher: inputDispatcher
      ) {
        let generation = try inputDispatcher.prepareForOutput()
        do {
          try prepareDurableEvidence()
        } catch {
          inputDispatcher.cancel(generation: generation)
          throw error
        }
        let result = IOHIDDeviceSetReportWithCallback(
          outputDevice,
          kIOHIDReportTypeOutput,
          CFIndex(reportID),
          operation.buffer,
          bytes.count,
          Self.operationTimeoutMilliseconds,
          ak47LCDAsyncReportCallback,
          context
        )
        if result == kIOReturnSuccess {
          submissionWasAccepted = true
          evidence.recordSubmittedReport()
          try inputDispatcher.markSubmitted(generation: generation)
        }
        return (result, generation)
      }
    } catch {
      if !submissionWasAccepted {
        Unmanaged<AK47LCDAsyncReportOperation>.fromOpaque(context).release()
      }
      throw error
    }
    activeOutputGeneration = generation
    do {
      try awaitCompletion(
        operation,
        context: context,
        submission: submission,
        expectedType: kIOHIDReportTypeOutput,
        expectedLength: bytes.count,
        direction: .set,
        stage: stage
      )
    } catch {
      if submission != kIOReturnSuccess {
        inputDispatcher.cancel(generation: generation)
        activeOutputGeneration = nil
      }
      throw error
    }
  }

  func getInputAcknowledgement(stage: AK47LCDUploadStage) throws
    -> AK47LCDInputAcknowledgement
  {
    guard let generation = activeOutputGeneration else {
      throw AK47LCDUploadAdapterError.inputCallbackNotPrepared
    }
    defer { activeOutputGeneration = nil }
    do {
      return try inputDispatcher.wait(
        generation: generation,
        timeoutMilliseconds: Self.inputWaitMilliseconds
      )
    } catch AK47LCDUploadAdapterError.operationTimedOut {
      throw AK47LCDUploadAdapterError.operationTimedOut(stage: stage)
    }
  }

  private func prepareDurableEvidence() throws {
    do {
      try evidence.prepareForSubmission()
    } catch {
      throw AK47LCDUploadAdapterError.quarantinePersistenceFailed
    }
  }

  private func awaitCompletion(
    _ operation: AK47LCDAsyncReportOperation,
    context: UnsafeMutableRawPointer,
    submission: IOReturn,
    expectedType: IOHIDReportType,
    expectedLength: Int,
    direction: AK47LCDAsyncReportCompletionDirection,
    stage: AK47LCDUploadStage
  ) throws {
    guard submission == kIOReturnSuccess else {
      Unmanaged<AK47LCDAsyncReportOperation>.fromOpaque(context).release()
      throw AK47LCDUploadAdapterError.operationFailed(
        stage: stage,
        code: UInt32(bitPattern: submission)
      )
    }
    guard
      operation.completion.wait(
        timeout: .now() + .milliseconds(Self.completionWaitMilliseconds)
      ) == .success
    else {
      throw AK47LCDUploadAdapterError.operationTimedOut(stage: stage)
    }
    guard operation.result == kIOReturnSuccess else {
      if operation.result == kIOReturnTimeout {
        throw AK47LCDUploadAdapterError.operationTimedOut(stage: stage)
      }
      throw AK47LCDUploadAdapterError.operationFailed(
        stage: stage,
        code: UInt32(bitPattern: operation.result)
      )
    }
    try AK47LCDAsyncReportCompletionValidator.validate(
      stage: stage,
      completedType: operation.completedType,
      completedReportID: operation.completedReportID,
      completedLength: operation.completedLength,
      expectedType: expectedType,
      expectedLength: expectedLength,
      direction: direction
    )
  }
}
