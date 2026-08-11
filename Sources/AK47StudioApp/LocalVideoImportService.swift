import AK47InspectorCore
@preconcurrency import AVFoundation
import CoreGraphics
import Darwin
import Foundation

enum LocalVideoImportError: Error, Equatable, LocalizedError {
  case notLocalRegularFile
  case symbolicLinkNotAllowed
  case fileTooLarge(maximumBytes: Int)
  case sourceChanged
  case snapshotCreationFailed
  case inspectionTimedOut
  case extractionTimedOut
  case unreadableAsset
  case missingVideoTrack
  case invalidOrientedDimensions
  case frameExtractionFailed(index: Int, description: String)
  case extractedTimeOutsideSelection(index: Int)
  case nonMonotonicExtractedTime(index: Int)
  case inconsistentFrameDimensions
  case extractedFrameOutsideWorkPlan
  case pixelConversionFailed(index: Int)

  var errorDescription: String? {
    switch self {
    case .notLocalRegularFile:
      return "Choose a local regular video file. Network URLs and special files are not supported."
    case .symbolicLinkNotAllowed:
      return "Symbolic-link video sources are not accepted. Choose the local file itself."
    case .fileTooLarge(let maximumBytes):
      return "The local video exceeds the bounded \(maximumBytes)-byte source-file limit."
    case .sourceChanged:
      return "The local video changed after it was inspected. Choose it again before converting."
    case .snapshotCreationFailed:
      return "A private immutable working copy of the local video could not be created."
    case .inspectionTimedOut:
      return "Local video inspection exceeded its bounded time limit."
    case .extractionTimedOut:
      return "Local video frame extraction exceeded its bounded time limit."
    case .unreadableAsset:
      return "AVFoundation could not read this local video."
    case .missingVideoTrack:
      return "The selected file has no AVFoundation-readable video track."
    case .invalidOrientedDimensions:
      return "The video track has invalid dimensions after applying its display orientation."
    case .frameExtractionFailed(let index, let description):
      return "Could not extract video frame \(index + 1): \(description)"
    case .extractedTimeOutsideSelection(let index):
      return "Video frame \(index + 1) resolved outside the bounded nearest-frame tolerance."
    case .nonMonotonicExtractedTime(let index):
      return "Video frame \(index + 1) resolved before the preceding extracted frame."
    case .inconsistentFrameDimensions:
      return "The video returned inconsistent frame dimensions during bounded extraction."
    case .extractedFrameOutsideWorkPlan:
      return "AVFoundation returned a frame outside the preflighted decoded-work bounds."
    case .pixelConversionFailed(let index):
      return "Could not convert video frame \(index + 1) into the editor's local RGBA format."
    }
  }
}

struct LocalVideoImportDescriptor: Equatable, Sendable {
  let sourceURL: URL
  let metadata: AK47LCDVideoSourceMetadata
  let nominalFramesPerSecond: Double?
  fileprivate let snapshot: LocalVideoSnapshot

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sourceURL == rhs.sourceURL
      && lhs.metadata == rhs.metadata
      && lhs.nominalFramesPerSecond == rhs.nominalFramesPerSecond
      && lhs.snapshot.identifier == rhs.snapshot.identifier
  }
}

struct LocalVideoExtractionProgress: Equatable, Sendable {
  let completedFrameCount: Int
  let totalFrameCount: Int
}

struct LocalVideoImportResult: Equatable, Sendable {
  let descriptor: LocalVideoImportDescriptor
  let plan: AK47LCDVideoImportPlan
  let decodedSource: AK47LCDDecodedGIF
}

private struct LocalVideoTrackInspection: Sendable {
  let isEnabled: Bool
  let orientedWidth: Int
  let orientedHeight: Int
  let nominalFramesPerSecond: Double?
}

enum LocalVideoImportService {
  static let maximumSourceFileByteCount = 1 * 1_024 * 1_024 * 1_024
  static let inspectionDeadlineMilliseconds = 30_000
  static let maximumExtractionDeadlineMilliseconds = 120_000
  static let assetReferenceRestrictionsRawValue =
    AVAssetReferenceRestrictions.forbidAll.rawValue

