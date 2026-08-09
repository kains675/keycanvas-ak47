import Foundation

public struct OfflineHIDTraceDirectionCount: Codable, Equatable, Sendable {
  public let direction: OfflineHIDTraceDirection
  public let count: Int

  public init(direction: OfflineHIDTraceDirection, count: Int) {
    self.direction = direction
    self.count = count
  }
}

public struct OfflineHIDTransferCount: Codable, Equatable, Sendable {
  public let transfer: OfflineHIDTransferKind
  public let count: Int

  public init(transfer: OfflineHIDTransferKind, count: Int) {
    self.transfer = transfer
    self.count = count
  }
}

public struct OfflineHIDReportIDCount: Codable, Equatable, Sendable {
  public let reportID: UInt8
  public let count: Int

  public init(reportID: UInt8, count: Int) {
    self.reportID = reportID
    self.count = count
  }
}

public struct OfflineHIDTraceSummary: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let eventCount: Int
  public let totalPayloadBytes: Int
  public let durationMicros: UInt64?
  public let directionCounts: [OfflineHIDTraceDirectionCount]
  public let transferCounts: [OfflineHIDTransferCount]
  public let reportIDCounts: [OfflineHIDReportIDCount]

  public init(
    schemaVersion: Int,
    eventCount: Int,
    totalPayloadBytes: Int,
    durationMicros: UInt64?,
    directionCounts: [OfflineHIDTraceDirectionCount],
    transferCounts: [OfflineHIDTransferCount],
    reportIDCounts: [OfflineHIDReportIDCount]
  ) {
    self.schemaVersion = schemaVersion
    self.eventCount = eventCount
    self.totalPayloadBytes = totalPayloadBytes
    self.durationMicros = durationMicros
    self.directionCounts = directionCounts
    self.transferCounts = transferCounts
    self.reportIDCounts = reportIDCounts
  }
}

public enum OfflineHIDTraceDifferenceKind: String, Codable, Equatable, Sendable {
  case added
  case removed
  case modified
}

public enum OfflineHIDTraceMetadataField: String, Codable, Equatable, Sendable {
  case offsetMicros
  case direction
  case transfer
  case reportID
}

public struct OfflineHIDByteDifference: Codable, Equatable, Sendable {
  public let offset: Int

  public init(offset: Int) {
    self.offset = offset
  }
}

public struct OfflineHIDTraceEventDifference: Codable, Equatable, Sendable {
  public let index: Int
  public let kind: OfflineHIDTraceDifferenceKind
  public let metadataChanges: [OfflineHIDTraceMetadataField]
  public let baselinePayloadLength: Int?
  public let candidatePayloadLength: Int?
  public let byteDifferenceCount: Int
  public let byteDifferences: [OfflineHIDByteDifference]

  public init(
    index: Int,
    kind: OfflineHIDTraceDifferenceKind,
    metadataChanges: [OfflineHIDTraceMetadataField],
    baselinePayloadLength: Int?,
    candidatePayloadLength: Int?,
    byteDifferenceCount: Int,
    byteDifferences: [OfflineHIDByteDifference]
  ) {
    self.index = index
    self.kind = kind
    self.metadataChanges = metadataChanges
    self.baselinePayloadLength = baselinePayloadLength
    self.candidatePayloadLength = candidatePayloadLength
    self.byteDifferenceCount = byteDifferenceCount
    self.byteDifferences = byteDifferences
  }
}

public struct OfflineHIDTraceComparison: Codable, Equatable, Sendable {
  public let baselineEventCount: Int
  public let candidateEventCount: Int
  public let unchangedEventCount: Int
  public let eventDifferences: [OfflineHIDTraceEventDifference]
  public let totalByteDifferenceCount: Int
  public let detailsTruncated: Bool
  public let hasDifferences: Bool

  public init(
    baselineEventCount: Int,
    candidateEventCount: Int,
    unchangedEventCount: Int,
    eventDifferences: [OfflineHIDTraceEventDifference],
    totalByteDifferenceCount: Int,
    detailsTruncated: Bool,
    hasDifferences: Bool
  ) {
    self.baselineEventCount = baselineEventCount
    self.candidateEventCount = candidateEventCount
    self.unchangedEventCount = unchangedEventCount
    self.eventDifferences = eventDifferences
    self.totalByteDifferenceCount = totalByteDifferenceCount
    self.detailsTruncated = detailsTruncated
    self.hasDifferences = hasDifferences
  }
}

