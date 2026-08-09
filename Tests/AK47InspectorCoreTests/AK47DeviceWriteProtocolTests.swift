import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47DeviceWriteProtocolTests: XCTestCase {
  func testClockPlanMatchesVerifiedAK47WireLayout() throws {
    let value = AK47ClockSyncValue(
      lcdItemNumber: 2,
      year: 2026,
      month: 8,
      day: 9,
      hour: 14,
      minute: 27,
      second: 31,
      weekday: 0
    )

    let steps = try AK47DeviceWriteProtocol.clockSteps(value)

    XCTAssertEqual(steps.count, 4)
    XCTAssertEqual(steps.map(\.stage), [.begin, .selectClock, .clockData, .commit])
    XCTAssertEqual(
      steps.map(\.readback),
      [.requireStatusOne, .requireStatusOne, .drain, .requireStatusOne]
    )
    XCTAssertEqual(Array(steps[0].payload.prefix(2)), [0x04, 0x18])
    XCTAssertEqual(Array(steps[1].payload.prefix(2)), [0x04, 0x28])
    XCTAssertEqual(steps[1].payload[8], 1)
    XCTAssertEqual(
      Array(steps[2].payload.prefix(11)),
      [0x00, 0x02, 0x5A, 26, 8, 9, 14, 27, 31, 0, 0]
    )
    XCTAssertEqual(Array(steps[2].payload.suffix(2)), [0xAA, 0x55])
    XCTAssertEqual(Array(steps[3].payload.prefix(2)), [0x04, 0x02])
  }

  func testClockStateMachineUsesThirtyFiveMillisecondsBeforeEverySetAndGet() throws {
    let value = AK47ClockSyncValue(
      year: 2026,
      month: 8,
      day: 9,
      hour: 14,
      minute: 27,
      second: 31,
      weekday: 0
    )
    let steps = try AK47DeviceWriteProtocol.clockSteps(value)
    let session = MockWriteFeatureSession(acknowledgementCount: 4)
    var sleeps: [UInt32] = []

    try AK47FeatureWriteStateMachine.execute(
      steps: steps,
      session: session,
      sleep: { sleeps.append($0) }
    )

    XCTAssertEqual(
      session.operations,
      steps.flatMap { [.set($0.payload), .get(64)] }
    )
    XCTAssertEqual(sleeps, Array(repeating: 35, count: 9))
  }

  func testClockDataReadbackIsDrainedWithoutTreatingEchoedYearAsStatus() throws {
    let value = AK47ClockSyncValue(
      year: 2026,
      month: 8,
      day: 9,
      hour: 14,
      minute: 27,
      second: 31,
      weekday: 0
    )
    let steps = try AK47DeviceWriteProtocol.clockSteps(value)
    var accepted = [UInt8](repeating: 0, count: 64)
    accepted[3] = 1
    var echoedClockData = steps[2].payload
    echoedClockData[3] = 26
    let session = MockWriteFeatureSession(
      acknowledgements: [accepted, accepted, echoedClockData, accepted]
    )

    XCTAssertNoThrow(
      try AK47FeatureWriteStateMachine.execute(
        steps: steps,
        session: session,
        sleep: { _ in }
      )
    )
  }

  func testRejectedAcknowledgementStopsWithoutLaterCommands() throws {
    let value = AK47ClockSyncValue(
      year: 2026,
      month: 8,
      day: 9,
      hour: 14,
      minute: 27,
      second: 31,
      weekday: 0
    )
    let steps = try AK47DeviceWriteProtocol.clockSteps(value)
    let session = MockWriteFeatureSession(acknowledgements: [[UInt8](repeating: 0, count: 64)])

    XCTAssertThrowsError(
      try AK47FeatureWriteStateMachine.execute(
        steps: steps,
        session: session,
        sleep: { _ in }
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47DeviceWriteError,
        .acknowledgementRejected(stage: .begin)
      )
    }
    XCTAssertEqual(session.operations, [.set(steps[0].payload), .get(64)])
  }

  func testAllNineteenOnboardModesEncodeWithoutHostAnimationFrames() throws {
    for mode in UInt8(1)...UInt8(19) {
      let value = AK47OnboardLightingValue(
        mode: mode,
        color: RGBColor(red: 0x12, green: 0x34, blue: 0x56),
        colorful: true,
        brightness: 5,
        speed: 3,
        direction: 1
      )
      let steps = try AK47DeviceWriteProtocol.onboardLightingSteps(value)
      XCTAssertEqual(steps.count, 5)
      XCTAssertEqual(
        steps.map(\.stage),
        [.begin, .selectOnboardLighting, .onboardLightingData, .commit, .finalize]
      )
      XCTAssertEqual(
        steps.map(\.readback),
        [.requireStatusOne, .requireStatusOne, .none, .requireStatusOne, .none]
      )
      XCTAssertEqual(steps[2].payload[0], mode)
      XCTAssertEqual(Array(steps[2].payload[1...3]), [0x12, 0x34, 0x56])
      XCTAssertEqual(steps[2].payload[8], 1)
      XCTAssertEqual(steps[2].payload[9], 5)
      XCTAssertEqual(steps[2].payload[10], 3)
      XCTAssertEqual(steps[2].payload[11], 1)
      XCTAssertEqual(Array(steps[2].payload[14...15]), [0xAA, 0x55])
    }
  }

  func testPerKeyPlanUsesVerifiedIndicesAndNinePackets() throws {
    let values = AK47PerKeyRGBQueryProtocol.lightIndices.map { lightIndex in
      AK47PerKeyRGBValue(
        lightIndex: lightIndex,
        color: RGBColor(
          red: UInt8(lightIndex),
          green: UInt8(lightIndex + 1),
          blue: UInt8(lightIndex + 2)
        )
      )
    }

    let steps = try AK47DeviceWriteProtocol.perKeyRGBSteps(
      brightness: 4,
      values: values.reversed()
    )

    XCTAssertEqual(steps.count, 18)
    XCTAssertEqual(steps[2].stage, .onboardLightingData)
    XCTAssertEqual(steps[2].payload[0], 0x80)
    XCTAssertEqual(steps[2].payload[9], 4)
    XCTAssertEqual(steps[6].stage, .selectPerKeyRGB)
    XCTAssertEqual(Array(steps[6].payload.prefix(2)), [0x04, 0x23])
    XCTAssertEqual(steps[6].payload[8], 9)

    let packets = Array(steps[7...15]).map(\.payload)
    let combined = packets.flatMap { $0 }
    for lightIndex in AK47PerKeyRGBQueryProtocol.lightIndices {
      let offset = lightIndex * 4
      XCTAssertEqual(combined[offset], UInt8(lightIndex))
      XCTAssertEqual(combined[offset + 1], UInt8(lightIndex))
      XCTAssertEqual(combined[offset + 2], UInt8(lightIndex + 1))
      XCTAssertEqual(combined[offset + 3], UInt8(lightIndex + 2))
    }
    XCTAssertEqual(Array(combined.suffix(2)), [0xAA, 0x55])
    XCTAssertEqual(
      Array(steps[7...15]).map(\.extraDelayAfterSetMilliseconds),
      [0, 0, 0, 0, 0, 0, 0, 0, 35]
    )
    XCTAssertEqual(steps[16].stage, .commit)
    XCTAssertEqual(steps[16].readback, .requireStatusOne)
    XCTAssertEqual(steps[17].stage, .finalize)
    XCTAssertEqual(steps[17].readback, .requireStatusOne)
  }

  func testPerKeyStateMachinePreservesTheFinalBulkSettleInterval() throws {
    let values = AK47PerKeyRGBQueryProtocol.lightIndices.map {
      AK47PerKeyRGBValue(lightIndex: $0, color: RGBColor(red: 1, green: 2, blue: 3))
    }
    let steps = try AK47DeviceWriteProtocol.perKeyRGBSteps(brightness: 3, values: values)
    let session = MockWriteFeatureSession(acknowledgementCount: 7)
    var sleeps: [UInt32] = []

    try AK47FeatureWriteStateMachine.execute(
      steps: steps,
      session: session,
      sleep: { sleeps.append($0) }
    )

    // 18 pre-SET delays + 7 ACK read delays + the bulk helper's final
    // post-packet delay + the conservative final session settle.
    XCTAssertEqual(sleeps, Array(repeating: 35, count: 27))
  }

  func testPerKeyPlanRejectsMissingOrDuplicateLightIndices() {
    let incomplete = AK47PerKeyRGBQueryProtocol.lightIndices.dropLast().map {
      AK47PerKeyRGBValue(lightIndex: $0, color: RGBColor(red: 0, green: 0, blue: 0))
    }
    XCTAssertThrowsError(
      try AK47DeviceWriteProtocol.perKeyRGBSteps(brightness: 5, values: incomplete)
    )

    var duplicate = AK47PerKeyRGBQueryProtocol.lightIndices.map {
      AK47PerKeyRGBValue(lightIndex: $0, color: RGBColor(red: 0, green: 0, blue: 0))
    }
    duplicate[1] = duplicate[0]
    XCTAssertThrowsError(
      try AK47DeviceWriteProtocol.perKeyRGBSteps(brightness: 5, values: duplicate)
    )
  }

  func testAuthorizationIsOperationSpecificAndSingleUse() throws {
    let clock = AK47DeviceWriteAuthorization(explicitlyConfirming: .clockSync)
    XCTAssertEqual(clock.kind, .clockSync)
    try clock.consume(for: .clockSync)
    XCTAssertThrowsError(try clock.consume(for: .clockSync)) {
      XCTAssertEqual(
        $0 as? AK47DeviceWriteError,
        .authorizationAlreadyConsumed(.clockSync)
      )
    }

    let lighting = AK47DeviceWriteAuthorization(explicitlyConfirming: .onboardLighting)
    XCTAssertThrowsError(try lighting.consume(for: .perKeyRGB)) {
      XCTAssertEqual(
        $0 as? AK47DeviceWriteError,
        .authorizationMismatch(expected: .perKeyRGB, actual: .onboardLighting)
      )
    }
  }
}

private final class MockWriteFeatureSession: AK47WriteFeatureSession {
  enum Operation: Equatable {
    case set([UInt8])
    case get(Int)
  }

  private var acknowledgements: [[UInt8]]
  private(set) var operations: [Operation] = []

  init(acknowledgementCount: Int) {
    var acknowledgement = [UInt8](repeating: 0, count: 64)
    acknowledgement[3] = 1
    acknowledgements = Array(repeating: acknowledgement, count: acknowledgementCount)
  }

  init(acknowledgements: [[UInt8]]) {
    self.acknowledgements = acknowledgements
  }

  func setFeature(_ bytes: [UInt8], stage _: AK47DeviceWriteStage) throws {
    operations.append(.set(bytes))
  }

  func getFeature(expectedLength: Int, stage _: AK47DeviceWriteStage) throws -> [UInt8] {
    operations.append(.get(expectedLength))
    guard !acknowledgements.isEmpty else {
      throw AK47DeviceWriteError.operationTimedOut(stage: .begin)
    }
    return acknowledgements.removeFirst()
  }
}
