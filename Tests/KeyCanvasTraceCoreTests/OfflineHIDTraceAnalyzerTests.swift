import Foundation
import XCTest

@testable import KeyCanvasTraceCore

final class OfflineHIDTraceAnalyzerTests: XCTestCase {
  func testSummaryCountsAndDurationWithoutSensitiveInputMetadata() throws {
    let trace = makeTrace(
      label: "private label",
      events: [
        event(0, 0, .hostToDevice, .control, 1, [1, 2]),
        event(1, nil, .deviceToHost, .interrupt, 2, [3]),
        event(2, 250, .hostToDevice, .bulk, 1, [4, 5, 6]),
      ])

    let summary = OfflineHIDTraceAnalyzer.summary(trace)

    XCTAssertEqual(summary.schemaVersion, 1)
    XCTAssertEqual(summary.eventCount, 3)
    XCTAssertEqual(summary.totalPayloadBytes, 6)
    XCTAssertEqual(summary.durationMicros, 250)
    XCTAssertEqual(
      summary.directionCounts,
      [
        OfflineHIDTraceDirectionCount(direction: .hostToDevice, count: 2),
        OfflineHIDTraceDirectionCount(direction: .deviceToHost, count: 1),
      ])
    XCTAssertEqual(
      summary.transferCounts,
      [
        OfflineHIDTransferCount(transfer: .control, count: 1),
        OfflineHIDTransferCount(transfer: .interrupt, count: 1),
        OfflineHIDTransferCount(transfer: .bulk, count: 1),
      ])
    XCTAssertEqual(
      summary.reportIDCounts,
      [
        OfflineHIDReportIDCount(reportID: 1, count: 2),
        OfflineHIDReportIDCount(reportID: 2, count: 1),
      ])

    let object = try encodedObject(summary)
    XCTAssertNil(object["label"])
    XCTAssertNil(object["firstOffsetMicros"])
    XCTAssertNil(object["lastOffsetMicros"])
    XCTAssertNil(object["provenance"])
  }

  func testSummaryWithoutTimestampsHasNoDuration() {
    let summary = OfflineHIDTraceAnalyzer.summary(
      makeTrace(events: [event(0, nil, .hostToDevice, .control, 0, [])])
    )
    XCTAssertNil(summary.durationMicros)
  }

  func testIdenticalEventsProduceNoDifferences() {
    let events = [event(0, 0, .hostToDevice, .control, 1, [1, 2])]
    let comparison = OfflineHIDTraceAnalyzer.compare(
      makeTrace(label: "before", events: events),
      makeTrace(label: "after", events: events)
    )

    XCTAssertFalse(comparison.hasDifferences)
    XCTAssertEqual(comparison.unchangedEventCount, 1)
    XCTAssertEqual(comparison.eventDifferences, [])
    XCTAssertEqual(comparison.totalByteDifferenceCount, 0)
    XCTAssertFalse(comparison.detailsTruncated)
  }

  func testCompareReportsMetadataAndChangedOffsetsOnly() {
    let baseline = makeTrace(events: [
      event(0, 0, .hostToDevice, .control, 1, [0x10, 0x20, 0x30])
    ])
    let candidate = makeTrace(events: [
      event(0, 10, .deviceToHost, .interrupt, 2, [0x10, 0xFF, 0x30, 0x40])
    ])

    let comparison = OfflineHIDTraceAnalyzer.compare(baseline, candidate)
    let difference = comparison.eventDifferences[0]

    XCTAssertTrue(comparison.hasDifferences)
    XCTAssertEqual(comparison.totalByteDifferenceCount, 2)
    XCTAssertEqual(difference.kind, .modified)
    XCTAssertEqual(
      difference.metadataChanges,
      [.offsetMicros, .direction, .transfer, .reportID]
    )
    XCTAssertEqual(difference.baselinePayloadLength, 3)
    XCTAssertEqual(difference.candidatePayloadLength, 4)
    XCTAssertEqual(
      difference.byteDifferences,
      [
        OfflineHIDByteDifference(offset: 1),
        OfflineHIDByteDifference(offset: 3),
      ])
  }

