import Darwin
import Foundation

enum HIDDeviceOperationGateAcquireResult: Equatable, Sendable {
  case acquired
  case busy
  case quarantined
}

package enum AK47DeviceQuarantineRecoveryState: Equatable, Sendable {
  case notQuarantined
  case awaitingObservedAbsence
  case awaitingExactReappearance
  case awaitingFullPowerCycleAcknowledgement
}

struct HIDDeviceQuarantineIdentity: Codable, Hashable, Sendable {
  let vendorID: UInt64
  let productID: UInt64
  let product: String
  let locationID: UInt64
  let versionNumber: UInt64?
  let serialNumber: String?

  init(target: AK47WiredDeviceTarget) {
    vendorID = HIDEnumerator.vendorID
    productID = HIDEnumerator.productID
    product = target.product
    locationID = target.locationID
    versionNumber = target.versionNumber
    serialNumber = target.serialNumber
  }

  init(request: AK47PerKeyRGBQueryRequest) {
    vendorID = HIDEnumerator.vendorID
    productID = HIDEnumerator.productID
    product = request.product
    locationID = request.locationID
    versionNumber = request.versionNumber
    serialNumber = request.serialNumber
  }

  init(
    vendorID: UInt64,
    productID: UInt64,
    product: String,
    locationID: UInt64,
    versionNumber: UInt64?,
    serialNumber: String?
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.locationID = locationID
    self.versionNumber = versionNumber
    self.serialNumber = serialNumber
  }

  /// Conservative family match used while a marker is active. Without a
  /// serial, every compatible AK47 is indistinguishable and therefore blocked
  /// regardless of USB location. Location is considered only by the stricter
  /// recovery-reappearance check below.
  func possiblyRepresentsSameDevice(as other: Self) -> Bool {
    guard vendorID == other.vendorID,
      productID == other.productID,
      product == other.product
    else { return false }
    if let versionNumber, let otherVersion = other.versionNumber,
      versionNumber != otherVersion
    {
      return false
    }
    if let serialNumber {
      guard let otherSerial = other.serialNumber else { return true }
      return serialNumber == otherSerial
    }
    return true
  }

  func possiblyRepresentsSameDevice(as record: HIDCollectionRecord) -> Bool {
    guard record.vendorID == vendorID,
      record.productID == productID,
      record.product == product
    else { return false }
    if let versionNumber, let observedVersion = record.versionNumber,
      versionNumber != observedVersion
    {
      return false
    }
    if let serialNumber {
      guard let observedSerial = record.serialNumber else { return true }
      return serialNumber == observedSerial
    }
    return true
  }

  func exactlyRepresentsSameDevice(as record: HIDCollectionRecord) -> Bool {
    guard record.vendorID == vendorID,
      record.productID == productID,
      record.product == product,
      record.transport == "USB",
      record.versionNumber == versionNumber
    else { return false }
    if let serialNumber {
      return record.serialNumber == serialNumber
    }
    return record.locationID == locationID
  }
}

extension HIDReadOnlyReportRequest {
  var quarantineIdentity: HIDDeviceQuarantineIdentity? {
    guard vendorID == HIDEnumerator.vendorID,
      productID == HIDEnumerator.productID,
      product == "Archon AK47",
      let locationID
    else { return nil }
    return HIDDeviceQuarantineIdentity(
      vendorID: vendorID,
      productID: productID,
      product: product ?? "Archon AK47",
      locationID: locationID,
      versionNumber: versionNumber,
      serialNumber: serialNumber
    )
  }
}

enum HIDDeviceQuarantinePersistenceError: Error, Equatable {
  case busy
  case unavailable
  case invalidMarker
}

protocol HIDDeviceQuarantinePersisting: AnyObject {
  func load() throws -> [HIDDeviceQuarantineIdentity]
  func save(_ identities: [HIDDeviceQuarantineIdentity]) throws
  func acquireProcessLock() throws -> any HIDDeviceQuarantineProcessLocking
}

