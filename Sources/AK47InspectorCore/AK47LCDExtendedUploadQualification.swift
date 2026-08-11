import CryptoKit
import Darwin
import Foundation

/// Durable authority state for the deliberately bounded 1...40-frame LCD path.
///
/// A previous live result, a checkbox, or the absence of a quarantine marker is
/// never authority. Qualification starts only when a receipt-enabled build
/// contemporaneously records a successful canonical one-frame transaction.
package enum AK47LCDExtendedUploadQualificationState: Equatable, Sendable {
  case unavailable
  case persistenceUnavailable
  case awaitingCanonicalFixtureVisualAttestation
  case awaitingObservedUSBDisconnection
  case awaitingExactSamePortReappearance
  case awaitingUSBPowerCycleAttestation
  case qualified(maximumFrameCount: Int)
  case canonicalTransferInProgress
  case canonicalVisualMismatchQuarantinePending
  case extendedTransferInProgress
  case awaitingExtendedVisualAttestation
  case extendedVisualMismatchQuarantinePending
  case interruptedTransferQuarantinePending
  case invalidatedRequiresFreshDiagnostic
}

package struct AK47LCDExtendedUploadQualificationSnapshot: Equatable, Sendable {
  package let target: AK47WiredDeviceTarget?
  package let state: AK47LCDExtendedUploadQualificationState
  package let pendingContainerSHA256: String?
  package let pendingFrameCount: Int?
  package let pendingPageCount: Int?

  package init(
    target: AK47WiredDeviceTarget?,
    state: AK47LCDExtendedUploadQualificationState,
    pendingContainerSHA256: String? = nil,
    pendingFrameCount: Int? = nil,
    pendingPageCount: Int? = nil
  ) {
    self.target = target
    self.state = state
    self.pendingContainerSHA256 = pendingContainerSHA256
    self.pendingFrameCount = pendingFrameCount
    self.pendingPageCount = pendingPageCount
  }
}

package struct AK47LCDQualifiedUploadVisualAttestation: Equatable, Sendable {
  package let containerSHA256: String
  package let attestedAt: Date

  package init(
    explicitlyConfirmingContainerSHA256 containerSHA256: String,
    at attestedAt: Date = Date()
  ) {
    self.containerSHA256 = containerSHA256
    self.attestedAt = attestedAt
  }
}

package struct AK47LCDCanonicalFixtureVisualAttestation: Equatable, Sendable {
  package let attestedAt: Date

  /// Construct only after the user sees the canonical mapping on the keyboard:
  /// black background, TL red, TR green, BL blue, and BR white.
  package init(
    explicitlyConfirmingCanonicalCornersAt attestedAt: Date = Date()
  ) {
    self.attestedAt = attestedAt
  }
}

package struct AK47LCDUSBModeCablePowerCycleAttestation: Equatable, Sendable {
  package let attestedAt: Date

  /// Construct only after the selector stayed in USB mode, the USB cable was
  /// removed until the keyboard and display were visibly unpowered, a real HID
  /// enumeration observed absence, and the exact four collections later
  /// reappeared at the original registry location.
  package init(
    explicitlyConfirmingUSBModeCableRemovalAt attestedAt: Date = Date()
  ) {
    self.attestedAt = attestedAt
  }
}

public struct AK47LCDQualifiedUploadPlanSummary: Equatable, Sendable {
  public let target: AK47WiredDeviceTarget
  public let frameCount: Int
  public let pageCount: Int
  public let expectedInputAcknowledgementCount: Int
  public let containerByteCount: Int
  public let transferStartAddress: UInt64
  public let transferEndAddressExclusive: UInt64
  public let containerSHA256: String
  public let firmwareMinimumAppliedFrameIndices: [Int]

  package init(plan: AK47LCDUploadPlan) {
    target = plan.target
    frameCount = plan.container.frameCount
    pageCount = plan.container.pageCount
    expectedInputAcknowledgementCount = plan.container.pageCount
    containerByteCount = plan.container.data.count
    transferStartAddress = AK47LCDUploadPreflight.externalFlashStartAddress
    transferEndAddressExclusive = transferStartAddress + UInt64(containerByteCount)
    containerSHA256 = AK47LCDUploadDigest.sha256Hex(plan.container.data)
    firmwareMinimumAppliedFrameIndices = plan.container.firmwareMinimumAppliedFrameIndices
  }
}

public enum AK47LCDExtendedUploadQualificationError: Error, Equatable, LocalizedError, Sendable {
  case unavailable
  case wrongTarget
  case transitionNotAllowed
  case persistenceUnavailable
  case qualificationLeaseMismatch
  case qualificationRevoked

  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "The 1...40-frame LCD path has no completed durable qualification receipt."
    case .wrongTarget:
      "The durable LCD qualification belongs to a different USB target or location."
    case .transitionNotAllowed:
      "The LCD qualification steps were attempted out of order."
    case .persistenceUnavailable:
      "KeyCanvas could not durably update the LCD qualification receipt."
    case .qualificationLeaseMismatch:
      "The durable LCD transfer lease does not match this exact target and container."
    case .qualificationRevoked:
      "The LCD qualification was revoked after an uncertain or submitted transfer failure."
    }
  }
}

