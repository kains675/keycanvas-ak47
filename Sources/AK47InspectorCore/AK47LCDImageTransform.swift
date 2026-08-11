import Foundation

public enum AK47LCDImageTransformError: Error, Equatable, LocalizedError {
  case nonFiniteOffset(x: Double, y: Double)
  case layoutSourceDimensionsMismatch(
    expectedWidth: Int,
    expectedHeight: Int,
    actualWidth: Int,
    actualHeight: Int
  )

  public var errorDescription: String? {
    switch self {
    case .nonFiniteOffset(let x, let y):
      return "LCD crop offsets must be finite; got x=\(x), y=\(y)."
    case .layoutSourceDimensionsMismatch(
      let expectedWidth,
      let expectedHeight,
      let actualWidth,
      let actualHeight
    ):
      return
        "The LCD crop layout was resolved for \(expectedWidth)x\(expectedHeight), not \(actualWidth)x\(actualHeight)."
    }
  }
}

/// The unit used by an aspect-fill crop adjustment.
public enum AK47LCDAspectFillOffsetUnit: String, Equatable, Sendable {
  /// `-1...1` spans the complete available crop travel on each axis.
  case normalized
  /// Source-image pixels measured from the centered crop position.
  case sourcePixels = "source-pixels"
}

/// A finite, center-relative adjustment for the automatic 16:9 aspect-fill crop.
///
/// Positive X moves the visible viewport toward the source's right edge. Positive
/// Y moves it toward the source's bottom edge. Resolution clamps either form to
/// the source bounds, so UI steppers can safely submit values beyond an edge.
public struct AK47LCDAspectFillTransform: Equatable, Sendable {
  public let offsetUnit: AK47LCDAspectFillOffsetUnit
  public let x: Double
  public let y: Double

  public static let centered = AK47LCDAspectFillTransform(
    validatedUnit: .sourcePixels,
    x: 0,
    y: 0
  )

  private init(validatedUnit: AK47LCDAspectFillOffsetUnit, x: Double, y: Double) {
    offsetUnit = validatedUnit
    self.x = x
    self.y = y
  }

  /// Creates an adjustment where `-1` and `1` select the two crop extremes.
  /// Values outside that interval remain valid and are clamped during layout.
  public static func normalized(x: Double, y: Double) throws -> Self {
    try validated(unit: .normalized, x: x, y: y)
  }

  /// Creates an adjustment in source pixels relative to the centered crop.
  /// Values outside the available crop travel are clamped during layout.
  public static func sourcePixels(x: Double, y: Double) throws -> Self {
    try validated(unit: .sourcePixels, x: x, y: y)
  }

  /// Resolves the exact automatic crop once so it can be reused for every frame.
  public func resolved(sourceWidth: Int, sourceHeight: Int) throws
    -> AK47LCDAspectFillLayout
  {
    guard sourceWidth > 0, sourceHeight > 0 else {
      throw AK47LCDAnimationError.invalidDimensions(width: sourceWidth, height: sourceHeight)
    }

    let sourceWidthValue = Double(sourceWidth)
    let sourceHeightValue = Double(sourceHeight)
    let targetAspect =
      Double(AK47LCDFormat.canvasWidth) / Double(AK47LCDFormat.canvasHeight)
    let sourceAspect = sourceWidthValue / sourceHeightValue

    let viewportWidth: Double
    let viewportHeight: Double
    if sourceAspect > targetAspect {
      viewportWidth = sourceHeightValue * targetAspect
      viewportHeight = sourceHeightValue
    } else {
      viewportWidth = sourceWidthValue
      viewportHeight = sourceWidthValue / targetAspect
    }

    let availableX = max(0, sourceWidthValue - viewportWidth)
    let availableY = max(0, sourceHeightValue - viewportHeight)
    let maximumOffsetX = availableX / 2
    let maximumOffsetY = availableY / 2

    let requestedSourceOffsetX: Double
    let requestedSourceOffsetY: Double
    switch offsetUnit {
    case .normalized:
      requestedSourceOffsetX = clamped(x, minimum: -1, maximum: 1) * maximumOffsetX
      requestedSourceOffsetY = clamped(y, minimum: -1, maximum: 1) * maximumOffsetY
    case .sourcePixels:
      requestedSourceOffsetX = x
      requestedSourceOffsetY = y
    }

    let appliedOffsetX = canonicalZero(
      clamped(requestedSourceOffsetX, minimum: -maximumOffsetX, maximum: maximumOffsetX)
    )
    let appliedOffsetY = canonicalZero(
      clamped(requestedSourceOffsetY, minimum: -maximumOffsetY, maximum: maximumOffsetY)
    )
    let normalizedOffsetX = canonicalZero(
      maximumOffsetX > 0 ? appliedOffsetX / maximumOffsetX : 0
    )
    let normalizedOffsetY = canonicalZero(
      maximumOffsetY > 0 ? appliedOffsetY / maximumOffsetY : 0
    )
    let viewportX = clamped(
      (availableX / 2) + appliedOffsetX,
      minimum: 0,
      maximum: availableX
    )
    let viewportY = clamped(
      (availableY / 2) + appliedOffsetY,
      minimum: 0,
      maximum: availableY
    )

    let offsetWasClamped: Bool
    switch offsetUnit {
    case .normalized:
      offsetWasClamped =
        x != normalizedOffsetX || y != normalizedOffsetY
    case .sourcePixels:
      offsetWasClamped =
        x != appliedOffsetX || y != appliedOffsetY
    }

    return AK47LCDAspectFillLayout(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      viewport: AK47LCDSourceViewport(
        x: viewportX,
        y: viewportY,
        width: viewportWidth,
        height: viewportHeight
      ),
      maximumSourceOffsetX: canonicalZero(maximumOffsetX),
      maximumSourceOffsetY: canonicalZero(maximumOffsetY),
      appliedSourceOffsetX: appliedOffsetX,
      appliedSourceOffsetY: appliedOffsetY,
      normalizedOffsetX: normalizedOffsetX,
      normalizedOffsetY: normalizedOffsetY,
      offsetWasClamped: offsetWasClamped
    )
  }

