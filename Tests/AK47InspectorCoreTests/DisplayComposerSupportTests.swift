import AK47InspectorCore
import XCTest

@testable import AK47StudioApp

final class DisplayComposerSupportTests: XCTestCase {
  func testQualifiedPreviewDecodesExactSubmittedRGB565Bytes() throws {
    let sourceColor = AK47LCDRGBAColor(red: 250, green: 129, blue: 63)
    let image = try AK47LCDRGBAImage(
      width: AK47LCDFormat.canvasWidth,
      height: AK47LCDFormat.canvasHeight,
      color: sourceColor
    )
    let frame = try AK47LCDAnimationFrame(
      image: image,
      sourceDelay: AK47LCDSourceDelay(milliseconds: 80)
    )
    let project = try AK47LCDAnimationProject(frames: [frame])
    let container = try AK47LCDContainerEncoder.encode(project: project)

    let decoded = try LCDQualifiedUploadPreviewDecoder.decodeFrame(
      from: container,
      at: 0
    )

    XCTAssertEqual(
      decoded.color(x: 0, y: 0),
      AK47LCDRGBAColor(red: 255, green: 130, blue: 57)
    )
    XCTAssertEqual(
      decoded.color(x: AK47LCDFormat.canvasWidth - 1, y: AK47LCDFormat.canvasHeight - 1),
      AK47LCDRGBAColor(red: 255, green: 130, blue: 57)
    )
    XCTAssertThrowsError(
      try LCDQualifiedUploadPreviewDecoder.decodeFrame(from: container, at: 1)
    ) { error in
      XCTAssertEqual(error as? LCDQualifiedUploadPreviewError, .invalidFrameIndex(1))
    }
  }

  func testTimelinePreservesValidDelaysAndFillsInvalidOrMissingEntries() {
    let timeline = DisplayAnimationTimeline(
      frameCount: 5,
      sourceDelaysMilliseconds: [70, 0, 130, 60_001],
      fallbackDelayMilliseconds: 40
    )

    XCTAssertEqual(timeline.frameDelaysMilliseconds, [70, 40, 130, 40, 40])
    XCTAssertEqual(timeline.totalDurationMilliseconds, 320)
    XCTAssertEqual(timeline.delayMilliseconds(forFrameAt: 2), 130)
    XCTAssertNil(timeline.delayMilliseconds(forFrameAt: 5))
  }