enum AK47LCDUploadDigest {
  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct AK47LCDQualifiedUploadLease: Equatable, Sendable {
  let identifier: UUID
  let target: HIDDeviceQuarantineIdentity
  let planFingerprintSHA256: String
}

struct AK47LCDCanonicalTransferLease: Equatable, Sendable {
  let identifier: UUID
  let target: HIDDeviceQuarantineIdentity
  let planFingerprintSHA256: String
}

enum AK47LCDQualificationGateAdmissionKind: Hashable, Sendable {
  case canonical
  case extended
}

/// Process-local, one-use capability carried only from a durable qualification
/// lease claim to the LCD adapter's shared-gate acquisition. Persisted receipt
/// data alone can never reconstruct this capability after a relaunch.
struct AK47LCDQualificationGateAdmission: Hashable, Sendable {
  let kind: AK47LCDQualificationGateAdmissionKind
  let leaseIdentifier: UUID
  let target: HIDDeviceQuarantineIdentity
  let planFingerprintSHA256: String
}

extension AK47LCDCanonicalTransferLease {
  var gateAdmission: AK47LCDQualificationGateAdmission {
    AK47LCDQualificationGateAdmission(
      kind: .canonical,
      leaseIdentifier: identifier,
      target: target,
      planFingerprintSHA256: planFingerprintSHA256
    )
  }
}

extension AK47LCDQualifiedUploadLease {
  var gateAdmission: AK47LCDQualificationGateAdmission {
    AK47LCDQualificationGateAdmission(
      kind: .extended,
      leaseIdentifier: identifier,
      target: target,
      planFingerprintSHA256: planFingerprintSHA256
    )
  }
}

enum AK47LCDQualifiedUploadLeaseOutcome: Equatable, Sendable {
  case succeeded
  case failedBeforeSubmissionWithConfirmedCleanup
  case submittedOrUncertainFailure
}

protocol AK47LCDExtendedUploadQualificationServicing: AnyObject {
  func claimCanonicalTransfer(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDCanonicalTransferLease
  func finishCanonicalTransfer(
    _ lease: AK47LCDCanonicalTransferLease,
    plan: AK47LCDUploadPlan,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws
  func claimQualifiedLease(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDQualifiedUploadLease
  func finishQualifiedLease(
    _ lease: AK47LCDQualifiedUploadLease,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws
}

enum AK47LCDQualificationPhase: String, Codable {
  case canonicalTransferInProgress
  case canonicalVisualMismatchQuarantinePending
  case awaitingCanonicalFixtureVisualAttestation
  case awaitingObservedUSBDisconnection
  case awaitingExactSamePortReappearance
  case awaitingUSBPowerCycleAttestation
  case qualified
  case extendedTransferInProgress
  case awaitingExtendedVisualAttestation
  case extendedVisualMismatchQuarantinePending
  case interruptedTransferQuarantinePending
  case invalidatedRequiresFreshDiagnostic
}

enum AK47LCDQualificationProvenance: String, Codable {
  case contemporaneousCanonicalTransfer
}

struct AK47LCDQualificationRecord: Codable, Equatable {
  static let schemaVersion = 1

  let schemaVersion: Int
  let policyRevision: String
  let target: HIDDeviceQuarantineIdentity
  let provenance: AK47LCDQualificationProvenance
  let canonicalTopologySignatureSHA256: String
  let canonicalFixtureSHA256: String
  var canonicalAcknowledgedPageCount: Int?
  let canonicalTransferStartedAt: Date
  var canonicalTransferCompletedAt: Date?
  var canonicalAttemptLeaseIdentifier: UUID?
  var canonicalAttemptPlanFingerprintSHA256: String?
  var canonicalVisualAttestedAt: Date?
  var usbDisconnectionAbsenceObservedAt: Date?
  var exactSamePortReappearanceObservedAt: Date?
  var usbModeCablePowerCycleAttestedAt: Date?
  var phase: AK47LCDQualificationPhase
  var activeLeaseIdentifier: UUID?
  var activePlanFingerprintSHA256: String?
  var activeContainerSHA256: String?
  var activeFrameCount: Int?
  var activePageCount: Int?
  var activeContainerByteCount: Int?
  var activePartitionBudgetByteCount: Int?
  var activeTransferEndAddressExclusive: UInt64?
  var pendingVisualPlanFingerprintSHA256: String?
  var pendingVisualContainerSHA256: String?
  var pendingVisualFrameCount: Int?
  var pendingVisualPageCount: Int?
  var pendingVisualContainerByteCount: Int?
  var pendingVisualPartitionBudgetByteCount: Int?
  var pendingVisualTransferEndAddressExclusive: UInt64?
  var pendingVisualHostCompletedAt: Date?
  var lastSuccessfulContainerSHA256: String?
  var lastSuccessfulTransferAt: Date?
}

enum AK47LCDQualificationPersistenceError: Error, Equatable {
  case busy
  case unavailable
  case invalidReceipt
}

protocol AK47LCDQualificationPersisting: AnyObject {
  func load() throws -> AK47LCDQualificationRecord?
  func save(_ record: AK47LCDQualificationRecord) throws
  func acquireProcessLock() throws -> any HIDDeviceQuarantineProcessLocking
}

final class AK47LCDQualificationMemoryPersistence: AK47LCDQualificationPersisting {
  private let lock = NSLock()
  private var record: AK47LCDQualificationRecord?
  private var processLockHeld = false
  var failsLoads = false
  var failsSaves = false

  init(record: AK47LCDQualificationRecord? = nil) {
    self.record = record
  }

  func load() throws -> AK47LCDQualificationRecord? {
    lock.lock()
    defer { lock.unlock() }
    guard !failsLoads else { throw AK47LCDQualificationPersistenceError.unavailable }
    return record
  }

  func save(_ record: AK47LCDQualificationRecord) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !failsSaves else { throw AK47LCDQualificationPersistenceError.unavailable }
    self.record = record
  }

  func acquireProcessLock() throws -> any HIDDeviceQuarantineProcessLocking {
    lock.lock()
    guard !processLockHeld else {
      lock.unlock()
      throw AK47LCDQualificationPersistenceError.busy
    }
    processLockHeld = true
    lock.unlock()
    return AK47LCDQualificationClosureProcessLock { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.processLockHeld = false
      self.lock.unlock()
    }
  }
}

private final class AK47LCDQualificationClosureProcessLock:
  HIDDeviceQuarantineProcessLocking
{
  private let lock = NSLock()
  private var releaseClosure: (() -> Void)?

  init(release: @escaping () -> Void) {
    releaseClosure = release
  }

  func release() {
    lock.lock()
    let closure = releaseClosure
    releaseClosure = nil
    lock.unlock()
    closure?()
  }

  deinit { release() }
}

final class AK47LCDQualificationFilePersistence: AK47LCDQualificationPersisting {
  static let maximumReceiptBytes = 64 * 1_024

  let receiptURL: URL
  private let lockURL: URL
  private let lock = NSLock()
  private var preparedDirectoryPaths: Set<String> = []

  init(receiptURL: URL) {
    self.receiptURL = receiptURL
    lockURL = receiptURL.deletingPathExtension().appendingPathExtension("lock")
  }

  static func production() -> AK47LCDQualificationFilePersistence {
    let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return AK47LCDQualificationFilePersistence(
      receiptURL:
        applicationSupport
        .appendingPathComponent("KeyCanvas", isDirectory: true)
        .appendingPathComponent("ak47-lcd-qualified-upload-v1.json", isDirectory: false)
    )
  }

  func load() throws -> AK47LCDQualificationRecord? {
    lock.lock()
    defer { lock.unlock() }
    do {
      return try readLocked()
    } catch let error as AK47LCDQualificationPersistenceError {
      throw error
    } catch {
      throw AK47LCDQualificationPersistenceError.unavailable
    }
  }

  func save(_ record: AK47LCDQualificationRecord) throws {
    lock.lock()
    defer { lock.unlock() }
    let directory = receiptURL.deletingLastPathComponent()
    do {
      try prepareStorageDirectory(directory)
      let validatedRecord = try validated(record)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(validatedRecord)
      guard data.count <= Self.maximumReceiptBytes else {
        throw AK47LCDQualificationPersistenceError.invalidReceipt
      }
      try rejectNonRegularExistingItem(receiptURL)
      try data.write(to: receiptURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: receiptURL.path
      )
      try synchronizeFile(receiptURL)
      try synchronizeDirectory(directory)
    } catch let error as AK47LCDQualificationPersistenceError {
      throw error
    } catch {
      throw AK47LCDQualificationPersistenceError.unavailable
    }
  }

  func acquireProcessLock() throws -> any HIDDeviceQuarantineProcessLocking {
    lock.lock()
    defer { lock.unlock() }
    let directory = lockURL.deletingLastPathComponent()
    do {
      try prepareStorageDirectory(directory)
    } catch {
      throw AK47LCDQualificationPersistenceError.unavailable
    }
    let descriptor = open(
      lockURL.path,
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else { throw AK47LCDQualificationPersistenceError.unavailable }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let lockError = errno
      close(descriptor)
      if lockError == EWOULDBLOCK || lockError == EAGAIN {
        throw AK47LCDQualificationPersistenceError.busy
      }
      throw AK47LCDQualificationPersistenceError.unavailable
    }
    return AK47LCDQualificationClosureProcessLock {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
    }
  }

  private func readLocked() throws -> AK47LCDQualificationRecord? {
    let descriptor = open(receiptURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      throw AK47LCDQualificationPersistenceError.unavailable
    }
    defer { close(descriptor) }

    var status = stat()
    guard fstat(descriptor, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_size >= 0,
      status.st_size <= Self.maximumReceiptBytes
    else {
      throw AK47LCDQualificationPersistenceError.invalidReceipt
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    guard let data = try handle.read(upToCount: Self.maximumReceiptBytes + 1),
      data.count <= Self.maximumReceiptBytes
    else {
      throw AK47LCDQualificationPersistenceError.invalidReceipt
    }
    do {
      return try validated(JSONDecoder().decode(AK47LCDQualificationRecord.self, from: data))
    } catch let error as AK47LCDQualificationPersistenceError {
      throw error
    } catch {
      throw AK47LCDQualificationPersistenceError.invalidReceipt
    }
  }

  private func validated(
    _ record: AK47LCDQualificationRecord
  ) throws -> AK47LCDQualificationRecord {
    guard AK47LCDExtendedUploadQualificationStateStore.isValid(record) else {
      throw AK47LCDQualificationPersistenceError.invalidReceipt
    }
    return record
  }

  private func rejectNonRegularExistingItem(_ url: URL) throws {
    var status = stat()
    if lstat(url.path, &status) == 0 {
      guard (status.st_mode & S_IFMT) == S_IFREG else {
        throw AK47LCDQualificationPersistenceError.unavailable
      }
    } else if errno != ENOENT {
      throw AK47LCDQualificationPersistenceError.unavailable
    }
  }

  private func prepareStorageDirectory(_ directory: URL) throws {
    let path = directory.standardizedFileURL.path
    guard !preparedDirectoryPaths.contains(path) else { return }
    var status = stat()
    if lstat(path, &status) == 0 {
      guard (status.st_mode & S_IFMT) == S_IFDIR else {
        throw AK47LCDQualificationPersistenceError.unavailable
      }
    } else {
      guard errno == ENOENT else { throw AK47LCDQualificationPersistenceError.unavailable }
      let parent = directory.deletingLastPathComponent()
      guard parent.standardizedFileURL.path != path else {
        throw AK47LCDQualificationPersistenceError.unavailable
      }
      try prepareStorageDirectory(parent)
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        var racedStatus = stat()
        guard lstat(path, &racedStatus) == 0,
          (racedStatus.st_mode & S_IFMT) == S_IFDIR
        else {
          throw AK47LCDQualificationPersistenceError.unavailable
        }
      }
    }
    let parent = directory.deletingLastPathComponent()
    try synchronizeDirectory(directory)
    if parent.standardizedFileURL.path != path {
      try synchronizeDirectory(parent)
    }
    preparedDirectoryPaths.insert(path)
  }

  private func synchronizeFile(_ url: URL) throws {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw AK47LCDQualificationPersistenceError.unavailable }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw AK47LCDQualificationPersistenceError.unavailable
    }
  }

  private func synchronizeDirectory(_ url: URL) throws {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw AK47LCDQualificationPersistenceError.unavailable }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw AK47LCDQualificationPersistenceError.unavailable
    }
  }
}

final class AK47LCDExtendedUploadQualificationStateStore:
  AK47LCDExtendedUploadQualificationServicing, @unchecked Sendable
{
  static let maximumQualifiedFrameCount = 40
  static let policyRevision = "ak47-lcd-qualified-upload-v1"
  private static let exactTopology: Set<AK47LCDQualificationCollectionSignature> = [
    .init(usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
    .init(usagePage: 0x000C, usage: 0x0001, input: 16, output: 1, feature: 1),
    .init(usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64, feature: 64),
    .init(usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096, feature: 0),
  ]
  static let canonicalTopologySignatureSHA256 = AK47LCDUploadDigest.sha256Hex(
    Data(
      "0001:0006:8:1:0|000c:0001:16:1:1|ff13:0001:64:64:64|ff68:0061:64:4096:0"
        .utf8
    )
  )

  private let lock = NSLock()
  private let persistence: any AK47LCDQualificationPersisting
  private let now: @Sendable () -> Date
  private let quarantineTarget: @Sendable (HIDDeviceQuarantineIdentity) throws -> Void
  private var persistenceUnavailable = false
  private var localGateAdmissions: Set<AK47LCDQualificationGateAdmission> = []

  init(
    persistence: any AK47LCDQualificationPersisting,
    now: @escaping @Sendable () -> Date = { Date() },
    quarantineTarget: @escaping @Sendable (HIDDeviceQuarantineIdentity) throws -> Void = {
      try HIDDeviceOperationGate.quarantine(target: $0)
    }
  ) {
    self.persistence = persistence
    self.now = now
    self.quarantineTarget = quarantineTarget
    do {
      if let record = try persistence.load(), !Self.isValid(record) {
        persistenceUnavailable = true
      }
    } catch {
      persistenceUnavailable = true
    }
  }

  var snapshot: AK47LCDExtendedUploadQualificationSnapshot {
    withLoadedRecord { record in
      guard let record else {
        return AK47LCDExtendedUploadQualificationSnapshot(target: nil, state: .unavailable)
      }
      return AK47LCDExtendedUploadQualificationSnapshot(
        target: Self.target(from: record.target),
        state: Self.publicState(record.phase),
        pendingContainerSHA256: record.pendingVisualContainerSHA256,
        pendingFrameCount: record.pendingVisualFrameCount,
        pendingPageCount: record.pendingVisualPageCount
      )
    }
      ?? AK47LCDExtendedUploadQualificationSnapshot(
        target: nil,
        state: .persistenceUnavailable
      )
  }

  func state(for target: AK47WiredDeviceTarget) -> AK47LCDExtendedUploadQualificationState {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    return withLoadedRecord { record in
      guard let record else { return .unavailable }
      guard record.target == identity else { return .unavailable }
      return Self.publicState(record.phase)
    } ?? .persistenceUnavailable
  }

  func claimCanonicalTransfer(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDCanonicalTransferLease {
    try Self.validateCanonicalPlan(plan)
    guard Self.isLowercaseSHA256(planFingerprintSHA256),
      planFingerprintSHA256 == AK47LCDUploadPlanFingerprint.hex(plan)
    else {
      throw AK47LCDExtendedUploadQualificationError.qualificationLeaseMismatch
    }
    let identity = HIDDeviceQuarantineIdentity(target: plan.target)
    let lease = AK47LCDCanonicalTransferLease(
      identifier: UUID(),
      target: identity,
      planFingerprintSHA256: planFingerprintSHA256
    )
    try mutateRecord { record in
      if let record {
        guard record.phase == .invalidatedRequiresFreshDiagnostic else {
          throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
        }
        guard record.target == identity else {
          throw AK47LCDExtendedUploadQualificationError.wrongTarget
        }
      }
      return AK47LCDQualificationRecord(
        schemaVersion: AK47LCDQualificationRecord.schemaVersion,
        policyRevision: Self.policyRevision,
        target: identity,
        provenance: .contemporaneousCanonicalTransfer,
        canonicalTopologySignatureSHA256: Self.canonicalTopologySignatureSHA256,
        canonicalFixtureSHA256: AK47LCDDiagnosticFixture.expectedContainerSHA256,
        canonicalAcknowledgedPageCount: nil,
        canonicalTransferStartedAt: now(),
        canonicalTransferCompletedAt: nil,
        canonicalAttemptLeaseIdentifier: lease.identifier,
        canonicalAttemptPlanFingerprintSHA256: planFingerprintSHA256,
        canonicalVisualAttestedAt: nil,
        usbDisconnectionAbsenceObservedAt: nil,
        exactSamePortReappearanceObservedAt: nil,
        usbModeCablePowerCycleAttestedAt: nil,
        phase: .canonicalTransferInProgress,
        activeLeaseIdentifier: nil,
        activePlanFingerprintSHA256: nil,
        activeContainerSHA256: nil,
        activeFrameCount: nil,
        activePageCount: nil,
        activeContainerByteCount: nil,
        activePartitionBudgetByteCount: nil,
        activeTransferEndAddressExclusive: nil,
        pendingVisualPlanFingerprintSHA256: nil,
        pendingVisualContainerSHA256: nil,
        pendingVisualFrameCount: nil,
        pendingVisualPageCount: nil,
        pendingVisualContainerByteCount: nil,
        pendingVisualPartitionBudgetByteCount: nil,
        pendingVisualTransferEndAddressExclusive: nil,
        pendingVisualHostCompletedAt: nil,
        lastSuccessfulContainerSHA256: nil,
        lastSuccessfulTransferAt: nil
      )
    }
    registerLocalGateAdmission(lease.gateAdmission)
    return lease
  }

  func finishCanonicalTransfer(
    _ lease: AK47LCDCanonicalTransferLease,
    plan: AK47LCDUploadPlan,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws {
    defer { revokeLocalGateAdmission(lease.gateAdmission) }
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.phase == .canonicalTransferInProgress,
        record.target == lease.target,
        record.canonicalAttemptLeaseIdentifier == lease.identifier,
        record.canonicalAttemptPlanFingerprintSHA256 == lease.planFingerprintSHA256,
        AK47LCDUploadPlanFingerprint.hex(plan) == lease.planFingerprintSHA256
      else {
        throw AK47LCDExtendedUploadQualificationError.qualificationLeaseMismatch
      }
      record.canonicalAttemptLeaseIdentifier = nil
      record.canonicalAttemptPlanFingerprintSHA256 = nil
      switch outcome {
      case .succeeded:
        try Self.validateCanonicalPlan(plan)
        record.canonicalTransferCompletedAt = now()
        record.canonicalAcknowledgedPageCount = AK47LCDDiagnosticFixture.expectedPageCount
        record.phase = .awaitingCanonicalFixtureVisualAttestation
      case .failedBeforeSubmissionWithConfirmedCleanup, .submittedOrUncertainFailure:
        record.phase = .invalidatedRequiresFreshDiagnostic
      }
      return record
    }
  }

  func recordCanonicalFixtureVisualAttestation(
    for target: AK47WiredDeviceTarget,
    attestation: AK47LCDCanonicalFixtureVisualAttestation
  ) throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard record.phase == .awaitingCanonicalFixtureVisualAttestation,
        let completedAt = record.canonicalTransferCompletedAt,
        attestation.attestedAt >= completedAt
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.canonicalVisualAttestedAt = attestation.attestedAt
      record.phase = .awaitingObservedUSBDisconnection
      return record
    }
  }

  func reportCanonicalFixtureVisualMismatch(
    for target: AK47WiredDeviceTarget
  ) throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard
        record.phase == .awaitingCanonicalFixtureVisualAttestation
          || record.phase == .canonicalVisualMismatchQuarantinePending
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.phase = .canonicalVisualMismatchQuarantinePending
      return record
    }

