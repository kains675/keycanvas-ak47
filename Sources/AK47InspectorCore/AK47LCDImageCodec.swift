import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AK47LCDImageCodecError: Error, Equatable, LocalizedError {
  case notLocalRegularFile
  case sourceFileTooLarge(maximumBytes: Int)
  case unsupportedImageType
  case invalidGIF
  case sourceWorkLimitExceeded
  case missingFrameDelay(frameIndex: Int)
  case imageDecodeFailed(frameIndex: Int)
  case imageEncodeFailed
  case encodedGIFTooLarge(maximumBytes: Int)

  public var errorDescription: String? {
    switch self {
    case .notLocalRegularFile:
      return "The GIF must be a local, non-symbolic-link regular file."
    case .sourceFileTooLarge(let maximumBytes):
      return "The GIF exceeds the \(maximumBytes)-byte local import limit."
    case .unsupportedImageType:
      return "Only a validated GIF source is accepted by the animation editor."
    case .invalidGIF:
      return "The GIF metadata is invalid or incomplete."
    case .sourceWorkLimitExceeded:
      return "The GIF exceeds the bounded dimension, frame, or decoded-pixel work limit."
    case .missingFrameDelay(let frameIndex):
      return "GIF frame \(frameIndex + 1) has no valid delay and no explicit fallback was supplied."
    case .imageDecodeFailed(let frameIndex):
      return "GIF frame \(frameIndex + 1) could not be fully decoded."
    case .imageEncodeFailed:
      return "The edited animation could not be encoded as GIF."
    case .encodedGIFTooLarge(let maximumBytes):
      return "The edited GIF exceeds the \(maximumBytes)-byte local asset limit."
    }
  }
}

public struct AK47LCDDecodedGIFFrame: Equatable, Sendable {
  public let image: AK47LCDRGBAImage
  public let sourceDelay: AK47LCDSourceDelay

  public init(image: AK47LCDRGBAImage, sourceDelay: AK47LCDSourceDelay) {
    self.image = image
    self.sourceDelay = sourceDelay
  }
}

public struct AK47LCDDecodedGIF: Equatable, Sendable {
  public let sourceWidth: Int
  public let sourceHeight: Int
  public let frames: [AK47LCDDecodedGIFFrame]

  public init(sourceWidth: Int, sourceHeight: Int, frames: [AK47LCDDecodedGIFFrame]) {
    self.sourceWidth = sourceWidth
    self.sourceHeight = sourceHeight
    self.frames = frames
  }

  public func makeProject(
    resizeMode: AK47LCDResizeMode,
    cropRectangle: AK47LCDPixelRect? = nil,
    background: AK47LCDRGBAColor = .black
  ) throws -> AK47LCDAnimationProject {
    let deviceFrames = try frames.map { sourceFrame in
      try AK47LCDAnimationFrame(
        image: sourceFrame.image.renderedForDevice(
          mode: resizeMode,
          cropRectangle: cropRectangle,
          background: background
        ),
        sourceDelay: sourceFrame.sourceDelay
      )
    }
    return try AK47LCDAnimationProject(frames: deviceFrames)
  }
}

public enum AK47LCDGIFDecoder {
  /// Decodes ImageIO's full, composited GIF frames into canonical RGBA8 pixels.
  /// A delay-less still uses source delay zero; an explicit fallback is required
  /// only for malformed/missing delays in a multi-frame GIF.
  public static func decode(
    url: URL,
    fallbackDelayMilliseconds: Int? = nil
  ) throws -> AK47LCDDecodedGIF {
    guard url.isFileURL else { throw AK47LCDImageCodecError.notLocalRegularFile }
    // Open once with O_NOFOLLOW, bound the exact inode size, then decode the
    // immutable snapshot. This prevents a path/symlink swap between validation
    // and ImageIO reopening the source.
    let sourceData = try readBoundedRegularFile(url: url)
    return try decode(
      data: sourceData,
      fallbackDelayMilliseconds: fallbackDelayMilliseconds
    )
  }