  private static func validated(
    unit: AK47LCDAspectFillOffsetUnit,
    x: Double,
    y: Double
  ) throws -> Self {
    guard x.isFinite, y.isFinite else {
      throw AK47LCDImageTransformError.nonFiniteOffset(x: x, y: y)
    }
    return Self(validatedUnit: unit, x: canonicalZero(x), y: canonicalZero(y))
  }
}

/// A source-space rectangle sampled into the complete 240x135 LCD output.
public struct AK47LCDSourceViewport: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public var maxX: Double { x + width }
  public var maxY: Double { y + height }
}

/// A validated, reusable aspect-fill layout for live preview and all GIF frames.
public struct AK47LCDAspectFillLayout: Equatable, Sendable {
  public let sourceWidth: Int
  public let sourceHeight: Int
  public let viewport: AK47LCDSourceViewport
  /// Symmetric center-relative X range is `-maximumSourceOffsetX...+maximumSourceOffsetX`.
  public let maximumSourceOffsetX: Double
  /// Symmetric center-relative Y range is `-maximumSourceOffsetY...+maximumSourceOffsetY`.
  public let maximumSourceOffsetY: Double
  public let appliedSourceOffsetX: Double
  public let appliedSourceOffsetY: Double
  public let normalizedOffsetX: Double
  public let normalizedOffsetY: Double
  public let offsetWasClamped: Bool

  /// Whole-source-pixel stepper values that include both exact crop extremes.
  ///
  /// When the exact travel is fractional, the two integer endpoints intentionally
  /// round outward; resolving either endpoint clamps it to the exposed exact
  /// `appliedSourceOffsetX`. This lets arrow controls reach both source edges.
  public var sourcePixelOffsetXRange: ClosedRange<Int> {
    let maximum = Int(maximumSourceOffsetX.rounded(.up))
    return -maximum...maximum
  }

  /// Whole-source-pixel stepper values that include both exact crop extremes.
  /// See `sourcePixelOffsetXRange` for fractional-endpoint behavior.
  public var sourcePixelOffsetYRange: ClosedRange<Int> {
    let maximum = Int(maximumSourceOffsetY.rounded(.up))
    return -maximum...maximum
  }

  fileprivate init(
    sourceWidth: Int,
    sourceHeight: Int,
    viewport: AK47LCDSourceViewport,
    maximumSourceOffsetX: Double,
    maximumSourceOffsetY: Double,
    appliedSourceOffsetX: Double,
    appliedSourceOffsetY: Double,
    normalizedOffsetX: Double,
    normalizedOffsetY: Double,
    offsetWasClamped: Bool
  ) {
    self.sourceWidth = sourceWidth
    self.sourceHeight = sourceHeight
    self.viewport = viewport
    self.maximumSourceOffsetX = maximumSourceOffsetX
    self.maximumSourceOffsetY = maximumSourceOffsetY
    self.appliedSourceOffsetX = appliedSourceOffsetX
    self.appliedSourceOffsetY = appliedSourceOffsetY
    self.normalizedOffsetX = normalizedOffsetX
    self.normalizedOffsetY = normalizedOffsetY
    self.offsetWasClamped = offsetWasClamped
  }
}

extension AK47LCDRGBAImage {
  /// Resolves and renders an automatic 16:9 aspect-fill transform.
  public func renderedForDevice(
    aspectFill transform: AK47LCDAspectFillTransform,
    background: AK47LCDRGBAColor = .black
  ) throws -> AK47LCDRGBAImage {
    let layout = try transform.resolved(sourceWidth: width, sourceHeight: height)
    return try renderedForDevice(aspectFillLayout: layout, background: background)
  }