    do {
      try quarantineTarget(identity)
    } catch {
      throw AK47LCDExtendedUploadQualificationError.persistenceUnavailable
    }

    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity,
        record.phase == .canonicalVisualMismatchQuarantinePending
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.phase = .invalidatedRequiresFreshDiagnostic
      return record
    }
  }

  func observeSuccessfulHardwareEnumeration(_ records: [HIDCollectionRecord]) {
    do {
      try mutateRecord { record in
        guard var record else { return nil }
        switch record.phase {
        case .awaitingObservedUSBDisconnection:
          let compatibleRecords = records.filter {
            record.target.possiblyRepresentsSameDevice(as: $0)
          }
          guard compatibleRecords.isEmpty else { return record }
          record.usbDisconnectionAbsenceObservedAt = now()
          record.phase = .awaitingExactSamePortReappearance
          return record
        case .awaitingExactSamePortReappearance:
          guard Self.hasExactTopology(records, target: record.target) else { return record }
          record.exactSamePortReappearanceObservedAt = now()
          record.phase = .awaitingUSBPowerCycleAttestation
          return record
        default:
          return record
        }
      }
    } catch {
      lock.lock()
      persistenceUnavailable = true
      lock.unlock()
    }
  }

  func acknowledgeUSBModeCablePowerCycle(
    for target: AK47WiredDeviceTarget,
    attestation: AK47LCDUSBModeCablePowerCycleAttestation
  ) throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard record.phase == .awaitingUSBPowerCycleAttestation,
        let reappearance = record.exactSamePortReappearanceObservedAt,
        attestation.attestedAt >= reappearance
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.usbModeCablePowerCycleAttestedAt = attestation.attestedAt
      record.phase = .qualified
      return record
    }
  }

  func claimQualifiedLease(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDQualifiedUploadLease {
    try AK47LCDUploadPreflight.validateStructuralModel(plan)
    try AK47LCDUploadAdapter.validateQualifiedAnimation(plan)
    guard planFingerprintSHA256 == AK47LCDUploadPlanFingerprint.hex(plan) else {
      throw AK47LCDExtendedUploadQualificationError.qualificationLeaseMismatch
    }
    let identity = HIDDeviceQuarantineIdentity(target: plan.target)
    let lease = AK47LCDQualifiedUploadLease(
      identifier: UUID(),
      target: identity,
      planFingerprintSHA256: planFingerprintSHA256
    )
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard record.phase == .qualified else {
        if record.phase == .invalidatedRequiresFreshDiagnostic {
          throw AK47LCDExtendedUploadQualificationError.qualificationRevoked
        }
        throw AK47LCDExtendedUploadQualificationError.unavailable
      }
      record.phase = .extendedTransferInProgress
      record.activeLeaseIdentifier = lease.identifier
      record.activePlanFingerprintSHA256 = planFingerprintSHA256
      record.activeContainerSHA256 = AK47LCDUploadDigest.sha256Hex(plan.container.data)
      record.activeFrameCount = plan.container.frameCount
      record.activePageCount = plan.container.pageCount
      record.activeContainerByteCount = plan.container.data.count
      record.activePartitionBudgetByteCount = plan.container.partitionBudgetByteCount
      record.activeTransferEndAddressExclusive =
        AK47LCDUploadPreflight.externalFlashStartAddress + UInt64(plan.container.data.count)
      return record
    }
    registerLocalGateAdmission(lease.gateAdmission)
    return lease
  }

  func finishQualifiedLease(
    _ lease: AK47LCDQualifiedUploadLease,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws {
    defer { revokeLocalGateAdmission(lease.gateAdmission) }
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == lease.target,
        record.phase == .extendedTransferInProgress,
        record.activeLeaseIdentifier == lease.identifier,
        record.activePlanFingerprintSHA256 == lease.planFingerprintSHA256
      else {
        throw AK47LCDExtendedUploadQualificationError.qualificationLeaseMismatch
      }
      switch outcome {
      case .succeeded:
        record.phase = .awaitingExtendedVisualAttestation
        record.pendingVisualPlanFingerprintSHA256 = record.activePlanFingerprintSHA256
        record.pendingVisualContainerSHA256 = record.activeContainerSHA256
        record.pendingVisualFrameCount = record.activeFrameCount
        record.pendingVisualPageCount = record.activePageCount
        record.pendingVisualContainerByteCount = record.activeContainerByteCount
        record.pendingVisualPartitionBudgetByteCount =
          record.activePartitionBudgetByteCount
        record.pendingVisualTransferEndAddressExclusive =
          record.activeTransferEndAddressExclusive
        record.pendingVisualHostCompletedAt = now()
      case .failedBeforeSubmissionWithConfirmedCleanup:
        record.phase = .qualified
      case .submittedOrUncertainFailure:
        record.phase = .invalidatedRequiresFreshDiagnostic
      }
      record.activeLeaseIdentifier = nil
      record.activePlanFingerprintSHA256 = nil
      record.activeContainerSHA256 = nil
      record.activeFrameCount = nil
      record.activePageCount = nil
      record.activeContainerByteCount = nil
      record.activePartitionBudgetByteCount = nil
      record.activeTransferEndAddressExclusive = nil
      return record
    }
  }

  func recordQualifiedUploadVisualAttestation(
    for target: AK47WiredDeviceTarget,
    attestation: AK47LCDQualifiedUploadVisualAttestation
  ) throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard record.phase == .awaitingExtendedVisualAttestation,
        record.pendingVisualContainerSHA256 == attestation.containerSHA256,
        let hostCompletedAt = record.pendingVisualHostCompletedAt,
        attestation.attestedAt >= hostCompletedAt
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.lastSuccessfulContainerSHA256 = attestation.containerSHA256
      record.lastSuccessfulTransferAt = attestation.attestedAt
      Self.clearPendingVisualMetadata(&record)
      record.phase = .qualified
      return record
    }
  }

  func reportQualifiedUploadVisualMismatch(
    for target: AK47WiredDeviceTarget,
    containerSHA256: String
  ) throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard
        record.phase == .awaitingExtendedVisualAttestation
          || record.phase == .extendedVisualMismatchQuarantinePending,
        record.pendingVisualContainerSHA256 == containerSHA256
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.phase = .extendedVisualMismatchQuarantinePending
      return record
    }

    do {
      try quarantineTarget(identity)
    } catch {
      throw AK47LCDExtendedUploadQualificationError.persistenceUnavailable
    }

    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity,
        record.phase == .extendedVisualMismatchQuarantinePending,
        record.pendingVisualContainerSHA256 == containerSHA256
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      Self.clearPendingVisualMetadata(&record)
      record.phase = .invalidatedRequiresFreshDiagnostic
      return record
    }
  }

  /// Reconciles a lease that survived process exit or was invalidated by a
  /// competing process. The receipt enters a terminal pending phase before the
  /// shared operation marker is armed, so the old lease can never finish back
  /// into positive authority. Every step is idempotent across relaunch.
  func reconcileInterruptedTransfer(for target: AK47WiredDeviceTarget) throws {
    let identity = HIDDeviceQuarantineIdentity(target: target)
    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity else {
        throw AK47LCDExtendedUploadQualificationError.wrongTarget
      }
      guard
        record.phase == .canonicalTransferInProgress
          || record.phase == .extendedTransferInProgress
          || record.phase == .interruptedTransferQuarantinePending
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      record.phase = .interruptedTransferQuarantinePending
      return record
    }
    revokeLocalGateAdmissions(for: identity)

    do {
      try quarantineTarget(identity)
    } catch {
      throw AK47LCDExtendedUploadQualificationError.persistenceUnavailable
    }

    try mutateRecord { record in
      guard var record else { throw AK47LCDExtendedUploadQualificationError.unavailable }
      guard record.target == identity,
        record.phase == .interruptedTransferQuarantinePending
      else {
        throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
      }
      Self.clearCanonicalLeaseMetadata(&record)
      Self.clearActiveLeaseMetadata(&record)
      record.phase = .invalidatedRequiresFreshDiagnostic
      return record
    }
  }

  var requiresDeviceOperationQuarantine: Bool {
    switch snapshot.state {
    case .canonicalTransferInProgress,
      .canonicalVisualMismatchQuarantinePending,
      .extendedTransferInProgress,
      .extendedVisualMismatchQuarantinePending,
      .interruptedTransferQuarantinePending,
      .persistenceUnavailable:
      true
    default:
      false
    }
  }

  /// Consumes one exact process-local gate capability. Generic HID callers and
  /// capabilities reconstructed from receipt data always fail this check.
  func consumeGateAdmission(
    _ admission: AK47LCDQualificationGateAdmission,
    for target: HIDDeviceQuarantineIdentity
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !persistenceUnavailable,
      admission.target == target,
      localGateAdmissions.contains(admission)
    else { return false }

    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
    } catch {
      localGateAdmissions.remove(admission)
      return false
    }
    defer { processLock.release() }

    do {
      guard let record = try persistence.load(), Self.isValid(record), record.target == target
      else {
        persistenceUnavailable = true
        localGateAdmissions.remove(admission)
        return false
      }
      let matches: Bool
      switch admission.kind {
      case .canonical:
        matches =
          record.phase == .canonicalTransferInProgress
          && record.canonicalAttemptLeaseIdentifier == admission.leaseIdentifier
          && record.canonicalAttemptPlanFingerprintSHA256
            == admission.planFingerprintSHA256
      case .extended:
        matches =
          record.phase == .extendedTransferInProgress
          && record.activeLeaseIdentifier == admission.leaseIdentifier
          && record.activePlanFingerprintSHA256 == admission.planFingerprintSHA256
      }
      guard matches else {
        localGateAdmissions.remove(admission)
        return false
      }
      localGateAdmissions.remove(admission)
      return true
    } catch {
      persistenceUnavailable = true
      localGateAdmissions.remove(admission)
      return false
    }
  }

  private func registerLocalGateAdmission(_ admission: AK47LCDQualificationGateAdmission) {
    lock.lock()
    localGateAdmissions.insert(admission)
    lock.unlock()
  }

  private func revokeLocalGateAdmission(_ admission: AK47LCDQualificationGateAdmission) {
    lock.lock()
    localGateAdmissions.remove(admission)
    lock.unlock()
  }

  private func revokeLocalGateAdmissions(for target: HIDDeviceQuarantineIdentity) {
    lock.lock()
    localGateAdmissions = localGateAdmissions.filter { $0.target != target }
    lock.unlock()
  }

  private func withLoadedRecord<T>(
    _ body: (AK47LCDQualificationRecord?) -> T
  ) -> T? {
    lock.lock()
    defer { lock.unlock() }
    guard !persistenceUnavailable else { return nil }
    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
    } catch {
      persistenceUnavailable = true
      return nil
    }
    defer { processLock.release() }
    do {
      let record = try persistence.load()
      guard record.map(Self.isValid) ?? true else {
        persistenceUnavailable = true
        return nil
      }
      return body(record)
    } catch {
      persistenceUnavailable = true
      return nil
    }
  }

  private func mutateRecord(
    _ mutation: (AK47LCDQualificationRecord?) throws -> AK47LCDQualificationRecord?
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !persistenceUnavailable else {
      throw AK47LCDExtendedUploadQualificationError.persistenceUnavailable
    }
    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
    } catch {
      persistenceUnavailable = true
      throw AK47LCDExtendedUploadQualificationError.persistenceUnavailable
    }
    defer { processLock.release() }
    do {
      let current = try persistence.load()
      guard current.map(Self.isValid) ?? true else {
        throw AK47LCDQualificationPersistenceError.invalidReceipt
      }
      guard let updated = try mutation(current) else { return }
      guard Self.isValid(updated) else {
        throw AK47LCDQualificationPersistenceError.invalidReceipt
      }
      try persistence.save(updated)
    } catch let error as AK47LCDExtendedUploadQualificationError {
      throw error
    } catch {
      persistenceUnavailable = true
      throw AK47LCDExtendedUploadQualificationError.persistenceUnavailable
    }
  }

  static func isValid(_ record: AK47LCDQualificationRecord) -> Bool {
    guard record.schemaVersion == AK47LCDQualificationRecord.schemaVersion,
      record.policyRevision == policyRevision,
      record.target.vendorID == HIDEnumerator.vendorID,
      record.target.productID == HIDEnumerator.productID,
      record.target.product == "Archon AK47",
      record.target.locationID <= UInt64(UInt32.max),
      record.target.versionNumber == 0x0115,
      record.target.serialNumber.map({ !$0.isEmpty && $0.utf8.count <= 256 }) ?? true,
      record.provenance == .contemporaneousCanonicalTransfer,
      record.canonicalTopologySignatureSHA256 == canonicalTopologySignatureSHA256,
      record.canonicalFixtureSHA256 == AK47LCDDiagnosticFixture.expectedContainerSHA256,
      record.canonicalTransferStartedAt.timeIntervalSinceReferenceDate.isFinite
    else { return false }

    let timestamps = [
      Optional(record.canonicalTransferStartedAt),
      record.canonicalTransferCompletedAt,
      record.canonicalVisualAttestedAt,
      record.usbDisconnectionAbsenceObservedAt,
      record.exactSamePortReappearanceObservedAt,
      record.usbModeCablePowerCycleAttestedAt,
    ].compactMap { $0 }
    guard timestamps.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
      zip(timestamps, timestamps.dropFirst()).allSatisfy({ $0 <= $1 })
    else { return false }

    let hasVisual = record.canonicalVisualAttestedAt != nil
    let hasAbsence = record.usbDisconnectionAbsenceObservedAt != nil
    let hasReappearance = record.exactSamePortReappearanceObservedAt != nil
    let hasPowerAttestation = record.usbModeCablePowerCycleAttestedAt != nil
    let hasCanonicalCompletion =
      record.canonicalTransferCompletedAt != nil
      && record.canonicalAcknowledgedPageCount
        == AK47LCDDiagnosticFixture.expectedPageCount
    let hasCanonicalLease =
      record.canonicalAttemptLeaseIdentifier != nil
      && (record.canonicalAttemptPlanFingerprintSHA256.map(Self.isLowercaseSHA256) ?? false)
    let hasAnyCanonicalLeaseMetadata =
      record.canonicalAttemptLeaseIdentifier != nil
      || record.canonicalAttemptPlanFingerprintSHA256 != nil
    let hasLease: Bool = {
      guard record.activeLeaseIdentifier != nil,
        let planFingerprint = record.activePlanFingerprintSHA256,
        Self.isLowercaseSHA256(planFingerprint),
        let containerDigest = record.activeContainerSHA256,
        Self.isLowercaseSHA256(containerDigest),
        let frameCount = record.activeFrameCount,
        (1...maximumQualifiedFrameCount).contains(frameCount),
        let expectedPageCount = Self.minimalPageCount(frameCount),
        expectedPageCount <= 633,
        record.activePageCount == expectedPageCount,
        let expectedByteCount = Self.checkedPaddedByteCount(pageCount: expectedPageCount),
        expectedByteCount <= 2_592_768,
        record.activeContainerByteCount == expectedByteCount,
        let budget = record.activePartitionBudgetByteCount,
        budget >= expectedByteCount,
        budget <= 2_592_768,
        budget.isMultiple(of: AK47LCDFormat.transferPageByteCount),
        let expectedEnd = Self.checkedTransferEnd(byteCount: expectedByteCount),
        expectedEnd <= 0x9B_9000,
        record.activeTransferEndAddressExclusive == expectedEnd
      else { return false }
      return true
    }()
    let hasAnyLeaseMetadata =
      record.activeLeaseIdentifier != nil
      || record.activePlanFingerprintSHA256 != nil
      || record.activeContainerSHA256 != nil
      || record.activeFrameCount != nil
      || record.activePageCount != nil
      || record.activeContainerByteCount != nil
      || record.activePartitionBudgetByteCount != nil
      || record.activeTransferEndAddressExclusive != nil
    let hasPendingVisual: Bool = {
      guard
        let planFingerprint = record.pendingVisualPlanFingerprintSHA256,
        Self.isLowercaseSHA256(planFingerprint),
        let containerDigest = record.pendingVisualContainerSHA256,
        Self.isLowercaseSHA256(containerDigest),
        let frameCount = record.pendingVisualFrameCount,
        let expectedPageCount = Self.minimalPageCount(frameCount),
        record.pendingVisualPageCount == expectedPageCount,
        let expectedByteCount = Self.checkedPaddedByteCount(pageCount: expectedPageCount),
        record.pendingVisualContainerByteCount == expectedByteCount,
        let pendingBudget = record.pendingVisualPartitionBudgetByteCount,
        pendingBudget >= expectedByteCount,
        pendingBudget <= 2_592_768,
        pendingBudget.isMultiple(of: AK47LCDFormat.transferPageByteCount),
        let expectedEnd = Self.checkedTransferEnd(byteCount: expectedByteCount),
        record.pendingVisualTransferEndAddressExclusive == expectedEnd,
        let hostCompletedAt = record.pendingVisualHostCompletedAt,
        hostCompletedAt.timeIntervalSinceReferenceDate.isFinite,
        let powerAttestation = record.usbModeCablePowerCycleAttestedAt,
        hostCompletedAt >= powerAttestation,
        record.lastSuccessfulTransferAt.map({ hostCompletedAt >= $0 }) ?? true
      else { return false }
      return true
    }()
    let hasAnyPendingVisualMetadata =
      record.pendingVisualPlanFingerprintSHA256 != nil
      || record.pendingVisualContainerSHA256 != nil
      || record.pendingVisualFrameCount != nil
      || record.pendingVisualPageCount != nil
      || record.pendingVisualContainerByteCount != nil
      || record.pendingVisualPartitionBudgetByteCount != nil
      || record.pendingVisualTransferEndAddressExclusive != nil
      || record.pendingVisualHostCompletedAt != nil
    let lastSuccessIsValid: Bool = {
      switch (record.lastSuccessfulContainerSHA256, record.lastSuccessfulTransferAt) {
      case (nil, nil):
        return true
      case (.some(let digest), .some(let date)):
        guard Self.isLowercaseSHA256(digest),
          date.timeIntervalSinceReferenceDate.isFinite,
          let powerAttestation = record.usbModeCablePowerCycleAttestedAt
        else { return false }
        return date >= powerAttestation
      default:
        return false
      }
    }()
    guard lastSuccessIsValid else { return false }

    switch record.phase {
    case .canonicalTransferInProgress:
      return !hasCanonicalCompletion && record.canonicalAcknowledgedPageCount == nil
        && hasCanonicalLease && !hasVisual && !hasAbsence && !hasReappearance
        && !hasPowerAttestation && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
        && record.lastSuccessfulContainerSHA256 == nil && record.lastSuccessfulTransferAt == nil
    case .awaitingCanonicalFixtureVisualAttestation:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && !hasVisual
        && !hasAbsence && !hasReappearance && !hasPowerAttestation
        && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
    case .canonicalVisualMismatchQuarantinePending:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && !hasVisual
        && !hasAbsence && !hasReappearance && !hasPowerAttestation
        && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
    case .awaitingObservedUSBDisconnection:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && !hasAbsence && !hasReappearance && !hasPowerAttestation
        && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
    case .awaitingExactSamePortReappearance:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && hasAbsence && !hasReappearance && !hasPowerAttestation
        && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
    case .awaitingUSBPowerCycleAttestation:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && hasAbsence && hasReappearance && !hasPowerAttestation
        && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
    case .qualified:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && hasAbsence && hasReappearance && hasPowerAttestation
        && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
    case .extendedTransferInProgress:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && hasAbsence && hasReappearance && hasPowerAttestation && hasLease
        && !hasAnyPendingVisualMetadata
    case .awaitingExtendedVisualAttestation, .extendedVisualMismatchQuarantinePending:
      return hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && hasAbsence && hasReappearance && hasPowerAttestation
        && !hasAnyLeaseMetadata && hasPendingVisual
    case .interruptedTransferQuarantinePending:
      let interruptedCanonical =
        !hasCanonicalCompletion && record.canonicalAcknowledgedPageCount == nil
        && hasCanonicalLease && !hasVisual && !hasAbsence && !hasReappearance
        && !hasPowerAttestation && !hasAnyLeaseMetadata && !hasAnyPendingVisualMetadata
        && record.lastSuccessfulContainerSHA256 == nil && record.lastSuccessfulTransferAt == nil
      let interruptedExtended =
        hasCanonicalCompletion && !hasAnyCanonicalLeaseMetadata && hasVisual
        && hasAbsence && hasReappearance && hasPowerAttestation && hasLease
        && !hasAnyPendingVisualMetadata
      return interruptedCanonical || interruptedExtended
    case .invalidatedRequiresFreshDiagnostic:
      let failedCanonical =
        !hasCanonicalCompletion
        && record.canonicalAcknowledgedPageCount == nil
        && !hasVisual && !hasAbsence && !hasReappearance && !hasPowerAttestation
      let invalidatedQualified =
        hasCanonicalCompletion && hasVisual && hasAbsence
        && hasReappearance && hasPowerAttestation
      let invalidatedCanonicalVisual =
        hasCanonicalCompletion && !hasVisual && !hasAbsence
        && !hasReappearance && !hasPowerAttestation
      return !hasAnyCanonicalLeaseMetadata && !hasAnyLeaseMetadata
        && !hasAnyPendingVisualMetadata
        && (failedCanonical || invalidatedCanonicalVisual || invalidatedQualified)
    }
  }

  private static func minimalPageCount(_ frameCount: Int) -> Int? {
    guard (1...maximumQualifiedFrameCount).contains(frameCount) else { return nil }
    let (frameBytes, frameOverflow) = frameCount.multipliedReportingOverflow(
      by: AK47LCDFormat.rgb565FrameByteCount
    )
    let (rawByteCount, rawOverflow) = AK47LCDFormat.headerByteCount
      .addingReportingOverflow(frameBytes)
    let (roundingNumerator, roundingOverflow) = rawByteCount.addingReportingOverflow(
      AK47LCDFormat.transferPageByteCount - 1
    )
    guard !frameOverflow, !rawOverflow, !roundingOverflow else { return nil }
    return roundingNumerator / AK47LCDFormat.transferPageByteCount
  }

  private static func validateCanonicalPlan(_ plan: AK47LCDUploadPlan) throws {
    try plan.target.validate()
    guard plan.container.frameCount == 1,
      plan.container.pageCount == AK47LCDDiagnosticFixture.expectedPageCount,
      plan.container.data.count == AK47LCDDiagnosticFixture.expectedContainerByteCount,
      AK47LCDUploadDigest.sha256Hex(plan.container.data)
        == AK47LCDDiagnosticFixture.expectedContainerSHA256
    else {
      throw AK47LCDExtendedUploadQualificationError.transitionNotAllowed
    }
  }

  private static func clearPendingVisualMetadata(
    _ record: inout AK47LCDQualificationRecord
  ) {
    record.pendingVisualContainerSHA256 = nil
    record.pendingVisualPlanFingerprintSHA256 = nil
    record.pendingVisualFrameCount = nil
    record.pendingVisualPageCount = nil
    record.pendingVisualContainerByteCount = nil
    record.pendingVisualPartitionBudgetByteCount = nil
    record.pendingVisualTransferEndAddressExclusive = nil
    record.pendingVisualHostCompletedAt = nil
  }

  private static func clearCanonicalLeaseMetadata(
    _ record: inout AK47LCDQualificationRecord
  ) {
    record.canonicalAttemptLeaseIdentifier = nil
    record.canonicalAttemptPlanFingerprintSHA256 = nil
  }

  private static func clearActiveLeaseMetadata(
    _ record: inout AK47LCDQualificationRecord
  ) {
    record.activeLeaseIdentifier = nil
    record.activePlanFingerprintSHA256 = nil
    record.activeContainerSHA256 = nil
    record.activeFrameCount = nil
    record.activePageCount = nil
    record.activeContainerByteCount = nil
    record.activePartitionBudgetByteCount = nil
    record.activeTransferEndAddressExclusive = nil
  }

  private static func checkedPaddedByteCount(pageCount: Int) -> Int? {
    let (byteCount, overflow) = pageCount.multipliedReportingOverflow(
      by: AK47LCDFormat.transferPageByteCount
    )
    return overflow ? nil : byteCount
  }

  private static func checkedTransferEnd(byteCount: Int) -> UInt64? {
    guard byteCount >= 0 else { return nil }
    let (end, overflow) = AK47LCDUploadPreflight.externalFlashStartAddress
      .addingReportingOverflow(UInt64(byteCount))
    return overflow ? nil : end
  }

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 64 else { return false }
    return bytes.allSatisfy { byte in
      (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
    }
  }

  private static func publicState(
    _ phase: AK47LCDQualificationPhase
  ) -> AK47LCDExtendedUploadQualificationState {
    switch phase {
    case .canonicalTransferInProgress:
      .canonicalTransferInProgress
    case .canonicalVisualMismatchQuarantinePending:
      .canonicalVisualMismatchQuarantinePending
    case .awaitingCanonicalFixtureVisualAttestation:
      .awaitingCanonicalFixtureVisualAttestation
    case .awaitingObservedUSBDisconnection:
      .awaitingObservedUSBDisconnection
    case .awaitingExactSamePortReappearance:
      .awaitingExactSamePortReappearance
    case .awaitingUSBPowerCycleAttestation:
      .awaitingUSBPowerCycleAttestation
    case .qualified:
      .qualified(maximumFrameCount: maximumQualifiedFrameCount)
    case .extendedTransferInProgress:
      .extendedTransferInProgress
    case .awaitingExtendedVisualAttestation:
      .awaitingExtendedVisualAttestation
    case .extendedVisualMismatchQuarantinePending:
      .extendedVisualMismatchQuarantinePending
    case .interruptedTransferQuarantinePending:
      .interruptedTransferQuarantinePending
    case .invalidatedRequiresFreshDiagnostic:
      .invalidatedRequiresFreshDiagnostic
    }
  }

  private static func target(
    from identity: HIDDeviceQuarantineIdentity
  ) -> AK47WiredDeviceTarget {
    AK47WiredDeviceTarget(
      product: identity.product,
      locationID: identity.locationID,
      versionNumber: identity.versionNumber ?? 0,
      serialNumber: identity.serialNumber
    )
  }

  private static func hasExactTopology(
    _ records: [HIDCollectionRecord],
    target: HIDDeviceQuarantineIdentity
  ) -> Bool {
    let exactRecords = records.filter { target.exactlyRepresentsSameDevice(as: $0) }
    guard exactRecords.count == 4 else { return false }
    let signatures = Set(
      exactRecords.compactMap { record -> AK47LCDQualificationCollectionSignature? in
        guard let usagePage = record.usagePage,
          let usage = record.usage,
          let input = record.maxInputReportSize,
          let output = record.maxOutputReportSize,
          let feature = record.maxFeatureReportSize
        else { return nil }
        return AK47LCDQualificationCollectionSignature(
          usagePage: usagePage,
          usage: usage,
          input: input,
          output: output,
          feature: feature
        )
      })
    return signatures == exactTopology
  }
}