  func testCompareReportsAddedAndRemovedEventsByIndex() {
    let common = event(0, 0, .hostToDevice, .control, 0, [1])
    let added = OfflineHIDTraceAnalyzer.compare(
      makeTrace(events: [common]),
      makeTrace(events: [common, event(1, 1, .hostToDevice, .bulk, 0, [2, 3])])
    )
    XCTAssertEqual(added.eventDifferences[0].kind, .added)
    XCTAssertNil(added.eventDifferences[0].baselinePayloadLength)
    XCTAssertEqual(added.eventDifferences[0].candidatePayloadLength, 2)

    let removed = OfflineHIDTraceAnalyzer.compare(
      makeTrace(events: [common, event(1, 1, .hostToDevice, .bulk, 0, [2])]),
      makeTrace(events: [common])
    )
    XCTAssertEqual(removed.eventDifferences[0].kind, .removed)
    XCTAssertEqual(removed.eventDifferences[0].baselinePayloadLength, 1)
    XCTAssertNil(removed.eventDifferences[0].candidatePayloadLength)
  }

  func testPublicCompareUsesFixedTenThousandDetailLimit() {
    let zeroes = [UInt8](repeating: 0, count: 4_096)
    let ones = [UInt8](repeating: 1, count: 4_096)
    let baseline = makeTrace(
      events: (0..<3).map {
        event($0, UInt64($0), .hostToDevice, .bulk, 0, zeroes)
      })
    let candidate = makeTrace(
      events: (0..<3).map {
        event($0, UInt64($0), .hostToDevice, .bulk, 0, ones)
      })

    let comparison = OfflineHIDTraceAnalyzer.compare(baseline, candidate)

    XCTAssertEqual(comparison.totalByteDifferenceCount, 12_288)
    XCTAssertEqual(
      comparison.eventDifferences.reduce(0) { $0 + $1.byteDifferences.count },
      10_000
    )
    XCTAssertTrue(comparison.detailsTruncated)
  }

  func testInternalCompareLimitSupportsBoundedTests() {
    let baseline = makeTrace(events: [
      event(0, 0, .hostToDevice, .control, 0, [0, 0, 0, 0])
    ])
    let candidate = makeTrace(events: [
      event(0, 0, .hostToDevice, .control, 0, [1, 1, 1, 1])
    ])

    let comparison = OfflineHIDTraceAnalyzer.compare(
      baseline,
      candidate,
      maximumDetailedByteDifferences: 2
    )

    XCTAssertEqual(comparison.totalByteDifferenceCount, 4)
    XCTAssertEqual(comparison.eventDifferences[0].byteDifferences.count, 2)
    XCTAssertTrue(comparison.detailsTruncated)
  }

  func testComparisonOutputOmitsLabelsAndObservedByteValues() throws {
    let comparison = OfflineHIDTraceAnalyzer.compare(
      makeTrace(
        label: "private before",
        events: [
          event(0, 0, .hostToDevice, .control, 0, [0x11])
        ]),
      makeTrace(
        label: "private after",
        events: [
          event(0, 0, .hostToDevice, .control, 0, [0xFF])
        ])
    )

    let root = try encodedObject(comparison)
    XCTAssertNil(root["baselineLabel"])
    XCTAssertNil(root["candidateLabel"])
    let differences = try XCTUnwrap(root["eventDifferences"] as? [[String: Any]])
    let bytes = try XCTUnwrap(differences[0]["byteDifferences"] as? [[String: Any]])
    XCTAssertEqual(bytes[0].keys.sorted(), ["offset"])
  }

  private func makeTrace(
    label: String = "synthetic",
    events: [OfflineHIDTraceEvent]
  ) -> OfflineHIDTrace {
    OfflineHIDTrace(
      label: label,
      provenance: OfflineHIDTraceProvenance(
        origin: .synthetic,
        authorizedUse: true,
        identifiersRemoved: true,
        absoluteTimestampsRemoved: true,
        firmwareTrafficExcluded: true
      ),
      events: events
    )
  }

  private func event(
    _ index: Int,
    _ offset: UInt64?,
    _ direction: OfflineHIDTraceDirection,
    _ transfer: OfflineHIDTransferKind,
    _ reportID: UInt8,
    _ bytes: [UInt8]
  ) -> OfflineHIDTraceEvent {
    OfflineHIDTraceEvent(
      index: index,
      offsetMicros: offset,
      direction: direction,
      transfer: transfer,
      reportID: reportID,
      bytes: bytes
    )
  }

  private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