  static func inspect(url: URL) async throws -> LocalVideoImportDescriptor {
    try await LocalVideoDeadline.run(
      milliseconds: inspectionDeadlineMilliseconds,
      timeoutError: LocalVideoImportError.inspectionTimedOut
    ) {
      let snapshot = try LocalVideoSnapshot.create(
        sourceURL: url,
        maximumByteCount: maximumSourceFileByteCount
      )
      return try await inspectSnapshot(snapshot, originalURL: url)
    }
  }

  static func extract(
    descriptor: LocalVideoImportDescriptor,
    selection: AK47LCDVideoSelection,
    progress: @escaping @Sendable (LocalVideoExtractionProgress) -> Void = { _ in }
  ) async throws -> LocalVideoImportResult {
    let plan = try AK47LCDVideoImportPlan(
      metadata: descriptor.metadata,
      selection: selection
    )
    let extractionDeadline = min(
      maximumExtractionDeadlineMilliseconds,
      15_000 + (plan.expectedFrameCount * 1_500)
    )
    let progressGate = LocalVideoProgressGate(progress)
    return try await LocalVideoDeadline.run(
      milliseconds: extractionDeadline,
      timeoutError: LocalVideoImportError.extractionTimedOut,
      onDeadlineOrCancellation: { progressGate.cancel() },
      operation: {
        try await extractOffMain(
          descriptor: descriptor,
          plan: plan,
          progress: { progressGate.report($0) }
        )
      }
    )
  }

  private static func inspectSnapshot(
    _ snapshot: LocalVideoSnapshot,
    originalURL: URL
  ) async throws -> LocalVideoImportDescriptor {
    try Task.checkCancellation()
    guard snapshot.hasExpectedIdentity else { throw LocalVideoImportError.sourceChanged }
    let asset = AVURLAsset(url: snapshot.fileURL, options: secureAssetOptions)
    let assetBox = LocalVideoAssetBox(asset)
    return try await withTaskCancellationHandler {
      try await inspectAsset(asset, snapshot: snapshot, originalURL: originalURL)
    } onCancel: {
      // AVFoundation async property loading is cancellation-cooperative but is
      // not guaranteed to observe Task cancellation alone.
      assetBox.asset.cancelLoading()
    }
  }

  private static func inspectAsset(
    _ asset: AVURLAsset,
    snapshot: LocalVideoSnapshot,
    originalURL: URL
  ) async throws -> LocalVideoImportDescriptor {
    guard try await asset.load(.isReadable) else {
      throw LocalVideoImportError.unreadableAsset
    }
    let duration = try await asset.load(.duration)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard !tracks.isEmpty else {
      throw LocalVideoImportError.missingVideoTrack
    }
    // AVAssetImageGenerator can choose any enabled visual track. Validate
    // every video track rather than trusting metadata from tracks.first, so a
    // secondary track cannot bypass raw/coded/oriented work bounds.
    var trackInspections: [LocalVideoTrackInspection] = []
    trackInspections.reserveCapacity(tracks.count)
    for track in tracks {
      try Task.checkCancellation()
      trackInspections.append(try await inspectTrack(track))
    }
    guard
      let primaryTrack = trackInspections.first(where: \.isEnabled)
        ?? trackInspections.first
    else {
      throw LocalVideoImportError.missingVideoTrack
    }

    let seconds = CMTimeGetSeconds(duration)
    guard seconds.isFinite, seconds > 0,
      seconds <= Double(AK47LCDVideoSourceMetadata.maximumDurationMilliseconds) / 1_000
    else {
      throw LocalVideoImportError.unreadableAsset
    }
    let durationMilliseconds = max(1, Int((seconds * 1_000).rounded(.down)))
    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: durationMilliseconds,
      width: primaryTrack.orientedWidth,
      height: primaryTrack.orientedHeight
    )
    guard snapshot.hasExpectedIdentity else { throw LocalVideoImportError.sourceChanged }

