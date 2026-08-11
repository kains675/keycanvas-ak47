import AK47InspectorCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AK47StudioApp

@MainActor
final class DisplayAnimationEditorModelTests: XCTestCase {
  func testPendingFillTransformChangesOnlyExactOutputPreview() async throws {
    let fixture = try makeSquareGIFFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = makeModel(url: fixture.url)

    await model.loadIfNeeded()
    let originalProject = try XCTUnwrap(model.project)
    let originalPreview = try XCTUnwrap(model.previewFrameImage)
    XCTAssertFalse(model.requiresReplacementConfirmation)

    model.setResizeMode(.aspectFill)

    XCTAssertTrue(model.hasPendingSourceTransform)
    XCTAssertTrue(model.requiresReplacementConfirmation)
    XCTAssertEqual(model.project, originalProject)
    XCTAssertNotEqual(model.previewFrameImage, originalPreview)
    XCTAssertEqual(model.previewFrameImage?.width, AK47LCDFormat.canvasWidth)
    XCTAssertEqual(model.previewFrameImage?.height, AK47LCDFormat.canvasHeight)
    XCTAssertEqual(
      model.previewFrameImage?.color(x: 0, y: 0),
      AK47LCDRGBAColor(red: 255, green: 0, blue: 0)
    )
  }

  func testApplyingFillTransformMatchesPreviewAndPreservesMatchingFrameDelays() async throws {
    let fixture = try makeSquareGIFFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = makeModel(url: fixture.url)

    await model.loadIfNeeded()
    model.setSelectedSourceDelay(milliseconds: 222)
    model.setResizeMode(.aspectFill)
    let pendingPreview = try XCTUnwrap(model.previewFrameImage)

    await model.applyPendingSourceTransform()

    let project = try XCTUnwrap(model.project)
    XCTAssertFalse(model.hasPendingSourceTransform)
    XCTAssertEqual(project.frames.map(\.sourceDelay.milliseconds), [222, 100])
    XCTAssertEqual(project.frames[0].image, pendingPreview)
    XCTAssertEqual(model.previewFrameImage, project.frames[0].image)
  }

  func testInFlightTransformDoesNotOverwriteNewerProjectEdit() async throws {
    let fixture = try makeSquareGIFFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let renderStarted = expectation(description: "detached transform started")
    let allowRenderToFinish = DispatchSemaphore(value: 0)
    let renderer: DisplaySourceTransformRenderer = { source, mode, aspectFill in
      renderStarted.fulfill()
      _ = allowRenderToFinish.wait(timeout: .now() + 5)
      if mode == .aspectFill {
        return try source.makeProject(aspectFill: aspectFill ?? .centered)
      }
      return try source.makeProject(resizeMode: mode)
    }
    let model = makeModel(url: fixture.url, renderer: renderer)

    await model.loadIfNeeded()
    model.setResizeMode(.aspectFill)
    let applyTask = Task { await model.applyPendingSourceTransform() }
    await fulfillment(of: [renderStarted], timeout: 2)

    model.setSelectedSourceDelay(milliseconds: 333)
    allowRenderToFinish.signal()
    await applyTask.value

    XCTAssertEqual(model.project?.frames[0].sourceDelay.milliseconds, 333)
    XCTAssertTrue(model.hasPendingSourceTransform)
    XCTAssertTrue(model.message?.contains("newer local edit") == true)
  }

  func testLargeNudgeReachesAndStopsAtFractionalSourceEdge() async throws {
    let fixture = try makeSolidGIFFixture(width: 400, height: 200)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let model = makeModel(url: fixture.url)

    await model.loadIfNeeded()
    model.setResizeMode(.aspectFill)
    model.nudgeAspectFill(x: 10, y: 0)
    model.nudgeAspectFill(x: 10, y: 0)
    model.nudgeAspectFill(x: 10, y: 0)

    let layout = try XCTUnwrap(model.aspectFillLayout)
    XCTAssertEqual(model.fillOffsetX, 23)
    XCTAssertEqual(layout.sourcePixelOffsetXRange, -23...23)
    XCTAssertEqual(layout.appliedSourceOffsetX, 200.0 / 9.0, accuracy: 0.000_001)
    XCTAssertFalse(model.canNudgeAspectFill(x: 1, y: 0))
    XCTAssertEqual(layout.viewport.maxX, 400, accuracy: 0.000_001)

    model.setResizeMode(.aspectFit)
    XCTAssertEqual(model.fillOffsetX, 23)
    model.setResizeMode(.aspectFill)
    XCTAssertEqual(model.fillOffsetX, 23)
    XCTAssertEqual(
      try XCTUnwrap(model.aspectFillLayout?.viewport.maxX),
      400,
      accuracy: 0.000_001
    )
  }

