import Foundation

/// Conservative, host-side limits for an AK47 LCD animation.
///
/// The vendor layout advertises `gif_maxframes="141"`; the Windows UI accepts
/// indices below that sentinel, so KeyCanvas deliberately caps projects at 140
/// frames. `maximumContainerByteCount` is a software budget derived from that
/// cap, not a claim about the physical end address of the external flash.
public enum AK47LCDFormat {
  public static let canvasWidth = 240
  public static let canvasHeight = 135
  public static let rgbaBytesPerPixel = 4
  public static let rgb565BytesPerPixel = 2
  public static let headerByteCount = 256
  public static let transferPageByteCount = 4_096
  public static let maximumFrameCount = 140
  public static let maximumSourceDelayMilliseconds = 60_000
  public static let maximumCompressedGIFByteCount = 25 * 1_024 * 1_024
  public static let maximumSourceDimension = 2_048
  public static let maximumTotalDecodedPixels = 32_000_000

  public static let rgb565FrameByteCount = canvasWidth * canvasHeight * rgb565BytesPerPixel

  public static let maximumContainerByteCount: Int = {
    let raw = headerByteCount + (rgb565FrameByteCount * maximumFrameCount)
    return ((raw + transferPageByteCount - 1) / transferPageByteCount)
      * transferPageByteCount
  }()
}

public enum AK47LCDAnimationError: Error, Equatable, LocalizedError {
  case invalidDimensions(width: Int, height: Int)
  case invalidPixelByteCount(expected: Int, actual: Int)
  case invalidSourceDelay(milliseconds: Int)
  case invalidDeviceDelay(rawValue: Int)
  case deviceDelaySourceOutOfRange(milliseconds: Int)
  case sourceDelayNotDeviceEncodable(frameIndex: Int, milliseconds: Int)
  case invalidFrameCount(Int)
  case invalidFrameIndex(Int)
  case invalidDestinationIndex(Int)
  case cannotRemoveOnlyFrame
  case frameLimitExceeded(maximum: Int)
  case invalidCropRectangle
  case invalidStroke
  case invalidTextOverlay
  case transparentDeviceFrame(frameIndex: Int)
  case arithmeticOverflow
  case partitionBudgetExceeded(required: Int, budget: Int)
  case invalidPartitionBudget(Int)

  public var errorDescription: String? {
    switch self {
    case .invalidDimensions(let width, let height):
      return "Invalid LCD image dimensions: \(width)×\(height)."
    case .invalidPixelByteCount(let expected, let actual):
      return "Invalid RGBA byte count: expected \(expected), got \(actual)."
    case .invalidSourceDelay(let milliseconds):
      return "Source frame delay must be 0…60000 ms; got \(milliseconds)."
    case .invalidDeviceDelay(let rawValue):
      return "Device delay is an explicit raw byte in the range 1…255; got \(rawValue)."
    case .deviceDelaySourceOutOfRange(let milliseconds):
      return
        "Verified AK47 device-delay encoding accepts 0…511 source milliseconds; got \(milliseconds)."
    case .sourceDelayNotDeviceEncodable(let frameIndex, let milliseconds):
      return
        "Frame \(frameIndex + 1) has a \(milliseconds) ms source delay; the verified device encoding accepts 0…511 ms without byte wrapping."
    case .invalidFrameCount(let count):
      return "LCD projects require 1…140 frames; got \(count)."
    case .invalidFrameIndex(let index):
      return "Invalid frame index \(index)."
    case .invalidDestinationIndex(let index):
      return "Invalid destination frame index \(index)."
    case .cannotRemoveOnlyFrame:
      return "The only frame cannot be removed."
    case .frameLimitExceeded(let maximum):
      return "The LCD project cannot exceed \(maximum) frames."
    case .invalidCropRectangle:
      return "The crop rectangle must be non-empty and inside the source image."
    case .invalidStroke:
      return "The drawing stroke is empty or exceeds the bounded drawing limits."
    case .invalidTextOverlay:
      return "The bitmap text is unsupported or does not fit on the LCD canvas."
    case .transparentDeviceFrame(let frameIndex):
      return "Frame \(frameIndex + 1) is not fully composited to opaque pixels."
    case .arithmeticOverflow:
      return "The requested LCD operation overflowed its checked size calculation."
    case .partitionBudgetExceeded(let required, let budget):
      return "The LCD container needs \(required) bytes but the budget is \(budget) bytes."
    case .invalidPartitionBudget(let budget):
      return "The partition budget must be a positive 4096-byte multiple; got \(budget)."
    }
  }
}

