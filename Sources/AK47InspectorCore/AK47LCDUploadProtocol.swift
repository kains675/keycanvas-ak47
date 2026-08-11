import Foundation

public enum AK47LCDUploadStage: Equatable, Sendable {
  case begin
  case selectUpload
  case page(Int)
  case commit

  package var description: String {
    switch self {
    case .begin: "begin"
    case .selectUpload: "LCD upload selector"
    case .page(let index): "LCD page \(index + 1)"
    case .commit: "commit"
    }
  }
}

public enum AK47LCDUploadError: Error, Equatable, LocalizedError, Sendable {
  case invalidFrameCount(Int)
  case invalidPageCount(Int)
  case containerLengthMismatch(expected: Int, actual: Int)
  case unpaddedLengthMismatch(expected: Int, actual: Int)
  case headerFrameCountMismatch(expected: Int, actual: Int)
  case delayMetadataMismatch
  case headerDelayMismatch(frameIndex: Int)
  case headerPaddingMismatch(offset: Int)
  case unsupportedPagePadding(UInt8)
  case pagePaddingMismatch(offset: Int)
  case partitionBudgetMismatch
  case transferAddressOverflow
  case transferEndExceedsSoftwareLimit(end: UInt64, limit: UInt64)
  case outputReportIDMismatch(stage: AK47LCDUploadStage, actual: UInt8)
  case acknowledgementRejected(stage: AK47LCDUploadStage)
  case invalidReportLength(stage: AK47LCDUploadStage, expected: Int, actual: Int)
  case operationTimedOut(stage: AK47LCDUploadStage)

  public var errorDescription: String? {
    switch self {
    case .invalidFrameCount(let count):
      "LCD uploads require 1...140 frames; got \(count)."
    case .invalidPageCount(let count):
      "LCD upload page count must be 1...2215; got \(count)."
    case .containerLengthMismatch(let expected, let actual):
      "LCD container length mismatch; expected \(expected), got \(actual)."
    case .unpaddedLengthMismatch(let expected, let actual):
      "LCD unpadded length mismatch; expected \(expected), got \(actual)."
    case .headerFrameCountMismatch(let expected, let actual):
      "LCD header frame count mismatch; expected \(expected), got \(actual)."
    case .delayMetadataMismatch:
      "LCD delay metadata does not contain exactly one entry per frame."
    case .headerDelayMismatch(let frameIndex):
      "LCD header delay differs from the encoded delay for frame \(frameIndex + 1)."
    case .headerPaddingMismatch(let offset):
      "LCD header padding is not 0xFF at byte \(offset)."
    case .unsupportedPagePadding(let value):
      String(format: "The modeled LCD transfer requires 0xFF page padding; got 0x%02X.", value)
    case .pagePaddingMismatch(let offset):
      "LCD transfer padding is not 0xFF at byte \(offset)."
    case .partitionBudgetMismatch:
      "LCD container and partition budget metadata are inconsistent."
    case .transferAddressOverflow:
      "LCD transfer address calculation overflowed."
    case .transferEndExceedsSoftwareLimit(let end, let limit):
      String(
        format: "LCD transfer end 0x%llX exceeds software ceiling 0x%llX.",
        end,
        limit
      )
    case .outputReportIDMismatch(let stage, let actual):
      "AK47 \(stage.description) returned unexpected report ID \(actual)."
    case .acknowledgementRejected(let stage):
      "AK47 \(stage.description) acknowledgement was rejected."
    case .invalidReportLength(let stage, let expected, let actual):
      "AK47 \(stage.description) length mismatch; expected \(expected), got \(actual)."
    case .operationTimedOut(let stage):
      "AK47 \(stage.description) exceeded the bounded timeout."
    }
  }
}

public enum AK47LCDUploadRisk: String, Equatable, Sendable {
  case unverifiedPhysicalPartitionEnd
  case noVerifiedReadbackOrRecovery
}

public struct AK47LCDUploadPlan: Equatable, Sendable {
  public let target: AK47WiredDeviceTarget
  public let container: AK47LCDEncodedContainer

  /// The 140-frame ceiling is known from host behavior, not a physical SPI
  /// partition boundary. The live adapter independently pins this ceiling to a
  /// policy revision and requires the exact one-frame diagnostic plus the
  /// maximum-boundary qualification sequence before ordinary uploads unlock.
  public var physicalPartitionEndVerified: Bool { false }
  public var unresolvedRisks: [AK47LCDUploadRisk] {
    [.unverifiedPhysicalPartitionEnd, .noVerifiedReadbackOrRecovery]
  }

  package init(
    target: AK47WiredDeviceTarget,
    container: AK47LCDEncodedContainer
  ) {
    self.target = target
    self.container = container
  }
}

public enum AK47LCDUploadPreflight {
  public static let externalFlashStartAddress: UInt64 = 0x74_0000
  /// Base + the vendor UI's 140-frame host-side budget. This is not a verified
  /// physical flash partition end or a recovery boundary.
  public static let softwareTransferEndLimit: UInt64 = 0xFE_7000
  public static let maximumPageCount = 2_215