private struct AK47LCDQualificationCollectionSignature: Hashable {
  let usagePage: UInt64
  let usage: UInt64
  let input: UInt64
  let output: UInt64
  let feature: UInt64
}

package enum AK47LCDExtendedUploadQualification {
  private static let store = AK47LCDExtendedUploadQualificationStateStore(
    persistence: AK47LCDQualificationFilePersistence.production()
  )

  package static var snapshot: AK47LCDExtendedUploadQualificationSnapshot {
    store.snapshot
  }

  static var requiresDeviceOperationQuarantine: Bool {
    store.requiresDeviceOperationQuarantine
  }

  static func consumeGateAdmission(
    _ admission: AK47LCDQualificationGateAdmission,
    for target: HIDDeviceQuarantineIdentity
  ) -> Bool {
    store.consumeGateAdmission(admission, for: target)
  }

  package static func state(
    for target: AK47WiredDeviceTarget
  ) -> AK47LCDExtendedUploadQualificationState {
    store.state(for: target)
  }

  package static func recordCanonicalFixtureVisualAttestation(
    for target: AK47WiredDeviceTarget,
    attestation: AK47LCDCanonicalFixtureVisualAttestation
  ) throws {
    try store.recordCanonicalFixtureVisualAttestation(for: target, attestation: attestation)
  }

  package static func reportCanonicalFixtureVisualMismatch(
    for target: AK47WiredDeviceTarget
  ) throws {
    try store.reportCanonicalFixtureVisualMismatch(for: target)
  }

  /// Call only with a fresh, successful real IOHID registry enumeration.
  package static func observeSuccessfulHardwareEnumeration(
    _ records: [HIDCollectionRecord]
  ) {
    store.observeSuccessfulHardwareEnumeration(records)
  }

  package static func acknowledgeUSBModeCablePowerCycle(
    for target: AK47WiredDeviceTarget,
    attestation: AK47LCDUSBModeCablePowerCycleAttestation
  ) throws {
    try store.acknowledgeUSBModeCablePowerCycle(for: target, attestation: attestation)
  }

  package static func recordQualifiedUploadVisualAttestation(
    for target: AK47WiredDeviceTarget,
    attestation: AK47LCDQualifiedUploadVisualAttestation
  ) throws {
    try store.recordQualifiedUploadVisualAttestation(
      for: target,
      attestation: attestation
    )
  }

  package static func reportQualifiedUploadVisualMismatch(
    for target: AK47WiredDeviceTarget,
    containerSHA256: String
  ) throws {
    try store.reportQualifiedUploadVisualMismatch(
      for: target,
      containerSHA256: containerSHA256
    )
  }

  package static func reconcileInterruptedTransfer(
    for target: AK47WiredDeviceTarget
  ) throws {
    try store.reconcileInterruptedTransfer(for: target)
  }

  static func claimCanonicalTransfer(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDCanonicalTransferLease {
    try store.claimCanonicalTransfer(
      plan: plan,
      planFingerprintSHA256: planFingerprintSHA256
    )
  }

  static func finishCanonicalTransfer(
    _ lease: AK47LCDCanonicalTransferLease,
    plan: AK47LCDUploadPlan,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws {
    try store.finishCanonicalTransfer(lease, plan: plan, outcome: outcome)
  }

  static func claimQualifiedLease(
    plan: AK47LCDUploadPlan,
    planFingerprintSHA256: String
  ) throws -> AK47LCDQualifiedUploadLease {
    try store.claimQualifiedLease(plan: plan, planFingerprintSHA256: planFingerprintSHA256)
  }

  static func finishQualifiedLease(
    _ lease: AK47LCDQualifiedUploadLease,
    outcome: AK47LCDQualifiedUploadLeaseOutcome
  ) throws {
    try store.finishQualifiedLease(lease, outcome: outcome)
  }
}