public struct AK47LCDRGBAColor: Equatable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8
  public let alpha: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let black = AK47LCDRGBAColor(red: 0, green: 0, blue: 0)
  public static let white = AK47LCDRGBAColor(red: 255, green: 255, blue: 255)
}

public struct AK47LCDPixelPoint: Equatable, Sendable {
  public let x: Int
  public let y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

public struct AK47LCDPixelRect: Equatable, Sendable {
  public let x: Int
  public let y: Int
  public let width: Int
  public let height: Int

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public enum AK47LCDResizeMode: String, CaseIterable, Equatable, Sendable {
  /// Preserves the whole source and letterboxes with the selected background.
  case aspectFit = "aspect-fit"
  /// Preserves aspect ratio and center-crops overflow.
  case aspectFill = "aspect-fill"
  /// Resizes the selected source rectangle directly to 240×135.
  case stretch
}

/// Canonical top-to-bottom, left-to-right RGBA8 pixels.
public struct AK47LCDRGBAImage: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var pixels: Data

  public init(width: Int, height: Int, pixels: Data) throws {
    guard width > 0, height > 0 else {
      throw AK47LCDAnimationError.invalidDimensions(width: width, height: height)
    }
    let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (expectedBytes, byteOverflow) = pixelCount.multipliedReportingOverflow(
      by: AK47LCDFormat.rgbaBytesPerPixel)
    guard !pixelOverflow, !byteOverflow else {
      throw AK47LCDAnimationError.arithmeticOverflow
    }
    guard pixels.count == expectedBytes else {
      throw AK47LCDAnimationError.invalidPixelByteCount(
        expected: expectedBytes,
        actual: pixels.count
      )
    }
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  public init(width: Int, height: Int, color: AK47LCDRGBAColor) throws {
    guard width > 0, height > 0 else {
      throw AK47LCDAnimationError.invalidDimensions(width: width, height: height)
    }
    let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(
      by: AK47LCDFormat.rgbaBytesPerPixel)
    guard !pixelOverflow, !byteOverflow else {
      throw AK47LCDAnimationError.arithmeticOverflow
    }
    var bytes = Data(count: byteCount)
    bytes.withUnsafeMutableBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      for offset in stride(from: 0, to: byteCount, by: 4) {
        base[offset] = color.red
        base[offset + 1] = color.green
        base[offset + 2] = color.blue
        base[offset + 3] = color.alpha
      }
    }
    self.width = width
    self.height = height
    self.pixels = bytes
  }

  public func color(x: Int, y: Int) -> AK47LCDRGBAColor? {
    guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
    let offset = ((y * width) + x) * AK47LCDFormat.rgbaBytesPerPixel
    return pixels.withUnsafeBytes { rawBuffer in
      let base = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
      return AK47LCDRGBAColor(
        red: base[offset],
        green: base[offset + 1],
        blue: base[offset + 2],
        alpha: base[offset + 3]
      )
    }
  }

