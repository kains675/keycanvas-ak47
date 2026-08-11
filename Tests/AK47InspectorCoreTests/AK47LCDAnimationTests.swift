import Darwin
import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47LCDAnimationTests: XCTestCase {
  func testGIFDecoderRejectsFIFOWithoutBlockingOnOpen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fifo = directory.appendingPathComponent("source.gif")
    let result = fifo.withUnsafeFileSystemRepresentation { path in
      Darwin.mkfifo(path, S_IRUSR | S_IWUSR)
    }
    XCTAssertEqual(result, 0)

    XCTAssertThrowsError(try AK47LCDGIFDecoder.decode(url: fifo)) { error in
      XCTAssertEqual(error as? AK47LCDImageCodecError, .notLocalRegularFile)
    }
  }

  func testProjectAddsDuplicatesMovesRemovesAndEditsDelay() throws {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let first = try frame(id: firstID, color: .black, delay: 70)
    let second = try frame(id: secondID, color: .white, delay: 130)
    var project = try AK47LCDAnimationProject(frames: [first])

    try project.append(second)
    try project.duplicateFrame(at: 0, newIdentifier: duplicateID)
    XCTAssertEqual(project.frames.map(\.id), [firstID, duplicateID, secondID])

    try project.moveFrame(from: 2, to: 0)
    XCTAssertEqual(project.frames.map(\.id), [secondID, firstID, duplicateID])
    try project.setSourceDelay(milliseconds: 222, at: 1)
    XCTAssertEqual(project.frames[1].sourceDelay.milliseconds, 222)

    let removed = try project.removeFrame(at: 2)
    XCTAssertEqual(removed.id, duplicateID)
    XCTAssertEqual(project.frames.map(\.id), [secondID, firstID])
  }

  func testProjectPreventsEmptyOrOversizedFrameSet() throws {
    XCTAssertThrowsError(try AK47LCDAnimationProject(frames: [])) { error in
      XCTAssertEqual(error as? AK47LCDAnimationError, .invalidFrameCount(0))
    }

    var oneFrame = try AK47LCDAnimationProject(frames: [frame(color: .black, delay: 100)])
    XCTAssertThrowsError(try oneFrame.removeFrame(at: 0)) { error in
      XCTAssertEqual(error as? AK47LCDAnimationError, .cannotRemoveOnlyFrame)
    }

    let base = try frame(color: .black, delay: 100)
    var maximum = try AK47LCDAnimationProject(
      frames: Array(repeating: base, count: AK47LCDFormat.maximumFrameCount)
    )
    XCTAssertThrowsError(try maximum.append(base)) { error in
      XCTAssertEqual(
        error as? AK47LCDAnimationError,
        .frameLimitExceeded(maximum: AK47LCDFormat.maximumFrameCount)
      )
    }
  }

  func testAspectFitLetterboxesAndExplicitCropStretchesSelectedPixels() throws {
    let red = AK47LCDRGBAColor(red: 255, green: 0, blue: 0)
    let blue = AK47LCDRGBAColor(red: 0, green: 0, blue: 255)
    var bytes = Data(count: 4 * 2 * 4)
    for y in 0..<2 {
      for x in 0..<4 {
        setPixel(x < 2 ? red : blue, x: x, y: y, width: 4, bytes: &bytes)
      }
    }
    let source = try AK47LCDRGBAImage(width: 4, height: 2, pixels: bytes)

    let fit = try source.renderedForDevice(mode: .aspectFit)
    XCTAssertEqual(fit.color(x: 120, y: 0), .black)
    XCTAssertEqual(fit.color(x: 10, y: 7), red)
    XCTAssertEqual(fit.color(x: 230, y: 7), blue)

    let cropped = try source.renderedForDevice(
      mode: .stretch,
      cropRectangle: AK47LCDPixelRect(x: 2, y: 0, width: 2, height: 2)
    )
    XCTAssertEqual(cropped.color(x: 0, y: 0), blue)
    XCTAssertEqual(cropped.color(x: 239, y: 134), blue)
  }

  func testBoundedStrokeAndBitmapTextAuthorOpaquePixels() throws {
    var project = try AK47LCDAnimationProject(frames: [frame(color: .black, delay: 100)])
    try project.drawStroke(
      at: 0,
      points: [AK47LCDPixelPoint(x: 10, y: 10), AK47LCDPixelPoint(x: 20, y: 10)],
      radius: 1,
      color: .white
    )
    XCTAssertEqual(project.frames[0].image.color(x: 15, y: 10), .white)

    try project.drawBitmapText(
      at: 0,
      text: "A1",
      origin: AK47LCDPixelPoint(x: 0, y: 0),
      scale: 1,
      color: .white
    )
    XCTAssertEqual(project.frames[0].image.color(x: 1, y: 0), .white)
    XCTAssertEqual(project.frames[0].image.color(x: 0, y: 0), .black)
    XCTAssertTrue(project.frames[0].image.isOpaque)

    XCTAssertThrowsError(
      try project.drawBitmapText(
        at: 0,
        text: "한글",
        origin: AK47LCDPixelPoint(x: 0, y: 0),
        scale: 1,
        color: .white
      )
    ) { error in
      XCTAssertEqual(error as? AK47LCDAnimationError, .invalidTextOverlay)
    }
  }

  func testVerifiedDelayEncodingSeparatesSourceNominalAndFirmwareEffectiveTiming() throws {
    let odd = try AK47LCDDeviceDelay(
      verifiedSourceDelay: AK47LCDSourceDelay(milliseconds: 71)
    )
    XCTAssertEqual(odd.rawValue, 35)
    XCTAssertEqual(odd.nominalMilliseconds, 70)
    XCTAssertEqual(odd.effectiveFirmwareMilliseconds, 70)
    XCTAssertFalse(odd.usesFirmwareMinimum)

    let fast = try AK47LCDDeviceDelay(
      verifiedSourceDelay: AK47LCDSourceDelay(milliseconds: 20)
    )
    XCTAssertEqual(fast.rawValue, 10)
    XCTAssertEqual(fast.nominalMilliseconds, 20)
    XCTAssertEqual(fast.firmwareSchedulerRawValue, 25)
    XCTAssertEqual(fast.effectiveFirmwareMilliseconds, 50)
    XCTAssertTrue(fast.usesFirmwareMinimum)

    for sourceMilliseconds in 0...3 {
      let minimum = try AK47LCDDeviceDelay(
        verifiedSourceDelay: AK47LCDSourceDelay(milliseconds: sourceMilliseconds)
      )
      XCTAssertEqual(minimum.rawValue, 1)
      XCTAssertEqual(minimum.nominalMilliseconds, 2)
      XCTAssertEqual(minimum.effectiveFirmwareMilliseconds, 50)
    }

    let maximum = try AK47LCDDeviceDelay(
      verifiedSourceDelay: AK47LCDSourceDelay(milliseconds: 511)
    )
    XCTAssertEqual(maximum.rawValue, 255)
    XCTAssertEqual(maximum.nominalMilliseconds, 510)

    XCTAssertThrowsError(
      try AK47LCDDeviceDelay(
        verifiedSourceDelay: AK47LCDSourceDelay(milliseconds: 512)
      )
    ) { error in
      XCTAssertEqual(
        error as? AK47LCDAnimationError,
        .deviceDelaySourceOutOfRange(milliseconds: 512)
      )
    }
  }

  func testContainerEncodesHeaderRGB565LittleEndianAndExactFFPages() throws {
    let project = try AK47LCDAnimationProject(
      frames: [
        frame(
          color: AK47LCDRGBAColor(red: 255, green: 0, blue: 0),
          delay: 71
        )
      ]
    )
    let encoded = try AK47LCDContainerEncoder.encode(project: project)

    XCTAssertEqual(encoded.frameCount, 1)
    XCTAssertEqual(encoded.sourceDelaysMilliseconds, [71])
    XCTAssertEqual(encoded.encodedDeviceDelays, [35])
    XCTAssertEqual(encoded.nominalEncodedDelaysMilliseconds, [70])
    XCTAssertEqual(encoded.effectiveDeviceDelaysMilliseconds, [70])
    XCTAssertEqual(encoded.unpaddedByteCount, 65_056)
    XCTAssertEqual(encoded.pageCount, 16)
    XCTAssertEqual(encoded.data.count, 65_536)
    XCTAssertEqual(encoded.pages.count, 16)
    XCTAssertTrue(encoded.pages.allSatisfy { $0.count == 4_096 })
    XCTAssertEqual(encoded.data[0], 1)
    XCTAssertEqual(encoded.data[1], 35)
    XCTAssertTrue(encoded.data[2..<256].allSatisfy { $0 == 0xFF })
    XCTAssertEqual(encoded.data[256], 0x00)
    XCTAssertEqual(encoded.data[257], 0xF8)
    XCTAssertTrue(encoded.data[65_056...].allSatisfy { $0 == 0xFF })
  }

  func testContainerSupportsExplicitZeroPageTailWithoutChangingFFHeader() throws {
    let project = try AK47LCDAnimationProject(frames: [frame(color: .black, delay: 100)])
    let encoded = try AK47LCDContainerEncoder.encode(
      project: project,
      configuration: AK47LCDContainerEncoderConfiguration(pagePadding: .zero)
    )

    XCTAssertEqual(encoded.paddingByte, 0)
    XCTAssertTrue(encoded.data[2..<256].allSatisfy { $0 == 0xFF })
    XCTAssertTrue(encoded.data[65_056...].allSatisfy { $0 == 0 })
  }

  func testMaximumProjectFitsExactlyInsideConservativeSoftwareBudget() throws {
    let base = try frame(color: .black, delay: 100)
    let project = try AK47LCDAnimationProject(
      frames: Array(repeating: base, count: AK47LCDFormat.maximumFrameCount)
    )
    let encoded = try AK47LCDContainerEncoder.encode(project: project)

    XCTAssertEqual(encoded.frameCount, 140)
    XCTAssertEqual(encoded.unpaddedByteCount, 9_072_256)
    XCTAssertEqual(encoded.pageCount, 2_215)
    XCTAssertEqual(encoded.data.count, 9_072_640)
    XCTAssertEqual(encoded.data.count, AK47LCDFormat.maximumContainerByteCount)
    XCTAssertEqual(encoded.data[0], 140)
  }

  func testContainerRejectsDelayWrapTransparencyAndPartitionOverrun() throws {
    for delay in [512, 60_000] {
      let project = try AK47LCDAnimationProject(frames: [frame(color: .black, delay: delay)])
      XCTAssertThrowsError(try AK47LCDContainerEncoder.encode(project: project)) { error in
        XCTAssertEqual(
          error as? AK47LCDAnimationError,
          .sourceDelayNotDeviceEncodable(frameIndex: 0, milliseconds: delay)
        )
      }
    }

    let transparent = try frame(
      color: AK47LCDRGBAColor(red: 1, green: 2, blue: 3, alpha: 254),
      delay: 100
    )
    let transparentProject = try AK47LCDAnimationProject(frames: [transparent])
    XCTAssertThrowsError(try AK47LCDContainerEncoder.encode(project: transparentProject)) {
      error in
      XCTAssertEqual(
        error as? AK47LCDAnimationError,
        .transparentDeviceFrame(frameIndex: 0)
      )
    }

    let project = try AK47LCDAnimationProject(frames: [frame(color: .black, delay: 100)])
    XCTAssertThrowsError(
      try AK47LCDContainerEncoder.encode(
        project: project,
        configuration: AK47LCDContainerEncoderConfiguration(
          partitionBudgetByteCount: 15 * 4_096
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? AK47LCDAnimationError,
        .partitionBudgetExceeded(required: 16 * 4_096, budget: 15 * 4_096)
      )
    }
  }

  func testSyntheticGIFRoundTripPreservesFramesAndSourceDelays() throws {
    let source = try AK47LCDAnimationProject(
      frames: [
        frame(color: AK47LCDRGBAColor(red: 255, green: 0, blue: 0), delay: 70),
        frame(color: AK47LCDRGBAColor(red: 0, green: 0, blue: 255), delay: 130),
      ]
    )
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("synthetic.gif")

    try AK47LCDGIFEncoder.write(source, to: url)
    let decoded = try AK47LCDGIFDecoder.decode(url: url)
    XCTAssertEqual(decoded.sourceWidth, 240)
    XCTAssertEqual(decoded.sourceHeight, 135)
    XCTAssertEqual(decoded.frames.map(\.sourceDelay.milliseconds), [70, 130])
    XCTAssertEqual(
      decoded.frames[0].image.color(x: 100, y: 60),
      AK47LCDRGBAColor(red: 255, green: 0, blue: 0))
    XCTAssertEqual(
      decoded.frames[1].image.color(x: 100, y: 60),
      AK47LCDRGBAColor(red: 0, green: 0, blue: 255))

    let rebuilt = try decoded.makeProject(resizeMode: .aspectFit)
    XCTAssertEqual(rebuilt.frames.count, 2)
    XCTAssertEqual(rebuilt.sourceDurationMilliseconds, 200)
  }

  func testDelaylessSyntheticStillUsesVerifiedZeroSourceMapping() throws {
    let source = try AK47LCDAnimationProject(
      frames: [frame(color: .black, delay: 0)]
    )
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("still.gif")

    try AK47LCDGIFEncoder.write(source, to: url)
    let decoded = try AK47LCDGIFDecoder.decode(url: url)
    XCTAssertEqual(decoded.frames.map(\.sourceDelay.milliseconds), [0])

    let project = try decoded.makeProject(resizeMode: .aspectFit)
    let container = try AK47LCDContainerEncoder.encode(project: project)
    XCTAssertEqual(container.sourceDelaysMilliseconds, [0])
    XCTAssertEqual(container.encodedDeviceDelays, [1])
    XCTAssertEqual(container.effectiveDeviceDelaysMilliseconds, [50])
  }

  func testSyntheticPartialGIFIsDecodedAsFullCompositedFrames() throws {
    let red = AK47LCDRGBAColor(red: 255, green: 0, blue: 0)
    let blue = AK47LCDRGBAColor(red: 0, green: 0, blue: 255)
    // Project-authored 4×4 GIF89a: an opaque red logical canvas followed by a
    // 2×2 blue sub-frame at offset (1,1), disposal none, 100 ms per frame.
    let data = Data([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x04, 0x00, 0x04, 0x00, 0xf0, 0x00,
      0x00, 0xff, 0x00, 0x00, 0xff, 0xff, 0xff, 0x21, 0xff, 0x0b, 0x4e, 0x45,
      0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2e, 0x30, 0x03, 0x01, 0x00,
      0x00, 0x00, 0x21, 0xf9, 0x04, 0x04, 0x0a, 0x00, 0x00, 0x00, 0x2c, 0x00,
      0x00, 0x00, 0x00, 0x04, 0x00, 0x04, 0x00, 0x00, 0x02, 0x04, 0x84, 0x8f,
      0x09, 0x05, 0x00, 0x21, 0xf9, 0x04, 0x04, 0x0a, 0x00, 0x00, 0x00, 0x2c,
      0x01, 0x00, 0x01, 0x00, 0x02, 0x00, 0x02, 0x00, 0x80, 0x00, 0x00, 0xff,
      0xff, 0xff, 0xff, 0x02, 0x02, 0x84, 0x51, 0x00, 0x3b,
    ])

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("partial.gif")
    try data.write(to: url, options: .atomic)

    let decoded = try AK47LCDGIFDecoder.decode(url: url)
    XCTAssertEqual(decoded.frames.count, 2)
    XCTAssertEqual(decoded.frames[1].image.width, 4)
    XCTAssertEqual(decoded.frames[1].image.height, 4)
    XCTAssertEqual(decoded.frames[1].image.color(x: 1, y: 1), blue)
    XCTAssertEqual(decoded.frames[1].image.color(x: 0, y: 0), red)
    XCTAssertEqual(decoded.frames[1].image.color(x: 3, y: 3), red)
  }

  func testAsymmetricVerticalRoundTripDoesNotFlipCanonicalRows() throws {
    let red = AK47LCDRGBAColor(red: 255, green: 0, blue: 0)
    let blue = AK47LCDRGBAColor(red: 0, green: 0, blue: 255)
    var bytes = Data(
      repeating: 0,
      count: AK47LCDFormat.canvasWidth * AK47LCDFormat.canvasHeight * 4
    )
    for y in 0..<AK47LCDFormat.canvasHeight {
      for x in 0..<AK47LCDFormat.canvasWidth {
        let color: AK47LCDRGBAColor
        if y == 0 {
          color = red
        } else if y == AK47LCDFormat.canvasHeight - 1 {
          color = blue
        } else {
          color = .black
        }
        setPixel(color, x: x, y: y, width: AK47LCDFormat.canvasWidth, bytes: &bytes)
      }
    }
    let sourceImage = try AK47LCDRGBAImage(
      width: AK47LCDFormat.canvasWidth,
      height: AK47LCDFormat.canvasHeight,
      pixels: bytes
    )
    let project = try AK47LCDAnimationProject(
      frames: [
        AK47LCDAnimationFrame(
          image: sourceImage,
          sourceDelay: AK47LCDSourceDelay(milliseconds: 100)
        )
      ]
    )
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("vertical.gif")

    try AK47LCDGIFEncoder.write(project, to: url)
    let decoded = try AK47LCDGIFDecoder.decode(url: url)
    XCTAssertEqual(decoded.frames[0].image.color(x: 120, y: 0), red)
    XCTAssertEqual(
      decoded.frames[0].image.color(x: 120, y: AK47LCDFormat.canvasHeight - 1),
      blue
    )

    let rebuilt = try decoded.makeProject(resizeMode: .stretch)
    let container = try AK47LCDContainerEncoder.encode(project: rebuilt)
    XCTAssertEqual(Array(container.data[256..<258]), [0x00, 0xF8])
    let lastPixel = 256 + AK47LCDFormat.rgb565FrameByteCount - 2
    XCTAssertEqual(Array(container.data[lastPixel..<(lastPixel + 2)]), [0x1F, 0x00])
  }

  func testDecoderRejectsSymbolicLinkInsteadOfFollowingAReplacedPath() throws {
    let project = try AK47LCDAnimationProject(
      frames: [frame(color: .black, delay: 100)]
    )
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("source.gif")
    let linkURL = directory.appendingPathComponent("link.gif")
    try AK47LCDGIFEncoder.write(project, to: sourceURL)
    try FileManager.default.createSymbolicLink(
      atPath: linkURL.path,
      withDestinationPath: sourceURL.path
    )

    XCTAssertThrowsError(try AK47LCDGIFDecoder.decode(url: linkURL)) { error in
      XCTAssertEqual(error as? AK47LCDImageCodecError, .notLocalRegularFile)
    }
  }

  func testDecoderRejectsOversizedSparseFileBeforeAllocatingItsContents() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("oversized.gif")
    XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(
      atOffset: UInt64(AK47LCDFormat.maximumCompressedGIFByteCount + 1)
    )
    try handle.close()

    XCTAssertThrowsError(try AK47LCDGIFDecoder.decode(url: url)) { error in
      XCTAssertEqual(
        error as? AK47LCDImageCodecError,
        .sourceFileTooLarge(maximumBytes: AK47LCDFormat.maximumCompressedGIFByteCount)
      )
    }
  }

  func testDecoderPreflightsEveryFrameAndAggregateWorkBeforeRasterDecode() throws {
    XCTAssertNoThrow(
      try AK47LCDGIFDecoder.validateDecodedWork(
        canvasWidth: 240,
        canvasHeight: 135,
        frameSizes: [(240, 135), (120, 80)]
      )
    )

    XCTAssertThrowsError(
      try AK47LCDGIFDecoder.validateDecodedWork(
        canvasWidth: 240,
        canvasHeight: 135,
        frameSizes: [(240, 135), (2_048, 2_048)]
      )
    ) { error in
      XCTAssertEqual(error as? AK47LCDImageCodecError, .sourceWorkLimitExceeded)
    }

    XCTAssertThrowsError(
      try AK47LCDGIFDecoder.validateDecodedWork(
        canvasWidth: 1_000,
        canvasHeight: 1_000,
        frameSizes: Array(repeating: (1_000, 1_000), count: 33)
      )
    ) { error in
      XCTAssertEqual(error as? AK47LCDImageCodecError, .sourceWorkLimitExceeded)
    }
  }

  private func frame(
    id: UUID = UUID(),
    color: AK47LCDRGBAColor,
    delay: Int
  ) throws -> AK47LCDAnimationFrame {
    try AK47LCDAnimationFrame(
      id: id,
      image: AK47LCDRGBAImage(
        width: AK47LCDFormat.canvasWidth,
        height: AK47LCDFormat.canvasHeight,
        color: color
      ),
      sourceDelay: AK47LCDSourceDelay(milliseconds: delay)
    )
  }

  private func setPixel(
    _ color: AK47LCDRGBAColor,
    x: Int,
    y: Int,
    width: Int,
    bytes: inout Data
  ) {
    let offset = ((y * width) + x) * 4
    bytes[offset] = color.red
    bytes[offset + 1] = color.green
    bytes[offset + 2] = color.blue
    bytes[offset + 3] = color.alpha
  }
}
