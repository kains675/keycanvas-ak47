import AK47InspectorCore
@preconcurrency import AVFoundation
import CoreVideo
import Darwin
import Foundation
import XCTest

@testable import AK47StudioApp

final class LocalVideoImportServiceTests: XCTestCase {
  func testInspectAndExtractPreservesOrientationTimestampOrderAndColorOrder() async throws {
    let fixture = try await makeRotatedMovieFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let descriptor = try await LocalVideoImportService.inspect(url: fixture.url)
    XCTAssertEqual(descriptor.metadata.width, 8)
    XCTAssertEqual(descriptor.metadata.height, 16)
    XCTAssertGreaterThanOrEqual(descriptor.metadata.durationMilliseconds, 1_000)

    // Extraction must use the exact private snapshot that was inspected, not
    // reopen a path that can be swapped between the two phases.
    try FileManager.default.removeItem(at: fixture.url)
    let previewAssetURL = try await MainActor.run { () throws -> URL in
      let player = try LocalVideoImportService.makePreviewPlayer(descriptor: descriptor)
      let asset = try XCTUnwrap(player.currentItem?.asset as? AVURLAsset)
      return asset.url
    }
    XCTAssertNotEqual(previewAssetURL, fixture.url)
    XCTAssertTrue(FileManager.default.fileExists(atPath: previewAssetURL.path))

    let selection = try AK47LCDVideoSelection(
      startMilliseconds: 0,
      endMilliseconds: 1_000,
      framesPerSecond: 2
    )
    let result = try await LocalVideoImportService.extract(
      descriptor: descriptor,
      selection: selection
    )

    XCTAssertEqual(result.plan.samples.map(\.timestampMilliseconds), [0, 500])
    XCTAssertEqual(result.plan.samples.map(\.delayMilliseconds), [500, 500])
    XCTAssertEqual(result.decodedSource.sourceWidth, 8)
    XCTAssertEqual(result.decodedSource.sourceHeight, 16)
    XCTAssertEqual(result.decodedSource.frames.count, 2)
    XCTAssertEqual(result.decodedSource.frames.map(\.sourceDelay.milliseconds), [500, 500])

    let firstImage = result.decodedSource.frames[0].image
    let topLeft = try XCTUnwrap(firstImage.color(x: 1, y: 1))
    let topRight = try XCTUnwrap(firstImage.color(x: 6, y: 1))
    let bottomLeft = try XCTUnwrap(firstImage.color(x: 1, y: 14))
    let bottomRight = try XCTUnwrap(firstImage.color(x: 6, y: 14))
    // Source TL red / TR green / BL blue / BR yellow rotated +90° becomes
    // output TL blue / TR red / BL yellow / BR green. Wide margins tolerate
    // the tiny fixture's H.264 chroma subsampling while pinning direction.
    XCTAssertGreaterThan(topLeft.blue, topLeft.red + 80)
    XCTAssertGreaterThan(topLeft.blue, topLeft.green + 80)
    XCTAssertGreaterThan(topRight.red, topRight.green + 80)
    XCTAssertGreaterThan(topRight.red, topRight.blue + 80)
    XCTAssertGreaterThan(bottomLeft.red, bottomLeft.blue + 80)
    XCTAssertGreaterThan(bottomLeft.green, bottomLeft.blue + 80)
    XCTAssertGreaterThan(bottomRight.green, bottomRight.red + 80)
    XCTAssertGreaterThan(bottomRight.green, bottomRight.blue + 80)
    let second = try XCTUnwrap(result.decodedSource.frames[1].image.color(x: 4, y: 8))
    XCTAssertGreaterThan(second.blue, second.red + 80)
    XCTAssertGreaterThan(second.blue, second.green + 80)
  }

  func testInspectRejectsSymbolicLinkSource() async throws {
    let fixture = try await makeRotatedMovieFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let link = fixture.directory.appendingPathComponent("linked.mov")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.url)