    let finiteFrameRate = primaryTrack.nominalFramesPerSecond
    return LocalVideoImportDescriptor(
      sourceURL: originalURL,
      metadata: metadata,
      nominalFramesPerSecond: finiteFrameRate,
      snapshot: snapshot
    )
  }

  private static func inspectTrack(_ track: AVAssetTrack) async throws
    -> LocalVideoTrackInspection
  {
    async let naturalSize = track.load(.naturalSize)
    async let preferredTransform = track.load(.preferredTransform)
    async let nominalFrameRate = track.load(.nominalFrameRate)
    async let formatDescriptions = track.load(.formatDescriptions)
    async let isEnabled = track.load(.isEnabled)
    let (
      loadedSize,
      loadedTransform,
      loadedFrameRate,
      loadedFormatDescriptions,
      loadedIsEnabled
    ) = try await (
      naturalSize,
      preferredTransform,
      nominalFrameRate,
      formatDescriptions,
      isEnabled
    )
    try Task.checkCancellation()

    _ = try validatedBoundedDimensions(
      width: abs(Double(loadedSize.width)),
      height: abs(Double(loadedSize.height))
    )
    guard !loadedFormatDescriptions.isEmpty else {
      throw LocalVideoImportError.invalidOrientedDimensions
    }
    for description in loadedFormatDescriptions {
      let dimensions = CMVideoFormatDescriptionGetDimensions(description)
      try validateRawDimensions(
        width: Int(dimensions.width),
        height: Int(dimensions.height)
      )
    }

    let transformValues = [
      loadedTransform.a,
      loadedTransform.b,
      loadedTransform.c,
      loadedTransform.d,
      loadedTransform.tx,
      loadedTransform.ty,
    ]
    guard transformValues.allSatisfy(\.isFinite) else {
      throw LocalVideoImportError.invalidOrientedDimensions
    }
    let orientedRectangle = CGRect(origin: .zero, size: loadedSize)
      .applying(loadedTransform)
      .standardized
    let orientedDimensions = try validatedBoundedDimensions(
      width: Double(orientedRectangle.width),
      height: Double(orientedRectangle.height)
    )
    let frameRate = Double(loadedFrameRate)
    return LocalVideoTrackInspection(
      isEnabled: loadedIsEnabled,
      orientedWidth: orientedDimensions.width,
      orientedHeight: orientedDimensions.height,
      nominalFramesPerSecond: frameRate.isFinite && frameRate > 0 ? frameRate : nil
    )
  }

  /// Converts untrusted AVFoundation floating-point dimensions only after
  /// finite, range and aggregate-work checks. Keeping this internal makes the
  /// no-trap boundary directly regression-testable.
  static func validatedBoundedDimensions(width: Double, height: Double) throws
    -> (width: Int, height: Int)
  {
    guard width.isFinite, height.isFinite,
      width > 0, height > 0,
      width <= Double(AK47LCDVideoSourceMetadata.maximumInputDimension),
      height <= Double(AK47LCDVideoSourceMetadata.maximumInputDimension),
      width * height <= Double(AK47LCDVideoSourceMetadata.maximumInputPixelCount)
    else {
      throw LocalVideoImportError.invalidOrientedDimensions
    }
    let roundedWidth = width.rounded()
    let roundedHeight = height.rounded()
    guard roundedWidth >= 1, roundedHeight >= 1,
      roundedWidth <= Double(Int.max), roundedHeight <= Double(Int.max)
    else {
      throw LocalVideoImportError.invalidOrientedDimensions
    }
    let dimensions = (width: Int(roundedWidth), height: Int(roundedHeight))
    try validateRawDimensions(width: dimensions.width, height: dimensions.height)
    return dimensions
  }

  static func validateRawDimensions(width: Int, height: Int) throws {
    do {
      _ = try AK47LCDVideoSourceMetadata(
        durationMilliseconds: 1,
        width: width,
        height: height
      )
    } catch {
      throw LocalVideoImportError.invalidOrientedDimensions
    }
  }

  private static var secureAssetOptions: [String: Any] {
    [
      AVURLAssetPreferPreciseDurationAndTimingKey: true,
      AVURLAssetReferenceRestrictionsKey: assetReferenceRestrictionsRawValue,
    ]
  }

  private static func extractOffMain(
    descriptor: LocalVideoImportDescriptor,
    plan: AK47LCDVideoImportPlan,
    progress: @escaping @Sendable (LocalVideoExtractionProgress) -> Void
  ) async throws -> LocalVideoImportResult {
    try Task.checkCancellation()
    guard descriptor.snapshot.hasExpectedIdentity else {
      throw LocalVideoImportError.sourceChanged
    }

    let asset = AVURLAsset(
      url: descriptor.snapshot.fileURL,
      options: secureAssetOptions
    )
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.apertureMode = .encodedPixels
    generator.maximumSize = CGSize(
      width: plan.maximumExtractionWidth,
      height: plan.maximumExtractionHeight
    )
    // A bounded half-sample tolerance supports 29.97 fps, VFR and edit-list
    // timelines whose presentation times do not land on integer milliseconds.
    // Exact-zero tolerance rejects otherwise valid local videos on those grids.
    let sampleTolerance = CMTime(
      value: 1,
      timescale: CMTimeScale(plan.selection.framesPerSecond * 2)
    )
    generator.requestedTimeToleranceBefore = sampleTolerance
    generator.requestedTimeToleranceAfter = sampleTolerance
    let generatorBox = LocalVideoImageGeneratorBox(generator)

    return try await withTaskCancellationHandler {
      var decodedFrames: [AK47LCDDecodedGIFFrame] = []
      decodedFrames.reserveCapacity(plan.expectedFrameCount)
      var extractedWidth: Int?
      var extractedHeight: Int?
      var totalPixels = 0
      var previousActualTime: CMTime?
      let selectionStart = CMTime(
        value: CMTimeValue(plan.selection.startMilliseconds),
        timescale: 1_000
      )
      let selectionEnd = CMTime(
        value: CMTimeValue(plan.selection.endMilliseconds),
        timescale: 1_000
      )
      // Start/end controls are millisecond values while encoded frame grids can
      // be fractional. Accept only the same half-sample nearest-frame window
      // advertised by the generator, including at the two selection edges.
      let earliestAcceptedTime = CMTimeSubtract(selectionStart, sampleTolerance)
      let latestAcceptedTime = CMTimeAdd(selectionEnd, sampleTolerance)

      for (index, sample) in plan.samples.enumerated() {
        try Task.checkCancellation()
        let requestedTime = CMTime(
          value: CMTimeValue(sample.timestampMilliseconds), timescale: 1_000)
        let image: CGImage
        let actualTime: CMTime
        do {
          let generated = try await generatorBox.generator.image(at: requestedTime)
          image = generated.image
          actualTime = generated.actualTime
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          throw LocalVideoImportError.frameExtractionFailed(
            index: index,
            description: error.localizedDescription
          )
        }
        // Do not perform pixel conversion or emit progress after a deadline or
        // user cancellation won while AVFoundation was awaiting a frame.
        try Task.checkCancellation()

        let earliestRequestedTime = CMTimeSubtract(requestedTime, sampleTolerance)
        let latestRequestedTime = CMTimeAdd(requestedTime, sampleTolerance)
        guard actualTime.isValid, actualTime.isNumeric,
          CMTimeCompare(actualTime, earliestRequestedTime) >= 0,
          CMTimeCompare(actualTime, latestRequestedTime) <= 0,
          CMTimeCompare(actualTime, earliestAcceptedTime) >= 0,
          CMTimeCompare(actualTime, latestAcceptedTime) < 0
        else {
          throw LocalVideoImportError.extractedTimeOutsideSelection(index: index)
        }
        if let previousActualTime, CMTimeCompare(actualTime, previousActualTime) < 0 {
          throw LocalVideoImportError.nonMonotonicExtractedTime(index: index)
        }
        previousActualTime = actualTime

        guard image.width > 0, image.height > 0,
          image.width <= plan.maximumExtractionWidth,
          image.height <= plan.maximumExtractionHeight
        else {
          throw LocalVideoImportError.extractedFrameOutsideWorkPlan
        }
        if let extractedWidth, let extractedHeight {
          guard image.width == extractedWidth, image.height == extractedHeight else {
            throw LocalVideoImportError.inconsistentFrameDimensions
          }
        } else {
          extractedWidth = image.width
          extractedHeight = image.height
        }

        let (framePixels, frameOverflow) = image.width.multipliedReportingOverflow(by: image.height)
        let (newTotalPixels, totalOverflow) = totalPixels.addingReportingOverflow(framePixels)
        guard !frameOverflow, !totalOverflow,
          framePixels <= 2_000_000,
          newTotalPixels <= AK47LCDFormat.maximumTotalDecodedPixels
        else {
          throw LocalVideoImportError.extractedFrameOutsideWorkPlan
        }
        totalPixels = newTotalPixels

        guard let rgbaImage = makeOpaqueRGBAImage(image) else {
          throw LocalVideoImportError.pixelConversionFailed(index: index)
        }
        decodedFrames.append(
          AK47LCDDecodedGIFFrame(
            image: rgbaImage,
            sourceDelay: try AK47LCDSourceDelay(milliseconds: sample.delayMilliseconds)
          )
        )
        try Task.checkCancellation()
        progress(
          LocalVideoExtractionProgress(
            completedFrameCount: decodedFrames.count,
            totalFrameCount: plan.expectedFrameCount
          )
        )
      }

      try Task.checkCancellation()
      guard descriptor.snapshot.hasExpectedIdentity else {
        throw LocalVideoImportError.sourceChanged
      }
      guard let extractedWidth, let extractedHeight,
        decodedFrames.count == plan.expectedFrameCount
      else {
        throw LocalVideoImportError.inconsistentFrameDimensions
      }
      let decodedSource = AK47LCDDecodedGIF(
        sourceWidth: extractedWidth,
        sourceHeight: extractedHeight,
        frames: decodedFrames
      )
      return LocalVideoImportResult(
        descriptor: descriptor,
        plan: plan,
        decodedSource: decodedSource
      )
    } onCancel: {
      generatorBox.generator.cancelAllCGImageGeneration()
    }
  }

  private static func makeOpaqueRGBAImage(_ image: CGImage) -> AK47LCDRGBAImage? {
    let (pixelCount, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
    let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
    guard !pixelOverflow, !byteOverflow else { return nil }
    var pixels = Data(count: byteCount)
    let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        )
      else {
        return false
      }
      context.setBlendMode(.copy)
      context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
      context.setBlendMode(.normal)
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    guard didDraw else { return nil }
    return try? AK47LCDRGBAImage(width: image.width, height: image.height, pixels: pixels)
  }
}

