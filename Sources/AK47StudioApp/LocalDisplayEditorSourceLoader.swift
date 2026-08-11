import AK47InspectorCore
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LocalDisplayEditorSourceError: Error, Equatable, LocalizedError {
  case notLocalRegularFile
  case sourceFileTooLarge(maximumBytes: Int)
  case unsupportedImageType
  case sourceWorkLimitExceeded
  case imageDecodeFailed

  var errorDescription: String? {
    switch self {
    case .notLocalRegularFile:
      return "Choose a local regular PNG, JPEG, or GIF file."
    case .sourceFileTooLarge(let maximumBytes):
      return "The local image exceeds the bounded \(maximumBytes)-byte editor import limit."
    case .unsupportedImageType:
      return "The selected local file is not a supported PNG, JPEG, or GIF image."
    case .sourceWorkLimitExceeded:
      return "The local image exceeds the bounded editor dimension or decoded-pixel limit."
    case .imageDecodeFailed:
      return "The local image could not be decoded into the editor's opaque RGBA format."
    }
  }
}

struct LocalDisplayEditorSource: Equatable, Sendable {
  let decodedSource: AK47LCDDecodedGIF
  let preferredFilenameExtension: String
  /// Exact encoded bytes opened once with O_NOFOLLOW and decoded above.
  /// DisplayComposer stores this snapshot instead of reopening the user path.
  let sourceData: Data
}

enum LocalDisplayEditorSourceLoader {
  static func load(
    url: URL,
    fallbackDelayMilliseconds: Int
  ) throws -> AK47LCDDecodedGIF {
    try inspect(
      url: url,
      fallbackDelayMilliseconds: fallbackDelayMilliseconds
    ).decodedSource
  }

  static func inspect(
    url: URL,
    fallbackDelayMilliseconds: Int
  ) throws -> LocalDisplayEditorSource {
    let data = try readBoundedLocalFile(url: url)
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let typeIdentifier = CGImageSourceGetType(source),
      let contentType = UTType(typeIdentifier as String)
    else {
      throw LocalDisplayEditorSourceError.unsupportedImageType
    }

    if contentType.conforms(to: .gif) {
      return LocalDisplayEditorSource(
        decodedSource: try AK47LCDGIFDecoder.decode(
          data: data,
          fallbackDelayMilliseconds: fallbackDelayMilliseconds
        ),
        preferredFilenameExtension: "gif",
        sourceData: data
      )
    }
    guard contentType.conforms(to: .png) || contentType.conforms(to: .jpeg),
      CGImageSourceGetCount(source) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0,
      height > 0
    else {
      throw LocalDisplayEditorSourceError.unsupportedImageType
    }
    let (sourcePixelCount, sourceOverflow) = width.multipliedReportingOverflow(by: height)
    guard !sourceOverflow,
      width <= AK47LCDVideoSourceMetadata.maximumInputDimension,
      height <= AK47LCDVideoSourceMetadata.maximumInputDimension,
      sourcePixelCount <= AK47LCDVideoSourceMetadata.maximumInputPixelCount
    else {
      throw LocalDisplayEditorSourceError.sourceWorkLimitExceeded
    }
    let dimensionScale = min(
      1,
      Double(AK47LCDFormat.maximumSourceDimension) / Double(max(width, height))
    )
    let areaScale = sqrt(2_000_000 / Double(sourcePixelCount))
    let thumbnailScale = min(dimensionScale, areaScale)
    guard thumbnailScale.isFinite, thumbnailScale > 0 else {
      throw LocalDisplayEditorSourceError.sourceWorkLimitExceeded
    }
    let thumbnailMaximumPixelSize = max(
      1,
      Int((Double(max(width, height)) * thumbnailScale).rounded(.down))
    )
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        thumbnailOptions as CFDictionary
      )
    else {
      throw LocalDisplayEditorSourceError.imageDecodeFailed
    }
    let (pixelCount, overflow) = image.width.multipliedReportingOverflow(by: image.height)
    guard !overflow,
      image.width <= AK47LCDFormat.maximumSourceDimension,
      image.height <= AK47LCDFormat.maximumSourceDimension,
      pixelCount <= 2_000_000
    else {
      throw LocalDisplayEditorSourceError.sourceWorkLimitExceeded
    }
    guard let rgbaImage = makeOpaqueRGBAImage(image) else {
      throw LocalDisplayEditorSourceError.imageDecodeFailed
    }
    return LocalDisplayEditorSource(
      decodedSource: AK47LCDDecodedGIF(
        sourceWidth: image.width,
        sourceHeight: image.height,
        frames: [
          AK47LCDDecodedGIFFrame(
            image: rgbaImage,
            sourceDelay: try AK47LCDSourceDelay(milliseconds: 0)
          )
        ]
      ),
      preferredFilenameExtension: contentType.conforms(to: .png) ? "png" : "jpg",
      sourceData: data
    )
  }

  private static func readBoundedLocalFile(url: URL) throws -> Data {
    guard url.isFileURL else { throw LocalDisplayEditorSourceError.notLocalRegularFile }
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    }
    guard descriptor >= 0 else { throw LocalDisplayEditorSourceError.notLocalRegularFile }
    defer { Darwin.close(descriptor) }

    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_size > 0
    else {
      throw LocalDisplayEditorSourceError.notLocalRegularFile
    }
    guard status.st_size <= off_t(AK47LCDFormat.maximumCompressedGIFByteCount) else {
      throw LocalDisplayEditorSourceError.sourceFileTooLarge(
        maximumBytes: AK47LCDFormat.maximumCompressedGIFByteCount
      )
    }

    let byteCount = Int(status.st_size)
    var data = Data(count: byteCount)
    var totalRead = 0
    while totalRead < byteCount {
      if Task.isCancelled { throw CancellationError() }
      let result: Int = data.withUnsafeMutableBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return -1 }
        return Darwin.read(
          descriptor,
          baseAddress.advanced(by: totalRead),
          byteCount - totalRead
        )
      }
      if result < 0, errno == EINTR { continue }
      guard result > 0 else { throw LocalDisplayEditorSourceError.imageDecodeFailed }
      totalRead += result
    }
    var trailingByte: UInt8 = 0
    var trailingRead: Int
    repeat {
      trailingRead = Darwin.read(descriptor, &trailingByte, 1)
    } while trailingRead < 0 && errno == EINTR
    guard trailingRead == 0 else { throw LocalDisplayEditorSourceError.imageDecodeFailed }
    return data
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
