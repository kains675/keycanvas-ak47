import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47LCDImageTransformTests: XCTestCase {
  func testCenteredLayoutProducesExactSixteenByNineViewport() throws {
    let wide = try AK47LCDAspectFillTransform.centered.resolved(
      sourceWidth: 400,
      sourceHeight: 200
    )
    XCTAssertEqual(wide.viewport.x, 200.0 / 9.0, accuracy: 0.000_001)
    XCTAssertEqual(wide.viewport.y, 0, accuracy: 0.000_001)
    XCTAssertEqual(wide.viewport.width, 3_200.0 / 9.0, accuracy: 0.000_001)
    XCTAssertEqual(wide.viewport.height, 200, accuracy: 0.000_001)
    XCTAssertEqual(wide.viewport.width / wide.viewport.height, 16.0 / 9.0, accuracy: 0.000_001)
    XCTAssertEqual(wide.maximumSourceOffsetX, 200.0 / 9.0, accuracy: 0.000_001)
    XCTAssertEqual(wide.maximumSourceOffsetY, 0)
    XCTAssertEqual(wide.sourcePixelOffsetXRange, -23...23)
    XCTAssertEqual(wide.sourcePixelOffsetYRange, 0...0)

    let tall = try AK47LCDAspectFillTransform.centered.resolved(
      sourceWidth: 200,
      sourceHeight: 400
    )
    XCTAssertEqual(tall.viewport.x, 0, accuracy: 0.000_001)
    XCTAssertEqual(tall.viewport.y, 143.75, accuracy: 0.000_001)
    XCTAssertEqual(tall.viewport.width, 200, accuracy: 0.000_001)
    XCTAssertEqual(tall.viewport.height, 112.5, accuracy: 0.000_001)
    XCTAssertEqual(tall.maximumSourceOffsetX, 0)
    XCTAssertEqual(tall.maximumSourceOffsetY, 143.75, accuracy: 0.000_001)
    XCTAssertEqual(tall.sourcePixelOffsetXRange, 0...0)
    XCTAssertEqual(tall.sourcePixelOffsetYRange, -144...144)

    let exact = try AK47LCDAspectFillTransform.centered.resolved(
      sourceWidth: 240,
      sourceHeight: 135
    )
    XCTAssertEqual(exact.viewport, AK47LCDSourceViewport(x: 0, y: 0, width: 240, height: 135))
    XCTAssertEqual(exact.sourcePixelOffsetXRange, 0...0)
    XCTAssertEqual(exact.sourcePixelOffsetYRange, 0...0)
  }

  func testNormalizedAndSourcePixelOffsetsClampToAvailableTravel() throws {
    let normalized = try AK47LCDAspectFillTransform.normalized(x: 4, y: -3)
      .resolved(sourceWidth: 200, sourceHeight: 400)
    XCTAssertEqual(normalized.appliedSourceOffsetX, 0)
    XCTAssertEqual(normalized.appliedSourceOffsetY, -143.75, accuracy: 0.000_001)
    XCTAssertEqual(normalized.normalizedOffsetX, 0)
    XCTAssertEqual(normalized.normalizedOffsetY, -1)
    XCTAssertEqual(normalized.viewport.y, 0, accuracy: 0.000_001)
    XCTAssertTrue(normalized.offsetWasClamped)

    let sourcePixels = try AK47LCDAspectFillTransform.sourcePixels(x: 1_000, y: 25)
      .resolved(sourceWidth: 400, sourceHeight: 200)
    XCTAssertEqual(sourcePixels.appliedSourceOffsetX, 200.0 / 9.0, accuracy: 0.000_001)
    XCTAssertEqual(sourcePixels.appliedSourceOffsetY, 0)
    XCTAssertEqual(sourcePixels.normalizedOffsetX, 1)
    XCTAssertEqual(sourcePixels.normalizedOffsetY, 0)
    XCTAssertEqual(sourcePixels.viewport.maxX, 400, accuracy: 0.000_001)
    XCTAssertEqual(sourcePixels.viewport.maxY, 200, accuracy: 0.000_001)
    XCTAssertTrue(sourcePixels.offsetWasClamped)

    let endpointInput = Double(sourcePixels.sourcePixelOffsetXRange.upperBound)
    let exactEndpoint = try AK47LCDAspectFillTransform.sourcePixels(x: endpointInput, y: 0)
      .resolved(sourceWidth: 400, sourceHeight: 200)
    XCTAssertEqual(
      exactEndpoint.appliedSourceOffsetX,
      exactEndpoint.maximumSourceOffsetX,
      accuracy: 0.000_001
    )
    XCTAssertEqual(exactEndpoint.viewport.maxX, 400, accuracy: 0.000_001)

    let inRange = try AK47LCDAspectFillTransform.sourcePixels(x: -10, y: 0)
      .resolved(sourceWidth: 400, sourceHeight: 200)
    XCTAssertEqual(inRange.appliedSourceOffsetX, -10)
    XCTAssertFalse(inRange.offsetWasClamped)
  }

  func testTransformRejectsNonFiniteOffsetsAndInvalidDimensions() throws {
    XCTAssertThrowsError(
      try AK47LCDAspectFillTransform.sourcePixels(x: .nan, y: 0)
    ) { error in
      guard case .nonFiniteOffset(let x, let y) = error as? AK47LCDImageTransformError else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertTrue(x.isNaN)
      XCTAssertEqual(y, 0)
    }
    XCTAssertThrowsError(
      try AK47LCDAspectFillTransform.normalized(x: 0, y: .infinity)
    ) { error in
      guard case .nonFiniteOffset(let x, let y) = error as? AK47LCDImageTransformError else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(x, 0)
      XCTAssertEqual(y, .infinity)
    }
    XCTAssertThrowsError(
      try AK47LCDAspectFillTransform.centered.resolved(sourceWidth: 0, sourceHeight: 10)
    ) { error in
      XCTAssertEqual(
        error as? AK47LCDAnimationError,
        .invalidDimensions(width: 0, height: 10)
      )
    }
  }

  func testHorizontalViewportNudgeChangesTheRenderedLCDContent() throws {
    let red = AK47LCDRGBAColor(red: 255, green: 0, blue: 0)
    let blue = AK47LCDRGBAColor(red: 0, green: 0, blue: 255)
    let source = try splitImage(
      width: 32,
      height: 9,
      first: red,
      second: blue,
      splitVertically: true
    )

    let centered = try source.renderedForDevice(aspectFill: .centered)
    XCTAssertEqual(centered.width, AK47LCDFormat.canvasWidth)
    XCTAssertEqual(centered.height, AK47LCDFormat.canvasHeight)
    XCTAssertEqual(centered.color(x: 20, y: 67), red)
    XCTAssertEqual(centered.color(x: 220, y: 67), blue)

    let left = try source.renderedForDevice(
      aspectFill: AK47LCDAspectFillTransform.sourcePixels(x: -1_000, y: 0)
    )
    let right = try source.renderedForDevice(
      aspectFill: AK47LCDAspectFillTransform.sourcePixels(x: 1_000, y: 0)
    )
    XCTAssertEqual(left.color(x: 120, y: 67), red)
    XCTAssertEqual(right.color(x: 120, y: 67), blue)
    XCTAssertTrue(left.isOpaque)
    XCTAssertTrue(right.isOpaque)
  }

  func testVerticalViewportNudgeChangesTheRenderedLCDContent() throws {
    let green = AK47LCDRGBAColor(red: 0, green: 255, blue: 0)
    let magenta = AK47LCDRGBAColor(red: 255, green: 0, blue: 255)
    let source = try splitImage(
      width: 16,
      height: 18,
      first: green,
      second: magenta,
      splitVertically: false
    )
    let top = try source.renderedForDevice(
      aspectFill: AK47LCDAspectFillTransform.sourcePixels(x: 0, y: -1_000)
    )
    let bottom = try source.renderedForDevice(
      aspectFill: AK47LCDAspectFillTransform.sourcePixels(x: 0, y: 1_000)
    )
    XCTAssertEqual(top.color(x: 120, y: 67), green)
    XCTAssertEqual(bottom.color(x: 120, y: 67), magenta)
  }

  func testResolvedLayoutCanRenderEveryDecodedFrameAndPreservesDelays() throws {
    let first = try splitImage(
      width: 32,
      height: 9,
      first: AK47LCDRGBAColor(red: 255, green: 0, blue: 0),
      second: AK47LCDRGBAColor(red: 0, green: 0, blue: 255),
      splitVertically: true
    )
    let second = try splitImage(
      width: 32,
      height: 9,
      first: AK47LCDRGBAColor(red: 0, green: 255, blue: 0),
      second: AK47LCDRGBAColor(red: 255, green: 0, blue: 255),
      splitVertically: true
    )
    let decoded = AK47LCDDecodedGIF(
      sourceWidth: 32,
      sourceHeight: 9,
      frames: [
        AK47LCDDecodedGIFFrame(
          image: first,
          sourceDelay: try AK47LCDSourceDelay(milliseconds: 70)
        ),
        AK47LCDDecodedGIFFrame(
          image: second,
          sourceDelay: try AK47LCDSourceDelay(milliseconds: 130)
        ),
      ]
    )

    let project = try decoded.makeProject(
      aspectFill: AK47LCDAspectFillTransform.sourcePixels(x: 1_000, y: 0)
    )
    XCTAssertEqual(project.frames.count, 2)
    XCTAssertEqual(project.frames.map(\.sourceDelay.milliseconds), [70, 130])
    XCTAssertEqual(
      project.frames[0].image.color(x: 120, y: 67),
      AK47LCDRGBAColor(red: 0, green: 0, blue: 255)
    )
    XCTAssertEqual(
      project.frames[1].image.color(x: 120, y: 67),
      AK47LCDRGBAColor(red: 255, green: 0, blue: 255)
    )
  }

  func testResolvedLayoutCannotBeAppliedToDifferentSourceDimensions() throws {
    let layout = try AK47LCDAspectFillTransform.centered.resolved(
      sourceWidth: 32,
      sourceHeight: 9
    )
    let other = try AK47LCDRGBAImage(width: 31, height: 9, color: .black)
    XCTAssertThrowsError(try other.renderedForDevice(aspectFillLayout: layout)) { error in
      XCTAssertEqual(
        error as? AK47LCDImageTransformError,
        .layoutSourceDimensionsMismatch(
          expectedWidth: 32,
          expectedHeight: 9,
          actualWidth: 31,
          actualHeight: 9
        )
      )
    }
  }

  private func splitImage(
    width: Int,
    height: Int,
    first: AK47LCDRGBAColor,
    second: AK47LCDRGBAColor,
    splitVertically: Bool
  ) throws -> AK47LCDRGBAImage {
    var pixels = Data(count: width * height * AK47LCDFormat.rgbaBytesPerPixel)
    pixels.withUnsafeMutableBytes { rawBuffer in
      guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }
      for y in 0..<height {
        for x in 0..<width {
          let useFirst = splitVertically ? x < width / 2 : y < height / 2
          let color = useFirst ? first : second
          let offset = ((y * width) + x) * 4
          bytes[offset] = color.red
          bytes[offset + 1] = color.green
          bytes[offset + 2] = color.blue
          bytes[offset + 3] = color.alpha
        }
      }
    }
    return try AK47LCDRGBAImage(width: width, height: height, pixels: pixels)
  }
}