  /// Decodes an already captured immutable GIF snapshot. Importers that also
  /// retain the original encoded bytes use this overload so the editor and its
  /// local library copy are guaranteed to describe the exact same file.
  public static func decode(
    data sourceData: Data,
    fallbackDelayMilliseconds: Int? = nil
  ) throws -> AK47LCDDecodedGIF {
    guard !sourceData.isEmpty else { throw AK47LCDImageCodecError.invalidGIF }
    guard sourceData.count <= AK47LCDFormat.maximumCompressedGIFByteCount else {
      throw AK47LCDImageCodecError.sourceFileTooLarge(
        maximumBytes: AK47LCDFormat.maximumCompressedGIFByteCount
      )
    }
    if let fallbackDelayMilliseconds {
      _ = try AK47LCDSourceDelay(milliseconds: fallbackDelayMilliseconds)
    }

    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(sourceData as CFData, options),
      let sourceType = CGImageSourceGetType(source),
      let sourceUTType = UTType(sourceType as String),
      sourceUTType.conforms(to: .gif)
    else {
      throw AK47LCDImageCodecError.unsupportedImageType
    }

    let frameCount = CGImageSourceGetCount(source)
    guard (1...AK47LCDFormat.maximumFrameCount).contains(frameCount),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0, height > 0
    else {
      throw AK47LCDImageCodecError.invalidGIF
    }

    // Inspect every frame before asking ImageIO to allocate a raster. A crafted
    // GIF may advertise a small logical canvas in frame zero and a much larger
    // later frame. The work budget therefore charges the larger of the logical
    // canvas and each frame's own metadata dimensions.
    var frameSizes: [(width: Int, height: Int)] = []
    frameSizes.reserveCapacity(frameCount)
    for index in 0..<frameCount {
      guard
        let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
          as? [CFString: Any],
        let frameWidth = (frameProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let frameHeight = (frameProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
      else {
        throw AK47LCDImageCodecError.invalidGIF
      }
      frameSizes.append((frameWidth, frameHeight))
    }
    try validateDecodedWork(canvasWidth: width, canvasHeight: height, frameSizes: frameSizes)

    var frames: [AK47LCDDecodedGIFFrame] = []
    frames.reserveCapacity(frameCount)
    for index in 0..<frameCount {
      guard
        let cgImage = CGImageSourceCreateImageAtIndex(
          source,
          index,
          [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        )
      else {
        throw AK47LCDImageCodecError.imageDecodeFailed(frameIndex: index)
      }
      // ImageIO returns each GIF index on the logical canvas with prior-frame
      // composition and disposal already applied. Requiring the logical size
      // prevents a partial raster from being mistaken for a full device frame.
      guard cgImage.width == width, cgImage.height == height else {
        throw AK47LCDImageCodecError.imageDecodeFailed(frameIndex: index)
      }
      let image = try canonicalRGBAImage(cgImage, frameIndex: index)
      // A still GIF has no meaningful inter-frame wait. The AK47 Windows path
      // represents its absent delay as source 0, which safely encodes to raw 1.
      let milliseconds =
        frameDelayMilliseconds(source: source, index: index)
        ?? (frameCount == 1 ? 0 : fallbackDelayMilliseconds)
      guard let milliseconds else {
        throw AK47LCDImageCodecError.missingFrameDelay(frameIndex: index)
      }
      let delay = try AK47LCDSourceDelay(milliseconds: milliseconds)
      frames.append(AK47LCDDecodedGIFFrame(image: image, sourceDelay: delay))
    }

    return AK47LCDDecodedGIF(sourceWidth: width, sourceHeight: height, frames: frames)
  }

  package static func validateDecodedWork(
    canvasWidth: Int,
    canvasHeight: Int,
    frameSizes: [(width: Int, height: Int)]
  ) throws {
    let canvasPixels = try validatedPixelCount(width: canvasWidth, height: canvasHeight)
    var totalDecodedWork: Int64 = 0
    for size in frameSizes {
      let framePixels = try validatedPixelCount(width: size.width, height: size.height)
      let chargedPixels = max(canvasPixels, framePixels)
      let (newTotal, overflow) = totalDecodedWork.addingReportingOverflow(chargedPixels)
      guard !overflow, newTotal <= Int64(AK47LCDFormat.maximumTotalDecodedPixels) else {
        throw AK47LCDImageCodecError.sourceWorkLimitExceeded
      }
      totalDecodedWork = newTotal
    }
  }

  private static func validatedPixelCount(width: Int, height: Int) throws -> Int64 {
    guard width > 0, height > 0,
      width <= AK47LCDFormat.maximumSourceDimension,
      height <= AK47LCDFormat.maximumSourceDimension
    else {
      throw AK47LCDImageCodecError.sourceWorkLimitExceeded
    }
    let (pixels, overflow) = Int64(width).multipliedReportingOverflow(by: Int64(height))
    guard !overflow, pixels <= 2_000_000 else {
      throw AK47LCDImageCodecError.sourceWorkLimitExceeded
    }
    return pixels
  }

  private static func readBoundedRegularFile(url: URL) throws -> Data {
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    }
    guard descriptor >= 0 else {
      throw AK47LCDImageCodecError.notLocalRegularFile
    }
    defer { Darwin.close(descriptor) }

    var fileStatus = stat()
    guard Darwin.fstat(descriptor, &fileStatus) == 0,
      (fileStatus.st_mode & S_IFMT) == S_IFREG
    else {
      throw AK47LCDImageCodecError.notLocalRegularFile
    }
    guard fileStatus.st_size > 0 else {
      throw AK47LCDImageCodecError.invalidGIF
    }
    guard fileStatus.st_size <= off_t(AK47LCDFormat.maximumCompressedGIFByteCount) else {
      throw AK47LCDImageCodecError.sourceFileTooLarge(
        maximumBytes: AK47LCDFormat.maximumCompressedGIFByteCount
      )
    }

    let byteCount = Int(fileStatus.st_size)
    var data = Data(count: byteCount)
    var totalRead = 0
    while totalRead < byteCount {
      let result: Int = data.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return -1 }
        return Darwin.read(
          descriptor,
          baseAddress.advanced(by: totalRead),
          byteCount - totalRead
        )
      }
      if result < 0, errno == EINTR { continue }
      guard result > 0 else {
        throw AK47LCDImageCodecError.invalidGIF
      }
      totalRead += result
    }

    // A growing file is rejected too; the snapshot must exactly match the
    // validated size instead of silently decoding an arbitrary prefix.
    var trailingByte: UInt8 = 0
    var trailingRead: Int
    repeat {
      trailingRead = Darwin.read(descriptor, &trailingByte, 1)
    } while trailingRead < 0 && errno == EINTR
    guard trailingRead == 0 else {
      throw AK47LCDImageCodecError.invalidGIF
    }
    return data
  }