private struct LocalVideoFileIdentity: Equatable, Sendable {
  let device: UInt64
  let inode: UInt64
  let byteCount: Int
  let modificationSeconds: Int64
  let modificationNanoseconds: Int64
  let changeSeconds: Int64
  let changeNanoseconds: Int64

  init(status: stat) throws {
    guard (status.st_mode & S_IFMT) == S_IFREG, status.st_size > 0,
      status.st_size <= off_t(Int.max)
    else {
      throw LocalVideoImportError.notLocalRegularFile
    }
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
    byteCount = Int(status.st_size)
    modificationSeconds = Int64(status.st_mtimespec.tv_sec)
    modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
    changeSeconds = Int64(status.st_ctimespec.tv_sec)
    changeNanoseconds = Int64(status.st_ctimespec.tv_nsec)
  }

  static func read(url: URL) throws -> Self {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.lstat(path, &status)
    }
    guard result == 0 else { throw LocalVideoImportError.notLocalRegularFile }
    if (status.st_mode & S_IFMT) == S_IFLNK {
      throw LocalVideoImportError.symbolicLinkNotAllowed
    }
    return try Self(status: status)
  }
}

private final class LocalVideoSnapshot: @unchecked Sendable {
  let identifier = UUID()
  let fileURL: URL
  private let directoryURL: URL
  private let identity: LocalVideoFileIdentity