  public var isOpaque: Bool {
    pixels.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return false
      }
      for offset in stride(from: 3, to: rawBuffer.count, by: 4) where base[offset] != 255 {
        return false
      }
      return true
    }
  }

  /// Crops, resizes, and composites onto an opaque 240×135 canvas.
  public func renderedForDevice(
    mode: AK47LCDResizeMode,
    cropRectangle: AK47LCDPixelRect? = nil,
    background: AK47LCDRGBAColor = .black
  ) throws -> AK47LCDRGBAImage {
    let crop = cropRectangle ?? AK47LCDPixelRect(x: 0, y: 0, width: width, height: height)
    guard crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
      crop.x <= width - crop.width,
      crop.y <= height - crop.height
    else {
      throw AK47LCDAnimationError.invalidCropRectangle
    }

    let targetWidth = AK47LCDFormat.canvasWidth
    let targetHeight = AK47LCDFormat.canvasHeight
    let scaleX = Double(targetWidth) / Double(crop.width)
    let scaleY = Double(targetHeight) / Double(crop.height)
    let scale: Double
    let destinationWidth: Int
    let destinationHeight: Int
    switch mode {
    case .aspectFit:
      scale = min(scaleX, scaleY)
      destinationWidth = max(1, Int((Double(crop.width) * scale).rounded()))
      destinationHeight = max(1, Int((Double(crop.height) * scale).rounded()))
    case .aspectFill:
      scale = max(scaleX, scaleY)
      destinationWidth = max(1, Int((Double(crop.width) * scale).rounded()))
      destinationHeight = max(1, Int((Double(crop.height) * scale).rounded()))
    case .stretch:
      scale = 1
      destinationWidth = targetWidth
      destinationHeight = targetHeight
    }

    var output = try AK47LCDRGBAImage(
      width: targetWidth,
      height: targetHeight,
      color: AK47LCDRGBAColor(
        red: background.red,
        green: background.green,
        blue: background.blue,
        alpha: 255
      )
    )
    let originX = (targetWidth - destinationWidth) / 2
    let originY = (targetHeight - destinationHeight) / 2

    output.pixels.withUnsafeMutableBytes { destinationBuffer in
      pixels.withUnsafeBytes { sourceBuffer in
        guard
          let destination = destinationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else { return }

        let clippedStartX = max(0, originX)
        let clippedStartY = max(0, originY)
        let clippedEndX = min(targetWidth, originX + destinationWidth)
        let clippedEndY = min(targetHeight, originY + destinationHeight)
        guard clippedStartX < clippedEndX, clippedStartY < clippedEndY else { return }

        for destinationY in clippedStartY..<clippedEndY {
          for destinationX in clippedStartX..<clippedEndX {
            let localX = destinationX - originX
            let localY = destinationY - originY
            let sourceX: Double
            let sourceY: Double
            if mode == .stretch {
              sourceX = Double(crop.x) + (Double(localX) + 0.5) / scaleX - 0.5
              sourceY = Double(crop.y) + (Double(localY) + 0.5) / scaleY - 0.5
            } else {
              sourceX = Double(crop.x) + (Double(localX) + 0.5) / scale - 0.5
              sourceY = Double(crop.y) + (Double(localY) + 0.5) / scale - 0.5
            }
            let sampled = Self.bilinearSample(
              source,
              width: width,
              height: height,
              x: sourceX,
              y: sourceY,
              crop: crop
            )
            let destinationOffset = ((destinationY * targetWidth) + destinationX) * 4
            Self.composite(
              sampled,
              over: destination,
              destinationOffset: destinationOffset
            )
          }
        }
      }
    }
    return output
  }

  public mutating func drawStroke(
    points: [AK47LCDPixelPoint],
    radius: Int,
    color: AK47LCDRGBAColor
  ) throws {
    guard !points.isEmpty, points.count <= 4_096, (1...16).contains(radius),
      points.allSatisfy({ (0..<width).contains($0.x) && (0..<height).contains($0.y) })
    else {
      throw AK47LCDAnimationError.invalidStroke
    }

    var samples: [AK47LCDPixelPoint] = []
    samples.reserveCapacity(points.count)
    if let first = points.first {
      samples.append(first)
    }
    for pairIndex in 1..<points.count {
      samples.append(
        contentsOf: Self.linePoints(from: points[pairIndex - 1], to: points[pairIndex]))
      guard samples.count <= 65_536 else {
        throw AK47LCDAnimationError.invalidStroke
      }
    }

    pixels.withUnsafeMutableBytes { rawBuffer in
      guard let destination = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }
      let squaredRadius = radius * radius
      for sample in samples {
        let minY = max(0, sample.y - radius)
        let maxY = min(height - 1, sample.y + radius)
        let minX = max(0, sample.x - radius)
        let maxX = min(width - 1, sample.x + radius)
        for y in minY...maxY {
          for x in minX...maxX {
            let dx = x - sample.x
            let dy = y - sample.y
            guard (dx * dx) + (dy * dy) <= squaredRadius else { continue }
            Self.composite(
              color,
              over: destination,
              destinationOffset: ((y * width) + x) * 4
            )
          }
        }
      }
    }
  }

  /// Draws deliberately limited 5×7 uppercase bitmap text without loading fonts.
  public mutating func drawBitmapText(
    _ text: String,
    origin: AK47LCDPixelPoint,
    scale: Int,
    color: AK47LCDRGBAColor
  ) throws {
    let characters = Array(text.uppercased())
    guard !characters.isEmpty, characters.count <= 32, (1...6).contains(scale),
      origin.x >= 0, origin.y >= 0,
      let glyphRows = try? characters.map({ try Self.bitmapGlyph(for: $0) })
    else {
      throw AK47LCDAnimationError.invalidTextOverlay
    }
    let glyphWidth = 5 * scale
    let spacing = scale
    let textWidth = (characters.count * glyphWidth) + ((characters.count - 1) * spacing)
    let textHeight = 7 * scale
    guard origin.x <= width - textWidth, origin.y <= height - textHeight else {
      throw AK47LCDAnimationError.invalidTextOverlay
    }

    pixels.withUnsafeMutableBytes { rawBuffer in
      guard let destination = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }
      for (characterIndex, rows) in glyphRows.enumerated() {
        let glyphOriginX = origin.x + characterIndex * (glyphWidth + spacing)
        for (rowIndex, rowBits) in rows.enumerated() {
          for column in 0..<5 where rowBits & (1 << (4 - column)) != 0 {
            for subY in 0..<scale {
              for subX in 0..<scale {
                let x = glyphOriginX + (column * scale) + subX
                let y = origin.y + (rowIndex * scale) + subY
                Self.composite(
                  color,
                  over: destination,
                  destinationOffset: ((y * width) + x) * 4
                )
              }
            }
          }
        }
      }
    }
  }

  private static func bilinearSample(
    _ source: UnsafePointer<UInt8>,
    width: Int,
    height: Int,
    x: Double,
    y: Double,
    crop: AK47LCDPixelRect
  ) -> AK47LCDRGBAColor {
    let minimumX = crop.x
    let maximumX = crop.x + crop.width - 1
    let minimumY = crop.y
    let maximumY = crop.y + crop.height - 1
    let clampedX = min(Double(maximumX), max(Double(minimumX), x))
    let clampedY = min(Double(maximumY), max(Double(minimumY), y))
    let x0 = Int(clampedX.rounded(.down))
    let y0 = Int(clampedY.rounded(.down))
    let x1 = min(maximumX, x0 + 1)
    let y1 = min(maximumY, y0 + 1)
    let fractionX = clampedX - Double(x0)
    let fractionY = clampedY - Double(y0)

    func channel(_ channel: Int) -> UInt8 {
      func value(_ sampleX: Int, _ sampleY: Int) -> Double {
        Double(source[((sampleY * width) + sampleX) * 4 + channel])
      }
      let top = value(x0, y0) + ((value(x1, y0) - value(x0, y0)) * fractionX)
      let bottom = value(x0, y1) + ((value(x1, y1) - value(x0, y1)) * fractionX)
      return UInt8(clamping: Int((top + ((bottom - top) * fractionY)).rounded()))
    }

    return AK47LCDRGBAColor(
      red: channel(0),
      green: channel(1),
      blue: channel(2),
      alpha: channel(3)
    )
  }

  private static func composite(
    _ source: AK47LCDRGBAColor,
    over destination: UnsafeMutablePointer<UInt8>,
    destinationOffset: Int
  ) {
    let alpha = Int(source.alpha)
    let inverseAlpha = 255 - alpha
    destination[destinationOffset] = UInt8(
      clamping: ((Int(source.red) * alpha) + (Int(destination[destinationOffset]) * inverseAlpha)
        + 127) / 255
    )
    destination[destinationOffset + 1] = UInt8(
      clamping: ((Int(source.green) * alpha)
        + (Int(destination[destinationOffset + 1]) * inverseAlpha) + 127) / 255
    )
    destination[destinationOffset + 2] = UInt8(
      clamping: ((Int(source.blue) * alpha)
        + (Int(destination[destinationOffset + 2]) * inverseAlpha) + 127) / 255
    )
    destination[destinationOffset + 3] = 255
  }

  private static func linePoints(
    from start: AK47LCDPixelPoint,
    to end: AK47LCDPixelPoint
  ) -> [AK47LCDPixelPoint] {
    var result: [AK47LCDPixelPoint] = []
    var x = start.x
    var y = start.y
    let dx = abs(end.x - start.x)
    let stepX = start.x < end.x ? 1 : -1
    let dy = -abs(end.y - start.y)
    let stepY = start.y < end.y ? 1 : -1
    var error = dx + dy
    while true {
      result.append(AK47LCDPixelPoint(x: x, y: y))
      if x == end.x, y == end.y { break }
      let doubledError = 2 * error
      if doubledError >= dy {
        error += dy
        x += stepX
      }
      if doubledError <= dx {
        error += dx
        y += stepY
      }
    }
    return result
  }

  private static func bitmapGlyph(for character: Character) throws -> [UInt8] {
    guard let rows = bitmapGlyphs[character] else {
      throw AK47LCDAnimationError.invalidTextOverlay
    }
    return rows
  }

  // Each row stores five pixels in its low five bits. This intentionally small
  // alphabet bounds rendering work and keeps authored text deterministic.
  private static let bitmapGlyphs: [Character: [UInt8]] = [
    " ": [0, 0, 0, 0, 0, 0, 0],
    "A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30],
    "C": [14, 17, 16, 16, 16, 17, 14], "D": [30, 17, 17, 17, 17, 17, 30],
    "E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
    "G": [14, 17, 16, 23, 17, 17, 15], "H": [17, 17, 17, 31, 17, 17, 17],
    "I": [31, 4, 4, 4, 4, 4, 31], "J": [7, 2, 2, 2, 18, 18, 12],
    "K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31],
    "M": [17, 27, 21, 21, 17, 17, 17], "N": [17, 25, 21, 19, 17, 17, 17],
    "O": [14, 17, 17, 17, 17, 17, 14], "P": [30, 17, 17, 30, 16, 16, 16],
    "Q": [14, 17, 17, 17, 21, 18, 13], "R": [30, 17, 17, 30, 20, 18, 17],
    "S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4],
    "U": [17, 17, 17, 17, 17, 17, 14], "V": [17, 17, 17, 17, 17, 10, 4],
    "W": [17, 17, 17, 21, 21, 21, 10], "X": [17, 17, 10, 4, 10, 17, 17],
    "Y": [17, 17, 10, 4, 4, 4, 4], "Z": [31, 1, 2, 4, 8, 16, 31],
    "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14],
    "2": [14, 17, 1, 2, 4, 8, 31], "3": [30, 1, 1, 14, 1, 1, 30],
    "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 16, 30, 1, 1, 30],
    "6": [14, 16, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8],
    "8": [14, 17, 17, 14, 17, 17, 14], "9": [14, 17, 17, 15, 1, 1, 14],
    "-": [0, 0, 0, 31, 0, 0, 0], "_": [0, 0, 0, 0, 0, 0, 31],
    ".": [0, 0, 0, 0, 0, 12, 12], ":": [0, 12, 12, 0, 12, 12, 0],
    "!": [4, 4, 4, 4, 4, 0, 4], "?": [14, 17, 1, 2, 4, 0, 4],
    "%": [25, 25, 2, 4, 8, 19, 19],
  ]
}