  public static func makeSyntheticPlan(
    target: AK47WiredDeviceTarget,
    container: AK47LCDEncodedContainer
  ) throws -> AK47LCDUploadPlan {
    try target.validate()
    let plan = AK47LCDUploadPlan(
      target: target,
      container: container
    )
    try validateStructuralModel(plan)
    return plan
  }

  package static func validateStructuralModel(_ plan: AK47LCDUploadPlan) throws {
    try plan.target.validate()
    let container = plan.container
    guard (1...AK47LCDFormat.maximumFrameCount).contains(container.frameCount) else {
      throw AK47LCDUploadError.invalidFrameCount(container.frameCount)
    }
    guard (1...maximumPageCount).contains(container.pageCount) else {
      throw AK47LCDUploadError.invalidPageCount(container.pageCount)
    }

    let (expectedLength, lengthOverflow) = container.pageCount.multipliedReportingOverflow(
      by: AK47LCDFormat.transferPageByteCount)
    guard !lengthOverflow else { throw AK47LCDUploadError.transferAddressOverflow }
    guard container.data.count == expectedLength else {
      throw AK47LCDUploadError.containerLengthMismatch(
        expected: expectedLength,
        actual: container.data.count
      )
    }
    guard container.pages.count == container.pageCount else {
      throw AK47LCDUploadError.invalidPageCount(container.pages.count)
    }

    let (frameBytes, frameOverflow) = container.frameCount.multipliedReportingOverflow(
      by: AK47LCDFormat.rgb565FrameByteCount)
    let (expectedUnpadded, unpaddedOverflow) = AK47LCDFormat.headerByteCount
      .addingReportingOverflow(frameBytes)
    guard !frameOverflow, !unpaddedOverflow else {
      throw AK47LCDUploadError.transferAddressOverflow
    }
    guard container.unpaddedByteCount == expectedUnpadded else {
      throw AK47LCDUploadError.unpaddedLengthMismatch(
        expected: expectedUnpadded,
        actual: container.unpaddedByteCount
      )
    }
    guard expectedUnpadded <= expectedLength else {
      throw AK47LCDUploadError.containerLengthMismatch(
        expected: expectedLength,
        actual: expectedUnpadded
      )
    }
    guard Int(container.data[0]) == container.frameCount else {
      throw AK47LCDUploadError.headerFrameCountMismatch(
        expected: container.frameCount,
        actual: Int(container.data[0])
      )
    }

    let delayCounts = [
      container.sourceDelaysMilliseconds.count,
      container.encodedDeviceDelays.count,
      container.nominalEncodedDelaysMilliseconds.count,
      container.effectiveDeviceDelaysMilliseconds.count,
    ]
    guard delayCounts.allSatisfy({ $0 == container.frameCount }) else {
      throw AK47LCDUploadError.delayMetadataMismatch
    }
    for frameIndex in 0..<container.frameCount {
      guard container.data[frameIndex + 1] == container.encodedDeviceDelays[frameIndex] else {
        throw AK47LCDUploadError.headerDelayMismatch(frameIndex: frameIndex)
      }
    }
    let headerPaddingStart = container.frameCount + 1
    if headerPaddingStart < AK47LCDFormat.headerByteCount {
      for offset in headerPaddingStart..<AK47LCDFormat.headerByteCount
      where container.data[offset] != 0xFF {
        throw AK47LCDUploadError.headerPaddingMismatch(offset: offset)
      }
    }

    guard container.paddingByte == 0xFF else {
      throw AK47LCDUploadError.unsupportedPagePadding(container.paddingByte)
    }
    if expectedUnpadded < expectedLength {
      for offset in expectedUnpadded..<expectedLength where container.data[offset] != 0xFF {
        throw AK47LCDUploadError.pagePaddingMismatch(offset: offset)
      }
    }
    guard container.partitionBudgetByteCount >= expectedLength,
      container.partitionBudgetByteCount <= AK47LCDFormat.maximumContainerByteCount,
      container.partitionBudgetByteCount.isMultiple(of: AK47LCDFormat.transferPageByteCount)
    else {
      throw AK47LCDUploadError.partitionBudgetMismatch
    }

    let (transferBytes, transferOverflow) = UInt64(container.pageCount)
      .multipliedReportingOverflow(by: UInt64(AK47LCDFormat.transferPageByteCount))
    let (transferEnd, addressOverflow) =
      externalFlashStartAddress
      .addingReportingOverflow(transferBytes)
    guard !transferOverflow, !addressOverflow else {
      throw AK47LCDUploadError.transferAddressOverflow
    }
    guard transferEnd <= softwareTransferEndLimit else {
      throw AK47LCDUploadError.transferEndExceedsSoftwareLimit(
        end: transferEnd,
        limit: softwareTransferEndLimit
      )
    }
  }
}

package struct AK47LCDInputAcknowledgement: Equatable, Sendable {
  let reportID: UInt8
  let bytes: [UInt8]
}