  func testTimelineMapsLoopOffsetsToFrameBoundaries() {
    let timeline = DisplayAnimationTimeline(
      frameCount: 3,
      sourceDelaysMilliseconds: [70, 130, 50],
      fallbackDelayMilliseconds: 40
    )

    XCTAssertEqual(timeline.startOffsetMilliseconds(forFrameAt: 0), 0)
    XCTAssertEqual(timeline.startOffsetMilliseconds(forFrameAt: 2), 200)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: 0), 0)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: 69), 0)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: 70), 1)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: 199), 1)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: 200), 2)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: 250), 0)
    XCTAssertEqual(timeline.frameIndex(atLoopOffsetMilliseconds: -1), 2)
  }

  func testPreviewDelayClampDoesNotChangeSourceDelays() {
    let timeline = DisplayAnimationTimeline(
      frameCount: 3,
      sourceDelaysMilliseconds: [1, 16, 70],
      fallbackDelayMilliseconds: 40
    )

    XCTAssertEqual(timeline.frameDelaysMilliseconds, [1, 16, 70])
    XCTAssertEqual(timeline.previewDelayMilliseconds(forFrameAt: 0, minimumMilliseconds: 16), 16)
    XCTAssertEqual(timeline.previewDelayMilliseconds(forFrameAt: 1, minimumMilliseconds: 16), 16)
    XCTAssertEqual(timeline.previewDelayMilliseconds(forFrameAt: 2, minimumMilliseconds: 16), 70)
    XCTAssertEqual(timeline.delayMilliseconds(forFrameAt: 0), 1)
  }

  func testPreviewWorkLimitsBoundDimensionsFramesAndAggregatePixels() {
    let limits = DisplayPreviewWorkLimits.localImport

    XCTAssertTrue(limits.permits(width: 2_000, height: 1_000, frameCount: 16))
    XCTAssertFalse(limits.permits(width: 2_049, height: 1, frameCount: 1))
    XCTAssertFalse(limits.permits(width: 2_001, height: 1_000, frameCount: 1))
    XCTAssertFalse(limits.permits(width: 240, height: 135, frameCount: 141))
    XCTAssertFalse(limits.permits(width: 2_000, height: 1_000, frameCount: 17))
    XCTAssertFalse(limits.permits(width: 0, height: 135, frameCount: 1))
  }

  func testContainerEstimateUsesCeilingDivisionAndTracksFinalChunk() {
    let estimate = DisplayContainerEstimate(
      targetWidth: 240,
      targetHeight: 135,
      referenceFrameCount: 2,
      decodedWidth: 240,
      decodedHeight: 135,
      decodedFrameCount: 2,
      decodedDelayCount: 2,
      encodedContainerByteCount: 8_193,
      maximumContainerByteCount: 25 * 1_024 * 1_024,
      planningPageByteCount: 4_096
    )

    XCTAssertTrue(estimate.matchesTargetCanvas)
    XCTAssertTrue(estimate.referenceMatchesDecodedFrameCount)
    XCTAssertTrue(estimate.hasOneDelayPerDecodedFrame)
    XCTAssertTrue(estimate.isContainerWithinLimit)
    XCTAssertEqual(estimate.planningPageCount, 3)
    XCTAssertEqual(estimate.finalPlanningPageByteCount, 1)
    XCTAssertTrue(estimate.isInternallyConsistent)
  }

  func testContainerEstimateSeparatesCanvasNoticeFromFileConsistency() {
    let estimate = DisplayContainerEstimate(
      targetWidth: 240,
      targetHeight: 135,
      referenceFrameCount: 3,
      decodedWidth: 480,
      decodedHeight: 270,
      decodedFrameCount: 3,
      decodedDelayCount: 3,
      encodedContainerByteCount: 4_096,
      maximumContainerByteCount: 8_192,
      planningPageByteCount: 4_096
    )

    XCTAssertFalse(estimate.matchesTargetCanvas)
    XCTAssertTrue(estimate.isInternallyConsistent)
    XCTAssertEqual(estimate.planningPageCount, 1)
    XCTAssertEqual(estimate.finalPlanningPageByteCount, 4_096)
  }

  func testContainerEstimateRejectsCountDelayAndSizeMismatches() {
    let estimate = DisplayContainerEstimate(
      targetWidth: 240,
      targetHeight: 135,
      referenceFrameCount: 4,
      decodedWidth: 240,
      decodedHeight: 135,
      decodedFrameCount: 3,
      decodedDelayCount: 2,
      encodedContainerByteCount: 8_193,
      maximumContainerByteCount: 8_192,
      planningPageByteCount: 4_096
    )

    XCTAssertFalse(estimate.referenceMatchesDecodedFrameCount)
    XCTAssertFalse(estimate.hasOneDelayPerDecodedFrame)
    XCTAssertFalse(estimate.isContainerWithinLimit)
    XCTAssertFalse(estimate.isInternallyConsistent)
  }

  func testPlaylistEditingReordersRemovesAndAppendsWithoutDuplication() {
    let original = ["a", "b", "c"]

    XCTAssertEqual(DisplayPlaylistEditing.moving(original, from: 1, by: -1), ["b", "a", "c"])
    XCTAssertEqual(DisplayPlaylistEditing.moving(original, from: 2, by: 1), original)
    XCTAssertEqual(DisplayPlaylistEditing.removing(original, at: 1), ["a", "c"])
    XCTAssertEqual(DisplayPlaylistEditing.removing(original, at: 3), original)
    XCTAssertEqual(DisplayPlaylistEditing.appending("d", to: original), ["a", "b", "c", "d"])
    XCTAssertEqual(DisplayPlaylistEditing.appending("b", to: original), original)
    XCTAssertEqual(DisplayPlaylistEditing.appending("", to: original), original)
  }
}