  var hasExpectedIdentity: Bool {
    (try? LocalVideoFileIdentity.read(url: fileURL)) == identity
  }

  private init(
    fileURL: URL,
    directoryURL: URL,
    identity: LocalVideoFileIdentity
  ) {
    self.fileURL = fileURL
    self.directoryURL = directoryURL
    self.identity = identity
  }

  deinit {
    try? FileManager.default.removeItem(at: directoryURL)
  }

  static func create(sourceURL: URL, maximumByteCount: Int) throws -> LocalVideoSnapshot {
    guard sourceURL.isFileURL else { throw LocalVideoImportError.notLocalRegularFile }
    var linkStatus = stat()
    let linkResult = sourceURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.lstat(path, &linkStatus)
    }
    guard linkResult == 0 else { throw LocalVideoImportError.notLocalRegularFile }
    guard (linkStatus.st_mode & S_IFMT) != S_IFLNK else {
      throw LocalVideoImportError.symbolicLinkNotAllowed
    }

    let sourceDescriptor = sourceURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    }
    guard sourceDescriptor >= 0 else { throw LocalVideoImportError.notLocalRegularFile }
    defer { Darwin.close(sourceDescriptor) }

    var sourceStatus = stat()
    guard Darwin.fstat(sourceDescriptor, &sourceStatus) == 0 else {
      throw LocalVideoImportError.notLocalRegularFile
    }
    let sourceIdentity = try LocalVideoFileIdentity(status: sourceStatus)
    guard sourceIdentity.byteCount <= maximumByteCount else {
      throw LocalVideoImportError.fileTooLarge(maximumBytes: maximumByteCount)
    }

    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("KeyCanvasVideo-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      throw LocalVideoImportError.snapshotCreationFailed
    }
    var shouldRemoveDirectory = true
    defer {
      if shouldRemoveDirectory {
        try? FileManager.default.removeItem(at: directoryURL)
      }
    }

    let rawExtension = sourceURL.pathExtension.lowercased()
    let safeExtension =
      !rawExtension.isEmpty && rawExtension.count <= 12
        && rawExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
      ? rawExtension : "mov"
    let fileURL = directoryURL.appendingPathComponent("source.\(safeExtension)")
    let destinationDescriptor = fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    }
    guard destinationDescriptor >= 0 else {
      throw LocalVideoImportError.snapshotCreationFailed
    }
    defer { Darwin.close(destinationDescriptor) }

    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    var totalCopied = 0
    while totalCopied < sourceIdentity.byteCount {
      if Task.isCancelled { throw CancellationError() }
      let requested = min(buffer.count, sourceIdentity.byteCount - totalCopied)
      let readCount = buffer.withUnsafeMutableBytes { bytes -> Int in
        guard let baseAddress = bytes.baseAddress else { return -1 }
        return Darwin.read(sourceDescriptor, baseAddress, requested)
      }
      if readCount < 0, errno == EINTR { continue }
      guard readCount > 0 else { throw LocalVideoImportError.sourceChanged }

      var written = 0
      while written < readCount {
        if Task.isCancelled { throw CancellationError() }
        let writeCount = buffer.withUnsafeBytes { bytes -> Int in
          guard let baseAddress = bytes.baseAddress else { return -1 }
          return Darwin.write(
            destinationDescriptor,
            baseAddress.advanced(by: written),
            readCount - written
          )
        }
        if writeCount < 0, errno == EINTR { continue }
        guard writeCount > 0 else { throw LocalVideoImportError.snapshotCreationFailed }
        written += writeCount
      }
      totalCopied += readCount
    }
    var trailingByte: UInt8 = 0
    var trailingRead: Int
    repeat {
      trailingRead = Darwin.read(sourceDescriptor, &trailingByte, 1)
    } while trailingRead < 0 && errno == EINTR
    guard trailingRead == 0 else { throw LocalVideoImportError.sourceChanged }

    var finalSourceStatus = stat()
    guard Darwin.fstat(sourceDescriptor, &finalSourceStatus) == 0,
      try LocalVideoFileIdentity(status: finalSourceStatus) == sourceIdentity,
      Darwin.fsync(destinationDescriptor) == 0,
      Darwin.fchmod(destinationDescriptor, 0o400) == 0
    else {
      throw LocalVideoImportError.sourceChanged
    }
    let snapshotIdentity = try LocalVideoFileIdentity.read(url: fileURL)
    shouldRemoveDirectory = false
    return LocalVideoSnapshot(
      fileURL: fileURL,
      directoryURL: directoryURL,
      identity: snapshotIdentity
    )
  }
}