public enum OfflineHIDTraceAnalyzer {
  public static func summary(_ trace: OfflineHIDTrace) -> OfflineHIDTraceSummary {
    let timestamps = trace.events.compactMap(\.offsetMicros)
    let firstTimestamp = timestamps.first
    let lastTimestamp = timestamps.last

    let directionCounts = OfflineHIDTraceDirection.allCases.compactMap { direction in
      let count = trace.events.count { $0.direction == direction }
      return count == 0 ? nil : OfflineHIDTraceDirectionCount(direction: direction, count: count)
    }
    let transferCounts = OfflineHIDTransferKind.allCases.compactMap { transfer in
      let count = trace.events.count { $0.transfer == transfer }
      return count == 0 ? nil : OfflineHIDTransferCount(transfer: transfer, count: count)
    }

    var reports: [UInt8: Int] = [:]
    for event in trace.events {
      reports[event.reportID, default: 0] += 1
    }
    let reportCounts = reports.keys.sorted().map { reportID in
      OfflineHIDReportIDCount(reportID: reportID, count: reports[reportID] ?? 0)
    }

    return OfflineHIDTraceSummary(
      schemaVersion: trace.schemaVersion,
      eventCount: trace.events.count,
      totalPayloadBytes: trace.events.reduce(0) { $0 + $1.bytes.count },
      durationMicros: duration(first: firstTimestamp, last: lastTimestamp),
      directionCounts: directionCounts,
      transferCounts: transferCounts,
      reportIDCounts: reportCounts
    )
  }

  public static func compare(
    _ baseline: OfflineHIDTrace,
    _ candidate: OfflineHIDTrace
  ) -> OfflineHIDTraceComparison {
    compare(
      baseline,
      candidate,
      maximumDetailedByteDifferences: 10_000
    )
  }

  static func compare(
    _ baseline: OfflineHIDTrace,
    _ candidate: OfflineHIDTrace,
    maximumDetailedByteDifferences: Int
  ) -> OfflineHIDTraceComparison {
    let detailLimit = max(0, maximumDetailedByteDifferences)
    let eventCount = max(baseline.events.count, candidate.events.count)
    var eventDifferences: [OfflineHIDTraceEventDifference] = []
    var unchangedEventCount = 0
    var totalByteDifferenceCount = 0
    var recordedByteDifferenceCount = 0

    for index in 0..<eventCount {
      let baselineEvent = baseline.events.indices.contains(index) ? baseline.events[index] : nil
      let candidateEvent = candidate.events.indices.contains(index) ? candidate.events[index] : nil

      if baselineEvent == candidateEvent {
        unchangedEventCount += 1
        continue
      }

      let kind: OfflineHIDTraceDifferenceKind
      switch (baselineEvent, candidateEvent) {
      case (nil, .some): kind = .added
      case (.some, nil): kind = .removed
      case (.some, .some): kind = .modified
      case (nil, nil): continue
      }

      let metadataChanges = changedMetadata(
        baseline: baselineEvent,
        candidate: candidateEvent
      )
      let byteResult = changedBytes(
        baseline: baselineEvent?.bytes ?? [],
        candidate: candidateEvent?.bytes ?? [],
        remainingDetailCapacity: max(0, detailLimit - recordedByteDifferenceCount)
      )
      totalByteDifferenceCount += byteResult.count
      recordedByteDifferenceCount += byteResult.details.count

      eventDifferences.append(
        OfflineHIDTraceEventDifference(
          index: index,
          kind: kind,
          metadataChanges: metadataChanges,
          baselinePayloadLength: baselineEvent?.bytes.count,
          candidatePayloadLength: candidateEvent?.bytes.count,
          byteDifferenceCount: byteResult.count,
          byteDifferences: byteResult.details
        ))
    }

    return OfflineHIDTraceComparison(
      baselineEventCount: baseline.events.count,
      candidateEventCount: candidate.events.count,
      unchangedEventCount: unchangedEventCount,
      eventDifferences: eventDifferences,
      totalByteDifferenceCount: totalByteDifferenceCount,
      detailsTruncated: recordedByteDifferenceCount < totalByteDifferenceCount,
      hasDifferences: !eventDifferences.isEmpty
    )
  }

  private static func duration(first: UInt64?, last: UInt64?) -> UInt64? {
    guard let first, let last, last >= first else { return nil }
    return last - first
  }

  private static func changedMetadata(
    baseline: OfflineHIDTraceEvent?,
    candidate: OfflineHIDTraceEvent?
  ) -> [OfflineHIDTraceMetadataField] {
    guard let baseline, let candidate else { return [] }
    var changes: [OfflineHIDTraceMetadataField] = []
    if baseline.offsetMicros != candidate.offsetMicros { changes.append(.offsetMicros) }
    if baseline.direction != candidate.direction { changes.append(.direction) }
    if baseline.transfer != candidate.transfer { changes.append(.transfer) }
    if baseline.reportID != candidate.reportID { changes.append(.reportID) }
    return changes
  }

  private static func changedBytes(
    baseline: [UInt8],
    candidate: [UInt8],
    remainingDetailCapacity: Int
  ) -> (count: Int, details: [OfflineHIDByteDifference]) {
    let byteCount = max(baseline.count, candidate.count)
    var count = 0
    var details: [OfflineHIDByteDifference] = []
    details.reserveCapacity(min(byteCount, remainingDetailCapacity))

    for offset in 0..<byteCount {
      let baselineByte = baseline.indices.contains(offset) ? baseline[offset] : nil
      let candidateByte = candidate.indices.contains(offset) ? candidate[offset] : nil
      guard baselineByte != candidateByte else { continue }
      count += 1
      if details.count < remainingDetailCapacity {
        details.append(OfflineHIDByteDifference(offset: offset))
      }
    }
    return (count, details)
  }
}