    do {
      _ = try await LocalVideoImportService.inspect(url: link)
      XCTFail("Expected the local video symlink to be rejected")
    } catch {
      XCTAssertEqual(error as? LocalVideoImportError, .symbolicLinkNotAllowed)
    }
  }

  func testInspectRejectsFIFOWithoutBlockingOnOpen() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fifo = directory.appendingPathComponent("source.mov")
    let result = fifo.withUnsafeFileSystemRepresentation { path in
      Darwin.mkfifo(path, S_IRUSR | S_IWUSR)
    }
    XCTAssertEqual(result, 0)

    do {
      _ = try await LocalVideoImportService.inspect(url: fifo)
      XCTFail("Expected FIFO video input to be rejected")
    } catch {
      XCTAssertEqual(error as? LocalVideoImportError, .notLocalRegularFile)
    }
  }

  func testNonIntegerFrameGridUsesBoundedToleranceWithoutReordering() async throws {
    let frameTimes = (0...30).map {
      CMTime(value: CMTimeValue($0 * 1_001), timescale: 30_000)
    }
    let fixture = try await makeMovieFixture(
      frameTimes: frameTimes,
      endTime: CMTime(value: 31 * 1_001, timescale: 30_000),
      transform: .identity
    )
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    let descriptor = try await LocalVideoImportService.inspect(url: fixture.url)
    let selection = try AK47LCDVideoSelection(
      startMilliseconds: 105,
      endMilliseconds: 905,
      framesPerSecond: 10
    )
    let result = try await LocalVideoImportService.extract(
      descriptor: descriptor,
      selection: selection
    )

    XCTAssertEqual(
      result.plan.samples.map(\.timestampMilliseconds),
      Array(stride(from: 105, to: 905, by: 100))
    )
    XCTAssertEqual(result.decodedSource.frames.count, 8)
    let first = try XCTUnwrap(result.decodedSource.frames[0].image.color(x: 8, y: 4))
    let second = try XCTUnwrap(result.decodedSource.frames[1].image.color(x: 8, y: 4))
    XCTAssertGreaterThan(first.blue, first.red + 80)
    XCTAssertGreaterThan(second.red, second.blue + 80)
  }

  func testUntrustedFloatingPointDimensionsFailBeforeIntegerConversion() throws {
    XCTAssertThrowsError(
      try LocalVideoImportService.validatedBoundedDimensions(width: 1e100, height: 1)
    ) { error in
      XCTAssertEqual(error as? LocalVideoImportError, .invalidOrientedDimensions)
    }
    XCTAssertThrowsError(
      try LocalVideoImportService.validatedBoundedDimensions(
        width: .infinity,
        height: 1
      )
    )
    XCTAssertThrowsError(
      try LocalVideoImportService.validatedBoundedDimensions(width: 8_193, height: 1)
    )
    let rounded = try LocalVideoImportService.validatedBoundedDimensions(
      width: 16.000_000_001,
      height: 8
    )
    XCTAssertEqual(rounded.width, 16)
    XCTAssertEqual(rounded.height, 8)
  }

  func testAVAssetInspectionForbidsEveryExternalReferenceKind() {
    XCTAssertEqual(
      LocalVideoImportService.assetReferenceRestrictionsRawValue,
      AVAssetReferenceRestrictions.forbidAll.rawValue
    )
  }

  func testDeadlineReturnsWithoutJoiningAnOperationThatIgnoresCancellation() async throws {
    let started = Date()
    do {
      _ = try await LocalVideoDeadline.run(
        milliseconds: 20,
        timeoutError: DeadlineFixtureError.timedOut
      ) {
        Darwin.usleep(200_000)
        return 1
      }
      XCTFail("Expected the deadline to win")
    } catch {
      XCTAssertEqual(error as? DeadlineFixtureError, .timedOut)
    }
    XCTAssertLessThan(Date().timeIntervalSince(started), 0.15)
  }

  func testSuccessfulDeadlineCancelsItsSleepingTimer() async throws {
    let timerFired = expectation(description: "deadline timer fired after operation success")
    timerFired.isInverted = true
    let value = try await LocalVideoDeadline.run(
      milliseconds: 20,
      timeoutError: DeadlineFixtureError.timedOut,
      onDeadlineOrCancellation: { timerFired.fulfill() },
      operation: { 47 }
    )

    XCTAssertEqual(value, 47)
    await fulfillment(of: [timerFired], timeout: 0.08)
  }

  private func makeRotatedMovieFixture() async throws -> (directory: URL, url: URL) {
    try await makeMovieFixture(
      frameTimes: [
        .zero,
        CMTime(value: 1, timescale: 2),
        CMTime(value: 2, timescale: 2),
      ],
      endTime: CMTime(value: 3, timescale: 2),
      transform: CGAffineTransform(rotationAngle: .pi / 2),
      cornerPatternOnFirstFrame: true
    )
  }

  private func makeMovieFixture(
    frameTimes: [CMTime],
    endTime: CMTime,
    transform: CGAffineTransform,
    cornerPatternOnFirstFrame: Bool = false
  ) async throws -> (directory: URL, url: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("rotated.mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 16,
        AVVideoHeightKey: 8,
      ]
    )
    input.transform = transform
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 16,
        kCVPixelBufferHeightKey as String: 8,
      ]
    )
    guard writer.canAdd(input) else {
      throw FixtureError.writerSetupFailed
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? FixtureError.writerSetupFailed
    }
    writer.startSession(atSourceTime: .zero)

    for (index, presentationTime) in frameTimes.enumerated() {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      let isRed = index.isMultiple(of: 2)
      let buffer =
        try cornerPatternOnFirstFrame && index == 0
        ? makeCornerPatternPixelBuffer(width: 16, height: 8)
        : makePixelBuffer(
          width: 16,
          height: 8,
          blue: isRed ? 0 : 255,
          green: 0,
          red: isRed ? 255 : 0
        )
      guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
        throw writer.error ?? FixtureError.frameAppendFailed
      }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: endTime)
    await writer.finishWriting()
    guard writer.status == .completed else {
      throw writer.error ?? FixtureError.writerFinishFailed
    }
    return (directory, url)
  }

  private func makePixelBuffer(
    width: Int,
    height: Int,
    blue: UInt8,
    green: UInt8,
    red: UInt8
  ) throws -> CVPixelBuffer {
    var optionalBuffer: CVPixelBuffer?
    let result = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      ] as CFDictionary,
      &optionalBuffer
    )
    guard result == kCVReturnSuccess, let buffer = optionalBuffer else {
      throw FixtureError.pixelBufferCreationFailed
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
      throw FixtureError.pixelBufferCreationFailed
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
      let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let offset = x * 4
        row[offset] = blue
        row[offset + 1] = green
        row[offset + 2] = red
        row[offset + 3] = 255
      }
    }
    return buffer
  }

  private func makeCornerPatternPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var optionalBuffer: CVPixelBuffer?
    let result = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      ] as CFDictionary,
      &optionalBuffer
    )
    guard result == kCVReturnSuccess, let buffer = optionalBuffer else {
      throw FixtureError.pixelBufferCreationFailed
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
      throw FixtureError.pixelBufferCreationFailed
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
      let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
      for x in 0..<width {
        let offset = x * 4
        let isLeft = x < width / 2
        let isTop = y < height / 2
        let (blue, green, red): (UInt8, UInt8, UInt8) =
          switch (isLeft, isTop) {
          case (true, true): (0, 0, 255)
          case (false, true): (0, 255, 0)
          case (true, false): (255, 0, 0)
          case (false, false): (0, 255, 255)
          }
        row[offset] = blue
        row[offset + 1] = green
        row[offset + 2] = red
        row[offset + 3] = 255
      }
    }
    return buffer
  }
}

private enum FixtureError: Error {
  case writerSetupFailed
  case frameAppendFailed
  case writerFinishFailed
  case pixelBufferCreationFailed
}

private enum DeadlineFixtureError: Error, Equatable {
  case timedOut
}