protocol HIDDeviceQuarantineProcessLocking: AnyObject {
  func release()
}

private final class HIDDeviceQuarantineClosureProcessLock:
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

  deinit {
    release()
  }
}

final class HIDDeviceQuarantineMemoryPersistence: HIDDeviceQuarantinePersisting {
  private let lock = NSLock()
  private var storedIdentities: [HIDDeviceQuarantineIdentity]
  private var processLockHeld = false
  var failsSaves = false

  init(identities: [HIDDeviceQuarantineIdentity] = []) {
    storedIdentities = identities
  }

  func load() throws -> [HIDDeviceQuarantineIdentity] {
    lock.lock()
    defer { lock.unlock() }
    return storedIdentities
  }

  func save(_ identities: [HIDDeviceQuarantineIdentity]) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !failsSaves else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    storedIdentities = identities
  }

  func acquireProcessLock() throws -> any HIDDeviceQuarantineProcessLocking {
    lock.lock()
    guard !processLockHeld else {
      lock.unlock()
      throw HIDDeviceQuarantinePersistenceError.busy
    }
    processLockHeld = true
    lock.unlock()
    return HIDDeviceQuarantineClosureProcessLock { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.processLockHeld = false
      self.lock.unlock()
    }
  }

  var identities: [HIDDeviceQuarantineIdentity] {
    lock.lock()
    defer { lock.unlock() }
    return storedIdentities
  }
}

/// Stores only target identities and no report contents. A removal is staged
/// in a second fail-closed marker before the active record is replaced. Until
/// the staged marker is durably removed, `load()` returns the union of both
/// records, so a failed clear cannot lose an active quarantine on relaunch.
final class HIDDeviceQuarantineFilePersistence: HIDDeviceQuarantinePersisting {
  static let maximumMarkerBytes = 64 * 1_024

  let markerURL: URL
  let pendingClearURL: URL
  let lockURL: URL
  private let lock = NSLock()
  private var preparedDirectoryPaths: Set<String> = []
  var injectedDirectorySynchronizationFailureCountdown: Int?

  init(markerURL: URL) {
    self.markerURL = markerURL
    pendingClearURL = markerURL.appendingPathExtension("pending-clear")
    lockURL = markerURL.deletingPathExtension().appendingPathExtension("lock")
  }