  /// Renders using a previously resolved layout. Reusing one layout keeps crop
  /// geometry identical while an animated preview walks through its frames.
  public func renderedForDevice(
    aspectFillLayout layout: AK47LCDAspectFillLayout,
    background: AK47LCDRGBAColor = .black
  ) throws -> AK47LCDRGBAImage {
    guard width == layout.sourceWidth, height == layout.sourceHeight else {
      throw AK47LCDImageTransformError.layoutSourceDimensionsMismatch(
        expectedWidth: layout.sourceWidth,
        expectedHeight: layout.sourceHeight,
        actualWidth: width,
        actualHeight: height
      )
    }

    let targetWidth = AK47LCDFormat.canvasWidth
    let targetHeight = AK47LCDFormat.canvasHeight
    let (pixelCount, pixelOverflow) = targetWidth.multipliedReportingOverflow(by: targetHeight)
    let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(
      by: AK47LCDFormat.rgbaBytesPerPixel
    )
    guard !pixelOverflow, !byteOverflow else {
      throw AK47LCDAnimationError.arithmeticOverflow
    }

    var outputPixels = Data(count: byteCount)
    outputPixels.withUnsafeMutableBytes { outputBuffer in
      pixels.withUnsafeBytes { sourceBuffer in
        guard
          let output = outputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else { return }

        for destinationY in 0..<targetHeight {
          let sourceY =
            layout.viewport.y
            + ((Double(destinationY) + 0.5) * layout.viewport.height / Double(targetHeight))
            - 0.5
          for destinationX in 0..<targetWidth {
            let sourceX =
              layout.viewport.x
              + ((Double(destinationX) + 0.5) * layout.viewport.width / Double(targetWidth))
              - 0.5
            let sample = aspectFillBilinearSample(
              source,
              width: width,
              height: height,
              x: sourceX,
              y: sourceY
            )
            let destinationOffset = ((destinationY * targetWidth) + destinationX) * 4
            compositeOpaque(sample, over: background, into: output, at: destinationOffset)
          }
        }
      }
    }
    return try AK47LCDRGBAImage(width: targetWidth, height: targetHeight, pixels: outputPixels)
  }

  private func aspectFillBilinearSample(
    _ source: UnsafePointer<UInt8>,
    width: Int,
    height: Int,
    x: Double,
    y: Double
  ) -> AK47LCDRGBAColor {
    let clampedX = clamped(x, minimum: 0, maximum: Double(width - 1))
    let clampedY = clamped(y, minimum: 0, maximum: Double(height - 1))
    let x0 = Int(clampedX.rounded(.down))
    let y0 = Int(clampedY.rounded(.down))
    let x1 = min(width - 1, x0 + 1)
    let y1 = min(height - 1, y0 + 1)
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

  private func compositeOpaque(
    _ source: AK47LCDRGBAColor,
    over background: AK47LCDRGBAColor,
    into destination: UnsafeMutablePointer<UInt8>,
    at offset: Int
  ) {
    let alpha = Int(source.alpha)
    let inverseAlpha = 255 - alpha
    destination[offset] = UInt8(
      clamping: ((Int(source.red) * alpha) + (Int(background.red) * inverseAlpha) + 127) / 255
    )
    destination[offset + 1] = UInt8(
      clamping: ((Int(source.green) * alpha) + (Int(background.green) * inverseAlpha) + 127) / 255
    )
    destination[offset + 2] = UInt8(
      clamping: ((Int(source.blue) * alpha) + (Int(background.blue) * inverseAlpha) + 127) / 255
    )
    destination[offset + 3] = 255
  }
}

extension AK47LCDDecodedGIF {
  /// Applies one clamped aspect-fill viewport to every decoded frame while
  /// preserving source delays. This is suitable for both live playback and the
  /// final device project, so the preview and exported LCD pixels share a path.
  public func makeProject(
    aspectFill transform: AK47LCDAspectFillTransform,
    background: AK47LCDRGBAColor = .black
  ) throws -> AK47LCDAnimationProject {
    let layout = try transform.resolved(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight
    )
    let deviceFrames = try frames.map { sourceFrame in
      try AK47LCDAnimationFrame(
        image: sourceFrame.image.renderedForDevice(
          aspectFillLayout: layout,
          background: background
        ),
        sourceDelay: sourceFrame.sourceDelay
      )
    }
    return try AK47LCDAnimationProject(frames: deviceFrames)
  }
}

private func clamped(_ value: Double, minimum: Double, maximum: Double) -> Double {
  min(maximum, max(minimum, value))
}

private func canonicalZero(_ value: Double) -> Double {
  value == 0 ? 0 : value
}
