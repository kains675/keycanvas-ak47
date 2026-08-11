import AK47InspectorCore
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AK47StudioApp

final class LocalDisplayEditorSourceLoaderTests: XCTestCase {
  func testJPEGEXIFOrientationProducesOrientedEditorDimensions() throws {
    let fixture = try makeOrientedJPEGFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let originalBytes = try Data(contentsOf: fixture.url)
    let inspection = try LocalDisplayEditorSourceLoader.inspect(
      url: fixture.url,
      fallbackDelayMilliseconds: 100
    )
    let decoded = inspection.decodedSource

    XCTAssertEqual(inspection.sourceData, originalBytes)
    XCTAssertEqual(decoded.sourceWidth, 8)
    XCTAssertEqual(decoded.sourceHeight, 16)
    XCTAssertEqual(decoded.frames.count, 1)
    XCTAssertEqual(decoded.frames[0].sourceDelay.milliseconds, 0)
    XCTAssertTrue(decoded.frames[0].image.isOpaque)
  }

  func testLoaderRejectsSymbolicLinkInsteadOfFollowingIt() throws {
    let fixture = try makeOrientedJPEGFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let link = fixture.directory.appendingPathComponent("linked.jpg")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.url)

    XCTAssertThrowsError(
      try LocalDisplayEditorSourceLoader.load(
        url: link,
        fallbackDelayMilliseconds: 100
      )
    ) { error in
      XCTAssertEqual(error as? LocalDisplayEditorSourceError, .notLocalRegularFile)
    }
  }

  func testLoaderRejectsFIFOWithoutBlockingOnOpen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fifo = directory.appendingPathComponent("source.gif")
    let result = fifo.withUnsafeFileSystemRepresentation { path in
      Darwin.mkfifo(path, S_IRUSR | S_IWUSR)
    }
    XCTAssertEqual(result, 0)

    XCTAssertThrowsError(
      try LocalDisplayEditorSourceLoader.load(
        url: fifo,
        fallbackDelayMilliseconds: 100
      )
    ) { error in
      XCTAssertEqual(error as? LocalDisplayEditorSourceError, .notLocalRegularFile)
    }
  }

  func testFourKJPEGIsDownscaledWithinRetainedFrameWorkBudget() throws {
    let fixture = try makeJPEGFixture(width: 3_840, height: 2_160, orientation: 1)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let decoded = try LocalDisplayEditorSourceLoader.load(
      url: fixture.url,
      fallbackDelayMilliseconds: 100
    )
    let retainedPixels = decoded.sourceWidth * decoded.sourceHeight

    XCTAssertLessThanOrEqual(decoded.sourceWidth, AK47LCDFormat.maximumSourceDimension)
    XCTAssertLessThanOrEqual(decoded.sourceHeight, AK47LCDFormat.maximumSourceDimension)
    XCTAssertLessThanOrEqual(retainedPixels, 2_000_000)
    XCTAssertEqual(
      Double(decoded.sourceWidth) / Double(decoded.sourceHeight),
      16.0 / 9.0,
      accuracy: 0.01
    )
  }

  private func makeOrientedJPEGFixture() throws -> (directory: URL, url: URL) {
    try makeJPEGFixture(width: 16, height: 8, orientation: 6)
  }

  private func makeJPEGFixture(
    width: Int,
    height: Int,
    orientation: Int
  ) throws -> (directory: URL, url: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("oriented.jpg")
    var pixels = Data(count: width * height * 4)
    pixels.withUnsafeMutableBytes { rawBuffer in
      guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      for y in 0..<height {
        for x in 0..<width {
          let offset = ((y * width) + x) * 4
          bytes[offset] = x < width / 2 ? 255 : 0
          bytes[offset + 1] = 0
          bytes[offset + 2] = x < width / 2 ? 0 : 255
          bytes[offset + 3] = 255
        }
      }
    }
    let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
    let image = try XCTUnwrap(
      CGImage(
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
    )
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImagePropertyOrientation: orientation] as CFDictionary
    )
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return (directory, url)
  }
}