  static func production() -> HIDDeviceQuarantineFilePersistence {
    let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support",
      isDirectory: true
    )
    return HIDDeviceQuarantineFilePersistence(
      markerURL:
        base
        .appendingPathComponent("KeyCanvas", isDirectory: true)
        .appendingPathComponent("ak47-device-quarantine-v1.json", isDirectory: false)
    )
  }

  func load() throws -> [HIDDeviceQuarantineIdentity] {
    lock.lock()
    defer { lock.unlock() }
    do {
      return try loadLocked()
    } catch let error as HIDDeviceQuarantinePersistenceError {
      throw error
    } catch {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }

  func save(_ identities: [HIDDeviceQuarantineIdentity]) throws {
    lock.lock()
    defer { lock.unlock() }
    let directory = markerURL.deletingLastPathComponent()
    do {
      try prepareStorageDirectory(directory)
      let updated = try validated(identities)
      let current = try loadLocked()
      let removesIdentity = current.contains { !updated.contains($0) }

      if removesIdentity {
        // This snapshot is the rollback record. It is durable before the
        // active file can omit any identity.
        try write(current, to: pendingClearURL)
        try synchronizeDirectory(directory)
      }

      try write(updated, to: markerURL)
      try synchronizeDirectory(directory)

      guard FileManager.default.fileExists(atPath: pendingClearURL.path) else {
        return
      }
      do {
        try FileManager.default.removeItem(at: pendingClearURL)
        try synchronizeDirectory(directory)
      } catch {
        // removeItem may already have changed the directory before fsync
        // failed. Recreate and sync the old identities before surfacing the
        // failure so a new process still sees the quarantine.
        try? restorePendingClear(current, in: directory)
        throw HIDDeviceQuarantinePersistenceError.unavailable
      }
    } catch let error as HIDDeviceQuarantinePersistenceError {
      throw error
    } catch {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }

  private func loadLocked() throws -> [HIDDeviceQuarantineIdentity] {
    let active = try read(markerURL) ?? []
    let pending = try read(pendingClearURL) ?? []
    var seen = Set<HIDDeviceQuarantineIdentity>()
    return (active + pending).filter { seen.insert($0).inserted }
  }

  private func read(_ url: URL) throws -> [HIDDeviceQuarantineIdentity]? {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    defer { close(descriptor) }

    var status = stat()
    guard fstat(descriptor, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_size >= 0,
      status.st_size <= Self.maximumMarkerBytes
    else {
      throw HIDDeviceQuarantinePersistenceError.invalidMarker
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    guard let data = try handle.read(upToCount: Self.maximumMarkerBytes + 1),
      data.count <= Self.maximumMarkerBytes
    else {
      throw HIDDeviceQuarantinePersistenceError.invalidMarker
    }
    do {
      return try validated(
        JSONDecoder().decode([HIDDeviceQuarantineIdentity].self, from: data)
      )
    } catch let error as HIDDeviceQuarantinePersistenceError {
      throw error
    } catch {
      throw HIDDeviceQuarantinePersistenceError.invalidMarker
    }
  }

  private func validated(
    _ identities: [HIDDeviceQuarantineIdentity]
  ) throws -> [HIDDeviceQuarantineIdentity] {
    guard identities.count <= 16,
      Set(identities).count == identities.count,
      identities.allSatisfy({ identity in
        identity.vendorID == HIDEnumerator.vendorID
          && identity.productID == HIDEnumerator.productID
          && identity.product == "Archon AK47"
          && identity.locationID <= UInt64(UInt32.max)
          && identity.versionNumber == 0x0115
          && (identity.serialNumber.map {
            !$0.isEmpty && $0.utf8.count <= 256
          } ?? true)
      })
    else {
      throw HIDDeviceQuarantinePersistenceError.invalidMarker
    }
    return identities
  }

  private func write(
    _ identities: [HIDDeviceQuarantineIdentity],
    to url: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(try validated(identities))
    guard data.count <= Self.maximumMarkerBytes else {
      throw HIDDeviceQuarantinePersistenceError.invalidMarker
    }
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
    try synchronizeFile(url)
  }

  private func restorePendingClear(
    _ identities: [HIDDeviceQuarantineIdentity],
    in directory: URL
  ) throws {
    try write(identities, to: pendingClearURL)
    try synchronizeDirectory(directory)
  }

  func acquireProcessLock() throws -> any HIDDeviceQuarantineProcessLocking {
    lock.lock()
    defer { lock.unlock() }
    let directory = lockURL.deletingLastPathComponent()
    do {
      try prepareStorageDirectory(directory)
    } catch {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    let descriptor = open(
      lockURL.path,
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let lockError = errno
      close(descriptor)
      if lockError == EWOULDBLOCK || lockError == EAGAIN {
        throw HIDDeviceQuarantinePersistenceError.busy
      }
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    return HIDDeviceQuarantineClosureProcessLock {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
    }
  }

  /// Confirms both a storage directory and its parent entry before this
  /// persistence instance uses it. The per-instance cache avoids repeating
  /// directory fsyncs within one transaction while ensuring a fresh process
  /// re-establishes the durability boundary.
  private func prepareStorageDirectory(_ directory: URL) throws {
    let path = directory.standardizedFileURL.path
    guard !preparedDirectoryPaths.contains(path) else { return }

    var status = stat()
    if lstat(path, &status) == 0 {
      guard (status.st_mode & S_IFMT) == S_IFDIR else {
        throw HIDDeviceQuarantinePersistenceError.unavailable
      }
    } else {
      guard errno == ENOENT else {
        throw HIDDeviceQuarantinePersistenceError.unavailable
      }
      let parent = directory.deletingLastPathComponent()
      guard parent.standardizedFileURL.path != path else {
        throw HIDDeviceQuarantinePersistenceError.unavailable
      }
      try prepareStorageDirectory(parent)
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        // Another KeyCanvas process may have won the create race. Accept only
        // a real directory; never follow a substituted symlink.
        var racedStatus = stat()
        guard lstat(path, &racedStatus) == 0,
          (racedStatus.st_mode & S_IFMT) == S_IFDIR
        else {
          throw HIDDeviceQuarantinePersistenceError.unavailable
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
    guard descriptor >= 0 else { throw HIDDeviceQuarantinePersistenceError.unavailable }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }

  private func synchronizeDirectory(_ url: URL) throws {
    if let countdown = injectedDirectorySynchronizationFailureCountdown {
      if countdown <= 1 {
        injectedDirectorySynchronizationFailureCountdown = nil
        throw HIDDeviceQuarantinePersistenceError.unavailable
      }
      injectedDirectorySynchronizationFailureCountdown = countdown - 1
    }
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw HIDDeviceQuarantinePersistenceError.unavailable }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }
}

private struct HIDDeviceTransactionEvidenceSnapshot {
  let writeAheadPrepared: Bool
  let submittedReport: Bool
  let cancellationUnconfirmed: Bool
  let safePreSubmissionCleanup: Bool

  func requiresQuarantine(transactionSucceeded: Bool) -> Bool {
    cancellationUnconfirmed || (!transactionSucceeded && submittedReport)
  }

  func mayClearWriteAheadMarker(transactionSucceeded: Bool) -> Bool {
    guard !cancellationUnconfirmed else { return false }
    return transactionSucceeded || (!submittedReport && safePreSubmissionCleanup)
  }
}

/// Per-transaction evidence used to decide whether clearing the durable marker
/// is safe. `prepareForSubmission()` must finish before every IOHID Set/Get call.
final class HIDDeviceTransactionEvidence: @unchecked Sendable {
  typealias WriteAhead = @Sendable () throws -> Void

  private let lock = NSLock()
  private let writeAhead: WriteAhead
  private var writeAheadPrepared = false
  private var submittedReport = false
  private var cancellationUnconfirmed = false
  private var safePreSubmissionCleanup = false

  init(writeAhead: @escaping WriteAhead = {}) {
    self.writeAhead = writeAhead
  }

  func prepareForSubmission() throws {
    lock.lock()
    let alreadyPrepared = writeAheadPrepared
    lock.unlock()
    guard !alreadyPrepared else { return }
    try writeAhead()
    lock.lock()
    writeAheadPrepared = true
    lock.unlock()
  }

  func recordSubmittedReport() {
    lock.lock()
    submittedReport = true
    lock.unlock()
  }

  func recordUnconfirmedCancellation() {
    lock.lock()
    cancellationUnconfirmed = true
    lock.unlock()
  }

  func recordSafePreSubmissionCleanup() {
    lock.lock()
    if !submittedReport, !cancellationUnconfirmed {
      safePreSubmissionCleanup = true
    }
    lock.unlock()
  }

  var hasSubmittedReport: Bool {
    lock.lock()
    defer { lock.unlock() }
    return submittedReport
  }

  var failureRequiresPhysicalRecovery: Bool {
    let snapshot = snapshot
    return snapshot.requiresQuarantine(transactionSucceeded: false)
      || (snapshot.writeAheadPrepared
        && !snapshot.mayClearWriteAheadMarker(transactionSucceeded: false))
  }

  fileprivate var snapshot: HIDDeviceTransactionEvidenceSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return HIDDeviceTransactionEvidenceSnapshot(
      writeAheadPrepared: writeAheadPrepared,
      submittedReport: submittedReport,
      cancellationUnconfirmed: cancellationUnconfirmed,
      safePreSubmissionCleanup: safePreSubmissionCleanup
    )
  }
}

/// Mutable gate state is injectable for tests. Persistent markers have no
/// automatic reset path: absence and exact reappearance merely make a target
/// eligible for a separate USB-mode cable-removal acknowledgement.
final class HIDDeviceOperationGateState: @unchecked Sendable {
  private let lock = NSLock()
  private let persistence: any HIDDeviceQuarantinePersisting
  private var inUse = false
  private var activeTarget: HIDDeviceQuarantineIdentity?
  private var activeProcessLock: (any HIDDeviceQuarantineProcessLocking)?
  private var processGlobalQuarantine = false
  private var persistenceUnavailable = false
  private var quarantinedTargets: [HIDDeviceQuarantineIdentity]
  private var observedAbsentTargets: Set<HIDDeviceQuarantineIdentity> = []
  private var observedReappearedTargets: Set<HIDDeviceQuarantineIdentity> = []

  init(
    persistence: any HIDDeviceQuarantinePersisting = HIDDeviceQuarantineMemoryPersistence()
  ) {
    self.persistence = persistence
    do {
      quarantinedTargets = try persistence.load()
    } catch {
      quarantinedTargets = []
      persistenceUnavailable = true
    }
  }

  func acquire(
    target: HIDDeviceQuarantineIdentity? = nil
  ) -> HIDDeviceOperationGateAcquireResult {
    lock.lock()
    defer { lock.unlock() }
    if persistenceUnavailable || processGlobalQuarantine {
      return .quarantined
    }
    guard !inUse else { return .busy }
    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
    } catch HIDDeviceQuarantinePersistenceError.busy {
      return .busy
    } catch {
      persistenceUnavailable = true
      return .quarantined
    }
    do {
      quarantinedTargets = try persistence.load()
    } catch {
      processLock.release()
      persistenceUnavailable = true
      return .quarantined
    }
    if let target {
      if quarantinedTargets.contains(where: {
        $0.possiblyRepresentsSameDevice(as: target)
      }) {
        processLock.release()
        return .quarantined
      }
    } else if !quarantinedTargets.isEmpty {
      processLock.release()
      return .quarantined
    }
    inUse = true
    activeTarget = target
    activeProcessLock = processLock
    return .acquired
  }

  func makeTransactionEvidence() -> HIDDeviceTransactionEvidence {
    HIDDeviceTransactionEvidence { [weak self] in
      guard let self else { throw HIDDeviceQuarantinePersistenceError.unavailable }
      try self.armWriteAheadMarker()
    }
  }

  func finish(
    succeeded: Bool,
    evidence: HIDDeviceTransactionEvidence
  ) throws {
    let snapshot = evidence.snapshot
    lock.lock()
    let processLock = activeProcessLock
    defer {
      activeTarget = nil
      activeProcessLock = nil
      inUse = false
      lock.unlock()
      processLock?.release()
    }
    guard let activeTarget else {
      if snapshot.requiresQuarantine(transactionSucceeded: succeeded) {
        processGlobalQuarantine = true
      }
      return
    }
    if snapshot.requiresQuarantine(transactionSucceeded: succeeded) {
      try ensureMarkerPersisted(activeTarget)
      return
    }
    if snapshot.writeAheadPrepared,
      snapshot.mayClearWriteAheadMarker(transactionSucceeded: succeeded)
    {
      try removeMarker(activeTarget)
    }
  }

  func releaseReadOnlyOperation() {
    lock.lock()
    let processLock = activeProcessLock
    activeTarget = nil
    activeProcessLock = nil
    inUse = false
    lock.unlock()
    processLock?.release()
  }

  func quarantineActiveTarget() {
    lock.lock()
    if let activeTarget {
      do {
        try ensureMarkerPersisted(activeTarget)
      } catch {
        persistenceUnavailable = true
      }
    } else {
      processGlobalQuarantine = true
    }
    let processLock = activeProcessLock
    activeTarget = nil
    activeProcessLock = nil
    inUse = false
    lock.unlock()
    processLock?.release()
  }

  func quarantine(target: HIDDeviceQuarantineIdentity) throws {
    lock.lock()
    guard !persistenceUnavailable else {
      lock.unlock()
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    guard !inUse else {
      lock.unlock()
      throw HIDDeviceQuarantinePersistenceError.busy
    }
    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
      quarantinedTargets = try persistence.load()
      try ensureMarkerPersisted(target)
    } catch HIDDeviceQuarantinePersistenceError.busy {
      lock.unlock()
      throw HIDDeviceQuarantinePersistenceError.busy
    } catch {
      persistenceUnavailable = true
      lock.unlock()
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    lock.unlock()
    processLock.release()
  }

  var isQuarantined: Bool {
    lock.lock()
    defer { lock.unlock() }
    return persistenceUnavailable || processGlobalQuarantine || !quarantinedTargets.isEmpty
  }

  func observeSuccessfulEnumeration(_ records: [HIDCollectionRecord]) {
    lock.lock()
    guard !inUse, !persistenceUnavailable else {
      lock.unlock()
      return
    }
    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
      quarantinedTargets = try persistence.load()
    } catch HIDDeviceQuarantinePersistenceError.busy {
      lock.unlock()
      return
    } catch {
      persistenceUnavailable = true
      lock.unlock()
      return
    }
    defer {
      lock.unlock()
      processLock.release()
    }
    for target in quarantinedTargets {
      let possibleRecords = records.filter {
        target.possiblyRepresentsSameDevice(as: $0)
      }
      if possibleRecords.isEmpty {
        observedAbsentTargets.insert(target)
        observedReappearedTargets.remove(target)
        continue
      }
      guard observedAbsentTargets.contains(target),
        hasExactAK47Topology(possibleRecords, target: target)
      else { continue }
      observedReappearedTargets.insert(target)
    }
  }

  func recoveryState(
    for target: HIDDeviceQuarantineIdentity
  ) -> AK47DeviceQuarantineRecoveryState {
    lock.lock()
    defer { lock.unlock() }
    guard
      let marker = quarantinedTargets.first(where: {
        $0.possiblyRepresentsSameDevice(as: target)
      })
    else { return .notQuarantined }
    if observedReappearedTargets.contains(marker) {
      return .awaitingFullPowerCycleAcknowledgement
    }
    if observedAbsentTargets.contains(marker) {
      return .awaitingExactReappearance
    }
    return .awaitingObservedAbsence
  }

  func aggregateRecoveryState() -> AK47DeviceQuarantineRecoveryState {
    lock.lock()
    defer { lock.unlock() }
    guard !quarantinedTargets.isEmpty || persistenceUnavailable else {
      return .notQuarantined
    }
    if quarantinedTargets.contains(where: { observedReappearedTargets.contains($0) }) {
      return .awaitingFullPowerCycleAcknowledgement
    }
    if quarantinedTargets.contains(where: { observedAbsentTargets.contains($0) }) {
      return .awaitingExactReappearance
    }
    return .awaitingObservedAbsence
  }

  func acknowledgeFullPowerCycle(
    for target: HIDDeviceQuarantineIdentity
  ) throws {
    lock.lock()
    guard !inUse, !persistenceUnavailable else {
      lock.unlock()
      throw AK47DeviceWriteError.operationGatePoisoned
    }
    let processLock: any HIDDeviceQuarantineProcessLocking
    do {
      processLock = try persistence.acquireProcessLock()
      quarantinedTargets = try persistence.load()
    } catch {
      lock.unlock()
      throw AK47DeviceWriteError.operationGatePoisoned
    }
    defer {
      lock.unlock()
      processLock.release()
    }
    guard
      let marker = quarantinedTargets.first(where: {
        $0.possiblyRepresentsSameDevice(as: target)
      }),
      observedAbsentTargets.contains(marker),
      observedReappearedTargets.contains(marker)
    else {
      throw AK47DeviceWriteError.operationGatePoisoned
    }
    try removeMarker(marker)
  }

  private func armWriteAheadMarker() throws {
    lock.lock()
    defer { lock.unlock() }
    guard !persistenceUnavailable, let activeTarget else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    guard
      !quarantinedTargets.contains(where: {
        $0.possiblyRepresentsSameDevice(as: activeTarget)
      })
    else { return }
    var updated = quarantinedTargets
    updated.append(activeTarget)
    do {
      try persistence.save(updated)
      quarantinedTargets = updated
      observedAbsentTargets.remove(activeTarget)
      observedReappearedTargets.remove(activeTarget)
    } catch {
      persistenceUnavailable = true
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }

  private func ensureMarkerPersisted(_ target: HIDDeviceQuarantineIdentity) throws {
    guard !persistenceUnavailable else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    guard
      !quarantinedTargets.contains(where: {
        $0.possiblyRepresentsSameDevice(as: target)
      })
    else { return }
    var updated = quarantinedTargets
    updated.append(target)
    do {
      try persistence.save(updated)
      quarantinedTargets = updated
    } catch {
      persistenceUnavailable = true
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }

  private func removeMarker(_ target: HIDDeviceQuarantineIdentity) throws {
    guard !persistenceUnavailable else {
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
    let updated = quarantinedTargets.filter {
      !$0.possiblyRepresentsSameDevice(as: target)
    }
    guard updated.count != quarantinedTargets.count else { return }
    do {
      try persistence.save(updated)
      quarantinedTargets = updated
      observedAbsentTargets.remove(target)
      observedReappearedTargets.remove(target)
    } catch {
      persistenceUnavailable = true
      throw HIDDeviceQuarantinePersistenceError.unavailable
    }
  }

  private func hasExactAK47Topology(
    _ records: [HIDCollectionRecord],
    target: HIDDeviceQuarantineIdentity
  ) -> Bool {
    let exactRecords = records.filter { target.exactlyRepresentsSameDevice(as: $0) }
    guard exactRecords.count == 4 else { return false }
    let signatures = Set(
      exactRecords.compactMap { record -> HIDDeviceQuarantineCollectionSignature? in
        guard let usagePage = record.usagePage,
          let usage = record.usage,
          let input = record.maxInputReportSize,
          let output = record.maxOutputReportSize,
          let feature = record.maxFeatureReportSize
        else { return nil }
        return HIDDeviceQuarantineCollectionSignature(
          usagePage: usagePage,
          usage: usage,
          input: input,
          output: output,
          feature: feature
        )
      })
    return signatures == HIDDeviceQuarantineCollectionSignature.expectedAK47
  }
}

private struct HIDDeviceQuarantineCollectionSignature: Hashable {
  let usagePage: UInt64
  let usage: UInt64
  let input: UInt64
  let output: UInt64
  let feature: UInt64

  static let expectedAK47: Set<Self> = [
    Self(usagePage: 0x0001, usage: 0x0006, input: 8, output: 1, feature: 0),
    Self(usagePage: 0x000C, usage: 0x0001, input: 16, output: 1, feature: 1),
    Self(usagePage: 0xFF13, usage: 0x0001, input: 64, output: 64, feature: 64),
    Self(usagePage: 0xFF68, usage: 0x0061, input: 64, output: 4_096, feature: 0),
  ]
}

/// Shared production gate. The marker is armed before the first IOHID report
/// call and survives process termination. It cannot be cleared by relaunching.
enum HIDDeviceOperationGate {
  private static let state = HIDDeviceOperationGateState(
    persistence: HIDDeviceQuarantineFilePersistence.production()
  )

  static func acquireResult(
    for target: HIDDeviceQuarantineIdentity? = nil,
    qualificationAdmission: AK47LCDQualificationGateAdmission? = nil
  ) -> HIDDeviceOperationGateAcquireResult {
    if AK47LCDExtendedUploadQualification.requiresDeviceOperationQuarantine {
      guard let target, let qualificationAdmission,
        AK47LCDExtendedUploadQualification.consumeGateAdmission(
          qualificationAdmission,
          for: target
        )
      else {
        return .quarantined
      }
    } else if qualificationAdmission != nil {
      // A qualification capability is meaningful only while its exact durable
      // lease is the reason generic device operations are interlocked.
      return .quarantined
    }
    return state.acquire(target: target)
  }

  static func acquire() -> Bool {
    acquireResult() == .acquired
  }

  static func makeTransactionEvidence() -> HIDDeviceTransactionEvidence {
    state.makeTransactionEvidence()
  }

  static func release() {
    state.releaseReadOnlyOperation()
  }

  static func finish(
    succeeded: Bool,
    evidence: HIDDeviceTransactionEvidence
  ) throws {
    try state.finish(succeeded: succeeded, evidence: evidence)
  }

  static func poison() {
    state.quarantineActiveTarget()
  }

  static func quarantine(target: HIDDeviceQuarantineIdentity) throws {
    try state.quarantine(target: target)
  }

  static var isPoisoned: Bool {
    state.isQuarantined
      || AK47LCDExtendedUploadQualification.requiresDeviceOperationQuarantine
  }

  fileprivate static func observeSuccessfulEnumeration(
    _ records: [HIDCollectionRecord]
  ) {
    state.observeSuccessfulEnumeration(records)
  }

  fileprivate static func recoveryState(
    for target: HIDDeviceQuarantineIdentity
  ) -> AK47DeviceQuarantineRecoveryState {
    state.recoveryState(for: target)
  }

  fileprivate static func aggregateRecoveryState() -> AK47DeviceQuarantineRecoveryState {
    state.aggregateRecoveryState()
  }

  fileprivate static func acknowledgeFullPowerCycle(
    for target: HIDDeviceQuarantineIdentity
  ) throws {
    try state.acknowledgeFullPowerCycle(for: target)
  }
}

package enum AK47DeviceQuarantineRecovery {
  /// Call only after a successful real IOHID registry enumeration. Preview or
  /// cached records are not valid recovery observations.
  package static func observeSuccessfulHardwareEnumeration(
    _ records: [HIDCollectionRecord]
  ) {
    HIDDeviceOperationGate.observeSuccessfulEnumeration(records)
  }

  package static func state(
    for target: AK47WiredDeviceTarget
  ) -> AK47DeviceQuarantineRecoveryState {
    HIDDeviceOperationGate.recoveryState(
      for: HIDDeviceQuarantineIdentity(target: target)
    )
  }

  package static var state: AK47DeviceQuarantineRecoveryState {
    HIDDeviceOperationGate.aggregateRecoveryState()
  }

  /// This acknowledgement is accepted only after this process observed the
  /// marked device absent and then saw the same identity return with the exact
  /// four-collection topology. The UI must separately confirm that the selector
  /// stayed in USB mode while cable removal fully powered down the LCD, LEDs,
  /// and device before reconnecting at the original USB location.
  package static func acknowledgeFullPowerCycle(
    for target: AK47WiredDeviceTarget
  ) throws {
    try target.validate()
    try HIDDeviceOperationGate.acknowledgeFullPowerCycle(
      for: HIDDeviceQuarantineIdentity(target: target)
    )
  }
}