public struct AK47LCDSourceDelay: Equatable, Sendable {
  public let milliseconds: Int

  public init(milliseconds: Int) throws {
    guard (0...AK47LCDFormat.maximumSourceDelayMilliseconds).contains(milliseconds) else {
      throw AK47LCDAnimationError.invalidSourceDelay(milliseconds: milliseconds)
    }
    self.milliseconds = milliseconds
  }
}

/// The literal LCD header byte, kept separate from the source GIF delay.
///
/// Direct analysis of the AK47 Windows uploader confirms truncating integer
/// division by two, then promotes quotients 0 and 1 to raw value 1. Odd source
/// milliseconds therefore lose one millisecond. The device scheduler
/// additionally promotes encoded values 1…15 to 25.
public struct AK47LCDDeviceDelay: Equatable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: Int) throws {
    guard (1...255).contains(rawValue) else {
      throw AK47LCDAnimationError.invalidDeviceDelay(rawValue: rawValue)
    }
    self.rawValue = UInt8(rawValue)
  }

  public init(verifiedSourceDelay sourceDelay: AK47LCDSourceDelay) throws {
    guard (0...511).contains(sourceDelay.milliseconds) else {
      throw AK47LCDAnimationError.deviceDelaySourceOutOfRange(
        milliseconds: sourceDelay.milliseconds)
    }
    try self.init(rawValue: max(1, sourceDelay.milliseconds / 2))
  }

  /// Nominal duration represented by the header byte before firmware scheduling.
  public var nominalMilliseconds: Int {
    Int(rawValue) * 2
  }

  /// The firmware promotes raw values 1…15 to 25 before scheduling a frame.
  public var firmwareSchedulerRawValue: UInt8 {
    rawValue <= 15 ? 25 : rawValue
  }

  public var effectiveFirmwareMilliseconds: Int {
    Int(firmwareSchedulerRawValue) * 2
  }

  public var usesFirmwareMinimum: Bool {
    rawValue <= 15
  }
}

