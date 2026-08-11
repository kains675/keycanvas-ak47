import Foundation

public enum AK47LCDVideoImportError: Error, Equatable, LocalizedError {
  case invalidDuration(milliseconds: Int)
  case invalidSourceDimensions(width: Int, height: Int)
  case inputWorkLimitExceeded
  case invalidFrameRate(Int)
  case invalidSelection(startMilliseconds: Int, endMilliseconds: Int)
  case selectionExceedsDuration(endMilliseconds: Int, durationMilliseconds: Int)
  case frameLimitExceeded(requested: Int, maximum: Int)
  case decodedWorkLimitExceeded
  case arithmeticOverflow

  public var errorDescription: String? {
    switch self {
    case .invalidDuration(let milliseconds):
      return "The local video duration must be between 1 ms and 24 hours; got \(milliseconds) ms."
    case .invalidSourceDimensions(let width, let height):
      return "The local video has invalid oriented dimensions: \(width)x\(height)."
    case .inputWorkLimitExceeded:
      return "The local video dimensions exceed the bounded 8K input inspection limit."
    case .invalidFrameRate(let framesPerSecond):
      return "Video sampling must use 2...60 frames per second; got \(framesPerSecond)."
    case .invalidSelection(let startMilliseconds, let endMilliseconds):
      return
        "The video selection must have a non-negative start before its end; got \(startMilliseconds)...\(endMilliseconds) ms."
    case .selectionExceedsDuration(let endMilliseconds, let durationMilliseconds):
      return
        "The video selection ends at \(endMilliseconds) ms, beyond the \(durationMilliseconds) ms asset duration."
    case .frameLimitExceeded(let requested, let maximum):
      return
        "The selected video range would create \(requested) frames; the offline limit is \(maximum)."
    case .decodedWorkLimitExceeded:
      return "The selected video range exceeds the bounded decoded-frame work limit."
    case .arithmeticOverflow:
      return "The selected video range overflowed a checked planning calculation."
    }
  }
}

/// AVFoundation-independent metadata for a local, oriented video track.
public struct AK47LCDVideoSourceMetadata: Equatable, Sendable {
  public static let maximumDurationMilliseconds = 24 * 60 * 60 * 1_000
  public static let maximumInputDimension = 8_192
  public static let maximumInputPixelCount = 33_554_432

  public let durationMilliseconds: Int
  public let width: Int
  public let height: Int

  public init(durationMilliseconds: Int, width: Int, height: Int) throws {
    guard (1...Self.maximumDurationMilliseconds).contains(durationMilliseconds) else {
      throw AK47LCDVideoImportError.invalidDuration(milliseconds: durationMilliseconds)
    }
    guard width > 0, height > 0 else {
      throw AK47LCDVideoImportError.invalidSourceDimensions(width: width, height: height)
    }
    let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow,
      width <= Self.maximumInputDimension,
      height <= Self.maximumInputDimension,
      pixelCount <= Self.maximumInputPixelCount
    else {
      throw AK47LCDVideoImportError.inputWorkLimitExceeded
    }
    self.durationMilliseconds = durationMilliseconds
    self.width = width
    self.height = height
  }
}

/// A bounded, half-open source interval sampled at an integer frame rate.
public struct AK47LCDVideoSelection: Equatable, Sendable {
  public static let minimumFramesPerSecond = 2
  public static let maximumFramesPerSecond = 60
  public static let recommendedFramesPerSecond = 10
  public static let recommendedDurationMilliseconds = 3_000

  public let startMilliseconds: Int
  public let endMilliseconds: Int
  public let framesPerSecond: Int

  public init(
    startMilliseconds: Int,
    endMilliseconds: Int,
    framesPerSecond: Int
  ) throws {
    guard
      (Self.minimumFramesPerSecond...Self.maximumFramesPerSecond).contains(framesPerSecond)
    else {
      throw AK47LCDVideoImportError.invalidFrameRate(framesPerSecond)
    }
    guard startMilliseconds >= 0, endMilliseconds > startMilliseconds else {
      throw AK47LCDVideoImportError.invalidSelection(
        startMilliseconds: startMilliseconds,
        endMilliseconds: endMilliseconds
      )
    }
    self.startMilliseconds = startMilliseconds
    self.endMilliseconds = endMilliseconds
    self.framesPerSecond = framesPerSecond
  }

  public static func recommended(for metadata: AK47LCDVideoSourceMetadata) throws -> Self {
    try Self(
      startMilliseconds: 0,
      endMilliseconds: min(
        metadata.durationMilliseconds,
        recommendedDurationMilliseconds
      ),
      framesPerSecond: recommendedFramesPerSecond
    )
  }
}

/// One requested video presentation time and its source GIF delay.
public struct AK47LCDVideoSample: Equatable, Sendable {
  public let timestampMilliseconds: Int
  public let delayMilliseconds: Int

  fileprivate init(timestampMilliseconds: Int, delayMilliseconds: Int) {
    self.timestampMilliseconds = timestampMilliseconds
    self.delayMilliseconds = delayMilliseconds
  }
}

/// A deterministic, bounded extraction plan. The extraction dimensions are a
/// maximum AVFoundation output box; the service validates every actual frame.
public struct AK47LCDVideoImportPlan: Equatable, Sendable {
  public let metadata: AK47LCDVideoSourceMetadata
  public let selection: AK47LCDVideoSelection
  public let samples: [AK47LCDVideoSample]
  public let maximumExtractionWidth: Int
  public let maximumExtractionHeight: Int
  public let estimatedDecodedPixelCount: Int