  private static func frameDelayMilliseconds(source: CGImageSource, index: Int) -> Int? {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        as? [CFString: Any],
      let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else {
      return nil
    }
    let seconds =
      (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
      ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
    guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
    let milliseconds = Int((seconds * 1_000).rounded())
    return (0...AK47LCDFormat.maximumSourceDelayMilliseconds).contains(milliseconds)
      ? milliseconds : nil
  }

  private static func canonicalRGBAImage(
    _ image: CGImage,
    frameIndex: Int
  ) throws -> AK47LCDRGBAImage {
    let (pixelCount, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
    let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
    guard !pixelOverflow, !byteOverflow else {
      throw AK47LCDAnimationError.arithmeticOverflow
    }
    var pixels = Data(count: byteCount)
    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard
        let context = CGContext(
          data: rawBuffer.baseAddress,
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
    guard didDraw else {
      throw AK47LCDImageCodecError.imageDecodeFailed(frameIndex: frameIndex)
    }
    return try AK47LCDRGBAImage(width: image.width, height: image.height, pixels: pixels)
  }
}

public enum AK47LCDGIFEncoder {
  public static func encode(_ project: AK47LCDAnimationProject) throws -> Data {
    let mutableData = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        mutableData,
        UTType.gif.identifier as CFString,
        project.frames.count,
        nil
      )
    else {
      throw AK47LCDImageCodecError.imageEncodeFailed
    }
    CGImageDestinationSetProperties(
      destination,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    )

    for frame in project.frames {
      guard let image = frame.image.makeCGImage() else {
        throw AK47LCDImageCodecError.imageEncodeFailed
      }
      let seconds = Double(frame.sourceDelay.milliseconds) / 1_000
      let properties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFDelayTime: seconds,
          kCGImagePropertyGIFUnclampedDelayTime: seconds,
        ]
      ]
      CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else {
      throw AK47LCDImageCodecError.imageEncodeFailed
    }
    let data = mutableData as Data
    guard data.count <= AK47LCDFormat.maximumCompressedGIFByteCount else {
      throw AK47LCDImageCodecError.encodedGIFTooLarge(
        maximumBytes: AK47LCDFormat.maximumCompressedGIFByteCount
      )
    }
    return data
  }

  public static func write(
    _ project: AK47LCDAnimationProject,
    to destinationURL: URL
  ) throws {
    guard destinationURL.isFileURL else {
      throw AK47LCDImageCodecError.notLocalRegularFile
    }
    try encode(project).write(to: destinationURL, options: .atomic)
  }
}

extension AK47LCDRGBAImage {
  public func makeCGImage() -> CGImage? {
    guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}
