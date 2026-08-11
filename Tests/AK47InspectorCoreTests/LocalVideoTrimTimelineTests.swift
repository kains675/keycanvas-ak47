import XCTest

@testable import AK47StudioApp

final class LocalVideoTrimTimelineTests: XCTestCase {
  func testSixtyFPSOutputGridHasNoAccumulatedRoundedStepDrift() {
    var state = LocalVideoTrimTimelineState(
      durationMilliseconds: 2_000,
      startMilliseconds: 0,
      endMilliseconds: 2_000,
      playheadMilliseconds: 0
    )
    var observed: [Int] = []
    for _ in 0..<60 {
      state.step(
        focus: .playhead,
        direction: .forward,
        samplingFramesPerSecond: 60
      )
      observed.append(state.playheadMilliseconds)
    }

    XCTAssertEqual(Array(observed.prefix(4)), [16, 33, 50, 66])
    XCTAssertEqual(observed.last, 1_000)
  }

  func testPlayheadStepsOnSelectionAnchoredOutputGrid() {
    var state = LocalVideoTrimTimelineState(
      durationMilliseconds: 2_000,
      startMilliseconds: 105,
      endMilliseconds: 905,
      playheadMilliseconds: 105
    )

    state.step(
      focus: .playhead,
      direction: .forward,
      samplingFramesPerSecond: 10
    )
    XCTAssertEqual(state.playheadMilliseconds, 205)
    state.step(
      focus: .playhead,
      direction: .forward,
      samplingFramesPerSecond: 10,
      multiplier: 3
    )
    XCTAssertEqual(state.playheadMilliseconds, 505)
    state.step(
      focus: .playhead,
      direction: .backward,
      samplingFramesPerSecond: 10
    )
    XCTAssertEqual(state.playheadMilliseconds, 405)
  }

  func testFPSChangeResnapsPlayheadToNearestSelectionAnchoredOutputSample() {
    var state = LocalVideoTrimTimelineState(
      durationMilliseconds: 2_000,
      startMilliseconds: 105,
      endMilliseconds: 905,
      playheadMilliseconds: 168
    )

    state.snapPlayheadToOutputGrid(framesPerSecond: 60)

    XCTAssertEqual(state.playheadMilliseconds, 171)
  }

  func testDualHandlesNeverCrossAndAlwaysRetainOneMillisecondSample() {
    var state = LocalVideoTrimTimelineState(
      durationMilliseconds: 1_000,
      startMilliseconds: 100,
      endMilliseconds: 900,
      playheadMilliseconds: 500
    )

    state.setStartMilliseconds(900)
    XCTAssertEqual(state.startMilliseconds, 899)
    XCTAssertEqual(state.endMilliseconds, 900)
    XCTAssertEqual(state.selectionDurationMilliseconds, 1)
    XCTAssertEqual(state.playheadMilliseconds, 899)

    state.setEndMilliseconds(0)
    XCTAssertEqual(state.startMilliseconds, 899)
    XCTAssertEqual(state.endMilliseconds, 900)
    XCTAssertEqual(state.selectionDurationMilliseconds, 1)

    state.step(
      focus: .startHandle,
      direction: .forward,
      samplingFramesPerSecond: 60,
      multiplier: .max
    )
    XCTAssertEqual(state.startMilliseconds, 899)
    XCTAssertEqual(state.endMilliseconds, 900)
  }

  func testHandleStepMovesPlayheadToTheAdjustedBoundary() {
    var state = LocalVideoTrimTimelineState(
      durationMilliseconds: 2_000,
      startMilliseconds: 100,
      endMilliseconds: 900,
      playheadMilliseconds: 500
    )

    state.step(
      focus: .startHandle,
      direction: .forward,
      samplingFramesPerSecond: 10
    )
    XCTAssertEqual(state.startMilliseconds, 200)
    XCTAssertEqual(state.playheadMilliseconds, 200)

    state.step(
      focus: .endHandle,
      direction: .backward,
      samplingFramesPerSecond: 10
    )
    XCTAssertEqual(state.endMilliseconds, 800)
    XCTAssertEqual(state.playheadMilliseconds, 800)
  }

  func testTimecodeUsesFixedHoursMinutesSecondsAndMilliseconds() {
    XCTAssertEqual(
      LocalVideoTrimTimelineState.timecode(milliseconds: 0),
      "00:00:00.000"
    )
    XCTAssertEqual(
      LocalVideoTrimTimelineState.timecode(milliseconds: 3_723_004),
      "01:02:03.004"
    )
    XCTAssertEqual(
      LocalVideoTrimTimelineState.timecode(milliseconds: 86_399_999),
      "23:59:59.999"
    )
    XCTAssertEqual(
      LocalVideoTrimTimelineState.timecode(milliseconds: -1),
      "00:00:00.000"
    )
  }

  func testTimelineGeometryFailsClosedForNonfiniteOrDegenerateInputs() {
    XCTAssertEqual(
      LocalVideoTimelineGeometry.milliseconds(
        x: 50,
        width: 100,
        durationMilliseconds: 1_000,
        horizontalInset: 10
      ),
      500
    )
    XCTAssertEqual(
      LocalVideoTimelineGeometry.milliseconds(
        x: .nan,
        width: 100,
        durationMilliseconds: 1_000,
        horizontalInset: 10
      ),
      0
    )
    XCTAssertEqual(
      LocalVideoTimelineGeometry.milliseconds(
        x: 50,
        width: .infinity,
        durationMilliseconds: 1_000,
        horizontalInset: 10
      ),
      0
    )
    XCTAssertEqual(
      LocalVideoTimelineGeometry.milliseconds(
        x: 10,
        width: 20,
        durationMilliseconds: 1_000,
        horizontalInset: 10
      ),
      0
    )
    XCTAssertEqual(
      LocalVideoTimelineGeometry.milliseconds(
        x: 1e100,
        width: 100,
        durationMilliseconds: 1_000,
        horizontalInset: 10
      ),
      1_000
    )
    XCTAssertEqual(
      LocalVideoTimelineGeometry.x(
        milliseconds: 500,
        width: .nan,
        durationMilliseconds: 1_000,
        horizontalInset: 10
      ),
      10
    )
  }
}