enum LocalVideoDeadline {
  static func run<Value: Sendable>(
    milliseconds: Int,
    timeoutError: Error,
    onDeadlineOrCancellation: @escaping @Sendable () -> Void = {},
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let gate = LocalVideoDeadlineGate<Value>()
    let operationTask = Task.detached(priority: .userInitiated) {
      try await operation()
    }
    let timerTask = Task.detached {
      do {
        try await Task.sleep(nanoseconds: UInt64(max(1, milliseconds)) * 1_000_000)
      } catch {
        return
      }
      _ = gate.resolve(.failure(timeoutError)) {
        onDeadlineOrCancellation()
        operationTask.cancel()
      }
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        gate.install(continuation)
        Task.detached {
          _ = gate.resolve(await operationTask.result) {
            // The operation won, so do not leave the deadline sleeper alive
            // for its full 30...120 second interval.
            timerTask.cancel()
          }
        }
      }
    } onCancel: {
      _ = gate.resolve(.failure(CancellationError())) {
        onDeadlineOrCancellation()
        operationTask.cancel()
        timerTask.cancel()
      }
    }
  }
}

private final class LocalVideoDeadlineGate<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, Error>?
  private var pendingResult: Result<Value, Error>?
  private var isResolved = false

  func install(_ continuation: CheckedContinuation<Value, Error>) {
    lock.lock()
    if let pendingResult {
      self.pendingResult = nil
      lock.unlock()
      continuation.resume(with: pendingResult)
    } else {
      self.continuation = continuation
      lock.unlock()
    }
  }

  @discardableResult
  func resolve(
    _ result: Result<Value, Error>,
    beforeResume: () -> Void = {}
  ) -> Bool {
    lock.lock()
    guard !isResolved else {
      lock.unlock()
      return false
    }
    isResolved = true
    if let continuation {
      self.continuation = nil
      lock.unlock()
      beforeResume()
      continuation.resume(with: result)
    } else {
      pendingResult = result
      lock.unlock()
      beforeResume()
    }
    return true
  }
}

private final class LocalVideoAssetBox: @unchecked Sendable {
  let asset: AVURLAsset

  init(_ asset: AVURLAsset) {
    self.asset = asset
  }
}

private final class LocalVideoImageGeneratorBox: @unchecked Sendable {
  let generator: AVAssetImageGenerator

  init(_ generator: AVAssetImageGenerator) {
    self.generator = generator
  }
}

private final class LocalVideoProgressGate: @unchecked Sendable {
  private let lock = NSLock()
  private let progress: @Sendable (LocalVideoExtractionProgress) -> Void
  private var isCancelled = false

  init(_ progress: @escaping @Sendable (LocalVideoExtractionProgress) -> Void) {
    self.progress = progress
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    lock.unlock()
  }

  func report(_ value: LocalVideoExtractionProgress) {
    lock.lock()
    guard !isCancelled else {
      lock.unlock()
      return
    }
    // Keep the cancellation check and callback mutually exclusive so the
    // deadline cannot return and then permit a late progress callback.
    progress(value)
    lock.unlock()
  }
}
