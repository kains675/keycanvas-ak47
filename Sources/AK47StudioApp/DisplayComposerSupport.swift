import AK47InspectorCore
import Foundation

enum LCDQualifiedUploadPreviewError: Error, Equatable {
  case invalidFrameIndex(Int)
  case truncatedContainer
}

/// Decodes the exact little-endian RGB565 bytes in the immutable transfer plan.
/// Visual review must not use the higher-precision editor RGBA source because
/// those are not the pixels submitted to the device.
enum LCDQualifiedUploadPreviewDecoder {
  static func decodeFrame(
    from container: AK47LCDEncodedContainer,
    at frameIndex: Int
  ) throws -> AK47LCDRGBAImage {
    guard (0..<container.frameCount).contains(frameIndex) else {
      throw LCDQualifiedUploadPreviewError.invalidFrameIndex(frameIndex)
    }

    let frameStart =
      AK47LCDFormat.headerByteCount
      + (frameIndex * AK47LCDFormat.rgb565FrameByteCount)
    let frameEnd = frameStart + AK47LCDFormat.rgb565FrameByteCount
    guard frameStart >= AK47LCDFormat.headerByteCount, frameEnd <= container.data.count else {
      throw LCDQualifiedUploadPreviewError.truncatedContainer
    }

    let pixelCount = AK47LCDFormat.canvasWidth * AK47LCDFormat.canvasHeight
    var rgba = Data(count: pixelCount * AK47LCDFormat.rgbaBytesPerPixel)
    container.data.withUnsafeBytes { sourceBuffer in
      rgba.withUnsafeMutableBytes { destinationBuffer in
        guard
          let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let destination = destinationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else { return }

        for pixelIndex in 0..<pixelCount {
          let sourceOffset = frameStart + (pixelIndex * 2)
          let value = UInt16(source[sourceOffset]) | (UInt16(source[sourceOffset + 1]) << 8)
          let red5 = UInt8((value >> 11) & 0x1F)
          let green6 = UInt8((value >> 5) & 0x3F)
          let blue5 = UInt8(value & 0x1F)
          let destinationOffset = pixelIndex * AK47LCDFormat.rgbaBytesPerPixel
          destination[destinationOffset] = (red5 << 3) | (red5 >> 2)
          destination[destinationOffset + 1] = (green6 << 2) | (green6 >> 4)
          destination[destinationOffset + 2] = (blue5 << 3) | (blue5 >> 2)
          destination[destinationOffset + 3] = 0xFF
        }
      }
    }

    return try AK47LCDRGBAImage(
      width: AK47LCDFormat.canvasWidth,
      height: AK47LCDFormat.canvasHeight,
      pixels: rgba
    )
  }
}

struct DisplayAnimationTimeline: Equatable {
  let frameDelaysMilliseconds: [Int]

  init(
    frameCount: Int,
    sourceDelaysMilliseconds: [Int],
    fallbackDelayMilliseconds: Int
  ) {
    let safeFrameCount = max(0, frameCount)
    let safeFallback = min(60_000, max(1, fallbackDelayMilliseconds))
    frameDelaysMilliseconds = (0..<safeFrameCount).map { index in
      guard sourceDelaysMilliseconds.indices.contains(index) else { return safeFallback }
      let delay = sourceDelaysMilliseconds[index]
      return (1...60_000).contains(delay) ? delay : safeFallback
    }
  }

  var frameCount: Int {
    frameDelaysMilliseconds.count
  }

  var totalDurationMilliseconds: Int {
    frameDelaysMilliseconds.reduce(0, +)
  }

  func delayMilliseconds(forFrameAt index: Int) -> Int? {
    guard frameDelaysMilliseconds.indices.contains(index) else { return nil }
    return frameDelaysMilliseconds[index]
  }

  func previewDelayMilliseconds(
    forFrameAt index: Int,
    minimumMilliseconds: Int
  ) -> Int? {
    guard let sourceDelay = delayMilliseconds(forFrameAt: index) else { return nil }
    let safeMinimum = min(60_000, max(1, minimumMilliseconds))
    return max(sourceDelay, safeMinimum)
  }

  func startOffsetMilliseconds(forFrameAt index: Int) -> Int? {
    guard frameDelaysMilliseconds.indices.contains(index) else { return nil }
    return frameDelaysMilliseconds.prefix(index).reduce(0, +)
  }