public struct AK47LCDAnimationFrame: Equatable, Sendable, Identifiable {
  public let id: UUID
  public var image: AK47LCDRGBAImage
  public var sourceDelay: AK47LCDSourceDelay

  public init(
    id: UUID = UUID(),
    image: AK47LCDRGBAImage,
    sourceDelay: AK47LCDSourceDelay
  ) throws {
    guard image.width == AK47LCDFormat.canvasWidth,
      image.height == AK47LCDFormat.canvasHeight
    else {
      throw AK47LCDAnimationError.invalidDimensions(width: image.width, height: image.height)
    }
    self.id = id
    self.image = image
    self.sourceDelay = sourceDelay
  }
}

public struct AK47LCDAnimationProject: Equatable, Sendable {
  public private(set) var frames: [AK47LCDAnimationFrame]

  public init(frames: [AK47LCDAnimationFrame]) throws {
    guard (1...AK47LCDFormat.maximumFrameCount).contains(frames.count) else {
      throw AK47LCDAnimationError.invalidFrameCount(frames.count)
    }
    self.frames = frames
  }

  public var sourceDurationMilliseconds: Int {
    frames.reduce(0) { $0 + $1.sourceDelay.milliseconds }
  }

  public mutating func append(_ frame: AK47LCDAnimationFrame) throws {
    guard frames.count < AK47LCDFormat.maximumFrameCount else {
      throw AK47LCDAnimationError.frameLimitExceeded(maximum: AK47LCDFormat.maximumFrameCount)
    }
    frames.append(frame)
  }