package protocol AK47LCDUploadSession: AnyObject {
  func setFeature(_ bytes: [UInt8], stage: AK47LCDUploadStage) throws
  func getFeature(expectedLength: Int, stage: AK47LCDUploadStage) throws -> [UInt8]
  func setOutput(_ bytes: [UInt8], reportID: UInt8, stage: AK47LCDUploadStage) throws
  func getInputAcknowledgement(stage: AK47LCDUploadStage) throws
    -> AK47LCDInputAcknowledgement
}

package enum AK47LCDUploadStateMachine {
  package typealias Sleep = (_ milliseconds: UInt32) -> Void

  package static let featureReportLength = 64
  package static let outputReportLength = AK47LCDFormat.transferPageByteCount
  package static let reportID: UInt8 = 0
  package static let commandDelayMilliseconds: UInt32 = 35

  package static func execute(
    plan: AK47LCDUploadPlan,
    session: any AK47LCDUploadSession,
    sleep: Sleep,
    progress: (_ completedPages: Int, _ totalPages: Int) -> Void = { _, _ in }
  ) throws {
    try AK47LCDUploadPreflight.validateStructuralModel(plan)

    try featureCommand(beginPayload, stage: .begin, session: session, sleep: sleep)
    try featureCommand(
      selectorPayload(pageCount: plan.container.pageCount),
      stage: .selectUpload,
      session: session,
      sleep: sleep
    )

    for (index, page) in plan.container.pages.enumerated() {
      let stage = AK47LCDUploadStage.page(index)
      let bytes = Array(page)
      guard bytes.count == outputReportLength else {
        throw AK47LCDUploadError.invalidReportLength(
          stage: stage,
          expected: outputReportLength,
          actual: bytes.count
        )
      }
      try session.setOutput(bytes, reportID: reportID, stage: stage)
      let acknowledgement = try session.getInputAcknowledgement(stage: stage)
      guard acknowledgement.reportID == reportID else {
        throw AK47LCDUploadError.outputReportIDMismatch(
          stage: stage,
          actual: acknowledgement.reportID
        )
      }
      guard acknowledgement.bytes.count == featureReportLength else {
        throw AK47LCDUploadError.invalidReportLength(
          stage: stage,
          expected: featureReportLength,
          actual: acknowledgement.bytes.count
        )
      }
      guard acknowledgement.bytes.starts(with: [0x01, 0x5A, 0x02]) else {
        throw AK47LCDUploadError.acknowledgementRejected(stage: stage)
      }
      progress(index + 1, plan.container.pageCount)
    }

    try featureCommand(commitPayload, stage: .commit, session: session, sleep: sleep)
    sleep(commandDelayMilliseconds)
  }

  package static var beginPayload: [UInt8] { commandPayload(0x18) }
  package static var commitPayload: [UInt8] { commandPayload(0x02) }

  /// Byte 2 is ignored by the v1.16 handler. Keep the Windows default value as
  /// a reserved transport byte; it does not select one of several LCD slots.
  package static func selectorPayload(pageCount: Int) -> [UInt8] {
    var payload = commandPayload(0x72)
    payload[2] = 1
    payload[8] = UInt8(truncatingIfNeeded: pageCount)
    payload[9] = UInt8(truncatingIfNeeded: pageCount >> 8)
    return payload
  }

  private static func commandPayload(_ command: UInt8) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: featureReportLength)
    payload[0] = 0x04
    payload[1] = command
    return payload
  }

  private static func featureCommand(
    _ payload: [UInt8],
    stage: AK47LCDUploadStage,
    session: any AK47LCDUploadSession,
    sleep: Sleep
  ) throws {
    guard payload.count == featureReportLength else {
      throw AK47LCDUploadError.invalidReportLength(
        stage: stage,
        expected: featureReportLength,
        actual: payload.count
      )
    }
    sleep(commandDelayMilliseconds)
    try session.setFeature(payload, stage: stage)
    sleep(commandDelayMilliseconds)
    let acknowledgement = try session.getFeature(
      expectedLength: featureReportLength,
      stage: stage
    )
    guard acknowledgement.count == featureReportLength else {
      throw AK47LCDUploadError.invalidReportLength(
        stage: stage,
        expected: featureReportLength,
        actual: acknowledgement.count
      )
    }
    guard acknowledgement[0] == payload[0],
      acknowledgement[1] == payload[1],
      acknowledgement[2] == payload[2],
      acknowledgement[3] == 0x01
    else {
      throw AK47LCDUploadError.acknowledgementRejected(stage: stage)
    }
    if stage == .selectUpload {
      guard acknowledgement[8] == payload[8],
        acknowledgement[9] == payload[9]
      else {
        throw AK47LCDUploadError.acknowledgementRejected(stage: stage)
      }
    }
    if stage == .commit {
      // The completion handler defines bytes 4...7 as the little-endian
      // running byte sum. LCD page transfers do not contribute to that sum,
      // so the fixed LCD path must complete with exactly zero here. Remaining
      // reserved/tail bytes are intentionally not interpreted.
      guard acknowledgement[4...7].allSatisfy({ $0 == 0 }) else {
        throw AK47LCDUploadError.acknowledgementRejected(stage: stage)
      }
    }
  }
}