  func frameIndex(atLoopOffsetMilliseconds offset: Int) -> Int? {
    guard totalDurationMilliseconds > 0 else { return nil }
    let wrappedOffset =
      ((offset % totalDurationMilliseconds) + totalDurationMilliseconds)
      % totalDurationMilliseconds
    var elapsed = 0
    for (index, delay) in frameDelaysMilliseconds.enumerated() {
      elapsed += delay
      if wrappedOffset < elapsed {
        return index
      }
    }
    return frameDelaysMilliseconds.indices.last
  }
}

struct DisplayPreviewWorkLimits: Equatable {
  let maximumDimension: Int64
  let maximumFrameCount: Int64
  let maximumPixelsPerFrame: Int64
  let maximumTotalDecodedPixels: Int64

  static let localImport = DisplayPreviewWorkLimits(
    maximumDimension: 2_048,
    maximumFrameCount: 140,
    maximumPixelsPerFrame: 2_000_000,
    maximumTotalDecodedPixels: 32_000_000
  )

  func permits(width: Int, height: Int, frameCount: Int) -> Bool {
    guard width > 0, height > 0, frameCount > 0 else { return false }
    let width64 = Int64(width)
    let height64 = Int64(height)
    let frameCount64 = Int64(frameCount)
    guard width64 <= maximumDimension,
      height64 <= maximumDimension,
      frameCount64 <= maximumFrameCount
    else {
      return false
    }

    let (pixelsPerFrame, frameOverflow) = width64.multipliedReportingOverflow(by: height64)
    guard !frameOverflow, pixelsPerFrame <= maximumPixelsPerFrame else { return false }
    let (totalPixels, totalOverflow) = pixelsPerFrame.multipliedReportingOverflow(by: frameCount64)
    return !totalOverflow && totalPixels <= maximumTotalDecodedPixels
  }
}

enum DisplayPreviewRuntimeLimits {
  static let minimumPlaybackDelayMilliseconds = 16
  static let thumbnailMaximumPixelSize = 480
  static let maximumCachedFrameCount = 12
  static let maximumCacheByteCost = 8 * 1_024 * 1_024
}

struct DisplayContainerEstimate: Equatable {
  let targetWidth: Int
  let targetHeight: Int
  let referenceFrameCount: Int
  let decodedWidth: Int
  let decodedHeight: Int
  let decodedFrameCount: Int
  let decodedDelayCount: Int
  let encodedContainerByteCount: Int64
  let maximumContainerByteCount: Int64
  let planningPageByteCount: Int64

  var matchesTargetCanvas: Bool {
    decodedWidth == targetWidth && decodedHeight == targetHeight
  }

  var referenceMatchesDecodedFrameCount: Bool {
    referenceFrameCount == decodedFrameCount
  }

  var hasOneDelayPerDecodedFrame: Bool {
    decodedDelayCount == decodedFrameCount
  }

  var isContainerWithinLimit: Bool {
    encodedContainerByteCount > 0 && encodedContainerByteCount <= maximumContainerByteCount
  }

  var planningPageCount: Int64 {
    guard encodedContainerByteCount > 0, planningPageByteCount > 0 else { return 0 }
    return (encodedContainerByteCount + planningPageByteCount - 1) / planningPageByteCount
  }

  var finalPlanningPageByteCount: Int64 {
    guard planningPageCount > 0 else { return 0 }
    return encodedContainerByteCount - ((planningPageCount - 1) * planningPageByteCount)
  }

  var isInternallyConsistent: Bool {
    referenceMatchesDecodedFrameCount && hasOneDelayPerDecodedFrame && isContainerWithinLimit
  }
}

enum DisplayPlaylistEditing {
  static func moving(_ playlist: [String], from sourceIndex: Int, by offset: Int) -> [String] {
    let destinationIndex = sourceIndex + offset
    guard playlist.indices.contains(sourceIndex), playlist.indices.contains(destinationIndex),
      sourceIndex != destinationIndex
    else {
      return playlist
    }

    var result = playlist
    let identifier = result.remove(at: sourceIndex)
    result.insert(identifier, at: destinationIndex)
    return result
  }

  static func removing(_ playlist: [String], at index: Int) -> [String] {
    guard playlist.indices.contains(index) else { return playlist }
    var result = playlist
    result.remove(at: index)
    return result
  }

  static func appending(_ identifier: String, to playlist: [String]) -> [String] {
    guard !identifier.isEmpty, !playlist.contains(identifier) else { return playlist }
    return playlist + [identifier]
  }
}
