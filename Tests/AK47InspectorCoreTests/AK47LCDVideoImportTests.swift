import XCTest

@testable import AK47InspectorCore

final class AK47LCDVideoImportTests: XCTestCase {
  func testRecommendedSelectionUsesThreeSecondsAtTenFPS() throws {
    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: 9_000,
      width: 1_920,
      height: 1_080
    )
    let selection = try AK47LCDVideoSelection.recommended(for: metadata)
    let plan = try AK47LCDVideoImportPlan(metadata: metadata, selection: selection)

    XCTAssertEqual(selection.startMilliseconds, 0)
    XCTAssertEqual(selection.endMilliseconds, 3_000)
    XCTAssertEqual(selection.framesPerSecond, 10)
    XCTAssertEqual(plan.expectedFrameCount, 30)
    XCTAssertEqual(plan.samples.first?.timestampMilliseconds, 0)
    XCTAssertEqual(plan.samples.last?.timestampMilliseconds, 2_900)
    XCTAssertEqual(plan.samples.reduce(0) { $0 + $1.delayMilliseconds }, 3_000)
    XCTAssertTrue(plan.samples.allSatisfy { $0.delayMilliseconds == 100 })
  }

  func testShortVideoStillProducesOneBoundedFrame() throws {
    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: 50,
      width: 320,
      height: 180
    )
    let selection = try AK47LCDVideoSelection.recommended(for: metadata)
    let plan = try AK47LCDVideoImportPlan(metadata: metadata, selection: selection)

    XCTAssertEqual(plan.samples.count, 1)
    XCTAssertEqual(plan.samples[0].timestampMilliseconds, 0)
    XCTAssertEqual(plan.samples[0].delayMilliseconds, 50)
  }

  func testSixtyFPSUsesDeterministicSixteenAndSeventeenMillisecondDelays() throws {
    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: 1_000,
      width: 640,
      height: 360
    )
    let selection = try AK47LCDVideoSelection(
      startMilliseconds: 0,
      endMilliseconds: 1_000,
      framesPerSecond: 60
    )
    let plan = try AK47LCDVideoImportPlan(metadata: metadata, selection: selection)

    XCTAssertEqual(plan.expectedFrameCount, 60)
    XCTAssertEqual(plan.samples.prefix(4).map(\.timestampMilliseconds), [0, 16, 33, 50])
    XCTAssertEqual(Set(plan.samples.map(\.delayMilliseconds)), [16, 17])
    XCTAssertEqual(plan.samples.reduce(0) { $0 + $1.delayMilliseconds }, 1_000)
    XCTAssertTrue(plan.samples.allSatisfy { (1...511).contains($0.delayMilliseconds) })
  }

  func testFrameCeilingIsExactAndFailsClosedAboveIt() throws {
    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: 20_000,
      width: 640,
      height: 360
    )
    let exactSelection = try AK47LCDVideoSelection(
      startMilliseconds: 0,
      endMilliseconds: 14_000,
      framesPerSecond: 10
    )
    XCTAssertEqual(
      try AK47LCDVideoImportPlan(metadata: metadata, selection: exactSelection).expectedFrameCount,
      AK47LCDFormat.maximumFrameCount
    )

    let excessiveSelection = try AK47LCDVideoSelection(
      startMilliseconds: 0,
      endMilliseconds: 14_001,
      framesPerSecond: 10
    )
    XCTAssertThrowsError(
      try AK47LCDVideoImportPlan(metadata: metadata, selection: excessiveSelection)
    ) { error in
      XCTAssertEqual(
        error as? AK47LCDVideoImportError,
        .frameLimitExceeded(requested: 141, maximum: AK47LCDFormat.maximumFrameCount)
      )
    }
  }

  func testExtractionSizePreservesAspectWithinAggregateWorkBudget() throws {
    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: 14_000,
      width: 3_840,
      height: 2_160
    )
    let selection = try AK47LCDVideoSelection(
      startMilliseconds: 0,
      endMilliseconds: 14_000,
      framesPerSecond: 10
    )
    let plan = try AK47LCDVideoImportPlan(metadata: metadata, selection: selection)

    XCTAssertLessThanOrEqual(plan.maximumExtractionWidth, AK47LCDFormat.maximumSourceDimension)
    XCTAssertLessThanOrEqual(plan.maximumExtractionHeight, AK47LCDFormat.maximumSourceDimension)
    XCTAssertLessThanOrEqual(
      plan.estimatedDecodedPixelCount,
      AK47LCDFormat.maximumTotalDecodedPixels
    )
    XCTAssertEqual(
      Double(plan.maximumExtractionWidth) / Double(plan.maximumExtractionHeight),
      16.0 / 9.0,
      accuracy: 0.01
    )
  }

  func testInputAndSelectionValidationRejectsUnsafeBounds() throws {
    XCTAssertNoThrow(
      try AK47LCDVideoSourceMetadata(
        durationMilliseconds: 1_000,
        width: 8_192,
        height: 4_096
      )
    )
    XCTAssertThrowsError(
      try AK47LCDVideoSourceMetadata(
        durationMilliseconds: 1_000,
        width: 8_192,
        height: 4_097
      )
    ) { error in
      XCTAssertEqual(error as? AK47LCDVideoImportError, .inputWorkLimitExceeded)
    }
    XCTAssertThrowsError(
      try AK47LCDVideoSelection(startMilliseconds: 0, endMilliseconds: 500, framesPerSecond: 1)
    ) { error in
      XCTAssertEqual(error as? AK47LCDVideoImportError, .invalidFrameRate(1))
    }

    let metadata = try AK47LCDVideoSourceMetadata(
      durationMilliseconds: 1_000,
      width: 640,
      height: 360
    )
    let outside = try AK47LCDVideoSelection(
      startMilliseconds: 900,
      endMilliseconds: 1_001,
      framesPerSecond: 10
    )
    XCTAssertThrowsError(try AK47LCDVideoImportPlan(metadata: metadata, selection: outside)) {
      error in
      XCTAssertEqual(
        error as? AK47LCDVideoImportError,
        .selectionExceedsDuration(endMilliseconds: 1_001, durationMilliseconds: 1_000)
      )
    }
  }
}