  public var expectedFrameCount: Int { samples.count }

  public init(
    metadata: AK47LCDVideoSourceMetadata,
    selection: AK47LCDVideoSelection
  ) throws {
    guard selection.endMilliseconds <= metadata.durationMilliseconds else {
      throw AK47LCDVideoImportError.selectionExceedsDuration(
        endMilliseconds: selection.endMilliseconds,
        durationMilliseconds: metadata.durationMilliseconds
      )
    }

    let duration = selection.endMilliseconds - selection.startMilliseconds
    let maximumDurationForFrameLimit =
      (AK47LCDFormat.maximumFrameCount * 1_000) / selection.framesPerSecond
    guard duration <= maximumDurationForFrameLimit else {
      let requested = try Self.frameCount(
        durationMilliseconds: duration,
        framesPerSecond: selection.framesPerSecond
      )
      throw AK47LCDVideoImportError.frameLimitExceeded(
        requested: requested,
        maximum: AK47LCDFormat.maximumFrameCount
      )
    }

    let frameCount = try Self.frameCount(
      durationMilliseconds: duration,
      framesPerSecond: selection.framesPerSecond
    )
    guard (1...AK47LCDFormat.maximumFrameCount).contains(frameCount) else {
      throw AK47LCDVideoImportError.frameLimitExceeded(
        requested: frameCount,
        maximum: AK47LCDFormat.maximumFrameCount
      )
    }

    samples = try Self.makeSamples(selection: selection, count: frameCount)
    let extractionSize = try Self.extractionSize(metadata: metadata, frameCount: frameCount)
    maximumExtractionWidth = extractionSize.width
    maximumExtractionHeight = extractionSize.height
    let (pixelsPerFrame, pixelOverflow) = extractionSize.width.multipliedReportingOverflow(
      by: extractionSize.height
    )
    let (totalPixels, totalOverflow) = pixelsPerFrame.multipliedReportingOverflow(by: frameCount)
    guard !pixelOverflow, !totalOverflow,
      pixelsPerFrame <= 2_000_000,
      totalPixels <= AK47LCDFormat.maximumTotalDecodedPixels
    else {
      throw AK47LCDVideoImportError.decodedWorkLimitExceeded
    }
    estimatedDecodedPixelCount = totalPixels
    self.metadata = metadata
    self.selection = selection
  }

  private static func frameCount(
    durationMilliseconds: Int,
    framesPerSecond: Int
  ) throws -> Int {
    let (scaledDuration, multiplyOverflow) = durationMilliseconds.multipliedReportingOverflow(
      by: framesPerSecond
    )
    let (roundedDuration, addOverflow) = scaledDuration.addingReportingOverflow(999)
    guard !multiplyOverflow, !addOverflow else {
      throw AK47LCDVideoImportError.arithmeticOverflow
    }
    return roundedDuration / 1_000
  }

  private static func makeSamples(
    selection: AK47LCDVideoSelection,
    count: Int
  ) throws -> [AK47LCDVideoSample] {
    var timestamps: [Int] = []
    timestamps.reserveCapacity(count)
    for index in 0..<count {
      let (scaledIndex, overflow) = index.multipliedReportingOverflow(by: 1_000)
      guard !overflow else { throw AK47LCDVideoImportError.arithmeticOverflow }
      let offset = scaledIndex / selection.framesPerSecond
      let (timestamp, timestampOverflow) = selection.startMilliseconds.addingReportingOverflow(
        offset
      )
      guard !timestampOverflow, timestamp < selection.endMilliseconds else {
        throw AK47LCDVideoImportError.arithmeticOverflow
      }
      timestamps.append(timestamp)
    }

    return try timestamps.enumerated().map { index, timestamp in
      let nextTimestamp =
        index + 1 < timestamps.count
        ? timestamps[index + 1] : selection.endMilliseconds
      let delay = nextTimestamp - timestamp
      guard (1...511).contains(delay) else {
        throw AK47LCDVideoImportError.decodedWorkLimitExceeded
      }
      return AK47LCDVideoSample(
        timestampMilliseconds: timestamp,
        delayMilliseconds: delay
      )
    }
  }

  private static func extractionSize(
    metadata: AK47LCDVideoSourceMetadata,
    frameCount: Int
  ) throws -> (width: Int, height: Int) {
    let totalBudgetPerFrame = AK47LCDFormat.maximumTotalDecodedPixels / frameCount
    let pixelBudget = min(2_000_000, totalBudgetPerFrame)
    guard pixelBudget > 0 else {
      throw AK47LCDVideoImportError.decodedWorkLimitExceeded
    }

    let width = Double(metadata.width)
    let height = Double(metadata.height)
    let dimensionScale = min(
      1,
      Double(AK47LCDFormat.maximumSourceDimension) / width,
      Double(AK47LCDFormat.maximumSourceDimension) / height
    )
    let areaScale = sqrt(Double(pixelBudget) / (width * height))
    let scale = min(dimensionScale, areaScale)
    guard scale.isFinite, scale > 0 else {
      throw AK47LCDVideoImportError.decodedWorkLimitExceeded
    }

    let extractionWidth = max(1, Int((width * scale).rounded(.down)))
    let extractionHeight = max(1, Int((height * scale).rounded(.down)))
    return (extractionWidth, extractionHeight)
  }
}