  func testPreparedDecodedSourceUsesTheSameEditorWithoutReopeningSourceURL() async throws {
    let fixture = try makeSquareGIFFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoded = try AK47LCDGIFDecoder.decode(url: fixture.url)
    let unavailableSourceURL = fixture.directory.appendingPathComponent("movie.mov")
    let model = DisplayAnimationEditorModel(
      input: DisplayAnimationEditorInput(
        sourceURL: unavailableSourceURL,
        displayName: "movie.mov",
        fallbackDelayMilliseconds: 100,
        preparedDecodedSource: decoded,
        preparedSourceRequiresExport: true
      )
    )

    await model.loadIfNeeded()

    XCTAssertEqual(model.project?.frames.count, decoded.frames.count)
    XCTAssertEqual(model.sourceWidth, decoded.sourceWidth)
    XCTAssertTrue(model.requiresReplacementConfirmation)
    XCTAssertFalse(model.hasUnexportedChanges)
    XCTAssertFalse(model.messageIsError)
  }

  func testPreparedLibraryImageDoesNotRequireExportUntilEdited() async throws {
    let fixture = try makeSquareGIFFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoded = try AK47LCDGIFDecoder.decode(url: fixture.url)
    let model = DisplayAnimationEditorModel(
      input: DisplayAnimationEditorInput(
        sourceURL: fixture.url,
        displayName: "stored.gif",
        fallbackDelayMilliseconds: 100,
        preparedDecodedSource: decoded
      )
    )

    await model.loadIfNeeded()

    XCTAssertFalse(model.requiresReplacementConfirmation)
    model.setSelectedSourceDelay(milliseconds: 222)
    XCTAssertTrue(model.requiresReplacementConfirmation)
  }

  private func makeModel(
    url: URL,
    renderer: @escaping DisplaySourceTransformRenderer = { source, mode, aspectFill in
      if mode == .aspectFill {
        return try source.makeProject(aspectFill: aspectFill ?? .centered)
      }
      return try source.makeProject(resizeMode: mode)
    }
  ) -> DisplayAnimationEditorModel {
    DisplayAnimationEditorModel(
      input: DisplayAnimationEditorInput(
        sourceURL: url,
        displayName: "square.gif",
        fallbackDelayMilliseconds: 100
      ),
      sourceTransformRenderer: renderer
    )
  }

  private func makeSquareGIFFixture() throws -> (directory: URL, url: URL) {
    // GIF89a: an opaque red 4x4 canvas followed by a 2x2 blue sub-frame.
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
    let url = directory.appendingPathComponent("square.gif")
    try data.write(to: url, options: .atomic)
    return (directory, url)
  }

  private func makeSolidGIFFixture(width: Int, height: Int) throws -> (
    directory: URL, url: URL
  ) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("solid.gif")
    var pixels = Data(count: width * height * 4)
    pixels.withUnsafeMutableBytes { rawBuffer in
      guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      for offset in stride(from: 0, to: rawBuffer.count, by: 4) {
        bytes[offset] = 255
        bytes[offset + 3] = 255
      }
    }
    guard
      let provider = CGDataProvider(data: pixels as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      ),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.gif.identifier as CFString,
        1,
        nil
      )
    else {
      throw FixtureError.creationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FixtureError.creationFailed
    }
    return (directory, url)
  }

  private enum FixtureError: Error {
    case creationFailed
  }
}