  public mutating func append(contentsOf newFrames: [AK47LCDAnimationFrame]) throws {
    let (newCount, overflow) = frames.count.addingReportingOverflow(newFrames.count)
    guard !overflow else { throw AK47LCDAnimationError.arithmeticOverflow }
    guard newCount <= AK47LCDFormat.maximumFrameCount else {
      throw AK47LCDAnimationError.frameLimitExceeded(maximum: AK47LCDFormat.maximumFrameCount)
    }
    frames.append(contentsOf: newFrames)
  }

  @discardableResult
  public mutating func removeFrame(at index: Int) throws -> AK47LCDAnimationFrame {
    guard frames.indices.contains(index) else {
      throw AK47LCDAnimationError.invalidFrameIndex(index)
    }
    guard frames.count > 1 else {
      throw AK47LCDAnimationError.cannotRemoveOnlyFrame
    }
    return frames.remove(at: index)
  }

  public mutating func duplicateFrame(at index: Int, newIdentifier: UUID = UUID()) throws {
    guard frames.indices.contains(index) else {
      throw AK47LCDAnimationError.invalidFrameIndex(index)
    }
    guard frames.count < AK47LCDFormat.maximumFrameCount else {
      throw AK47LCDAnimationError.frameLimitExceeded(maximum: AK47LCDFormat.maximumFrameCount)
    }
    var duplicate = frames[index]
    duplicate = try AK47LCDAnimationFrame(
      id: newIdentifier,
      image: duplicate.image,
      sourceDelay: duplicate.sourceDelay
    )
    frames.insert(duplicate, at: index + 1)
  }

  public mutating func moveFrame(from sourceIndex: Int, to destinationIndex: Int) throws {
    guard frames.indices.contains(sourceIndex) else {
      throw AK47LCDAnimationError.invalidFrameIndex(sourceIndex)
    }
    guard frames.indices.contains(destinationIndex) else {
      throw AK47LCDAnimationError.invalidDestinationIndex(destinationIndex)
    }
    guard sourceIndex != destinationIndex else { return }
    let frame = frames.remove(at: sourceIndex)
    frames.insert(frame, at: destinationIndex)
  }

  public mutating func setSourceDelay(milliseconds: Int, at index: Int) throws {
    guard frames.indices.contains(index) else {
      throw AK47LCDAnimationError.invalidFrameIndex(index)
    }
    frames[index].sourceDelay = try AK47LCDSourceDelay(milliseconds: milliseconds)
  }

  public mutating func drawStroke(
    at index: Int,
    points: [AK47LCDPixelPoint],
    radius: Int,
    color: AK47LCDRGBAColor
  ) throws {
    guard frames.indices.contains(index) else {
      throw AK47LCDAnimationError.invalidFrameIndex(index)
    }
    try frames[index].image.drawStroke(points: points, radius: radius, color: color)
  }

  public mutating func drawBitmapText(
    at index: Int,
    text: String,
    origin: AK47LCDPixelPoint,
    scale: Int,
    color: AK47LCDRGBAColor
  ) throws {
    guard frames.indices.contains(index) else {
      throw AK47LCDAnimationError.invalidFrameIndex(index)
    }
    try frames[index].image.drawBitmapText(text, origin: origin, scale: scale, color: color)
  }
}
