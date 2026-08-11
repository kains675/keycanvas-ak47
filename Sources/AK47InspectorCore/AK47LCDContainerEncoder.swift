import Foundation

public enum AK47LCDPagePadding: UInt8, Equatable, Sendable {
  /// Matches an erased SPI flash byte and the Windows-style all-FF buffer.
  case erasedFlash = 0xFF
  /// Available only for deterministic compatibility experiments.
  case zero = 0x00
}

public struct AK47LCDContainerEncoderConfiguration: Equatable, Sendable {
  public var partitionBudgetByteCount: Int
  public var pagePadding: AK47LCDPagePadding

  public init(
    partitionBudgetByteCount: Int = AK47LCDFormat.maximumContainerByteCount,
    pagePadding: AK47LCDPagePadding = .erasedFlash
  ) {
    self.partitionBudgetByteCount = partitionBudgetByteCount
    self.pagePadding = pagePadding
  }
}

public struct AK47LCDEncodedContainer: Equatable, Sendable {
  public let data: Data
  public let frameCount: Int
  public let sourceDelaysMilliseconds: [Int]
  public let encodedDeviceDelays: [UInt8]
  public let nominalEncodedDelaysMilliseconds: [Int]
  public let effectiveDeviceDelaysMilliseconds: [Int]
  public let firmwareMinimumAppliedFrameIndices: [Int]
  public let unpaddedByteCount: Int
  public let pageCount: Int
  public let paddingByte: UInt8
  public let partitionBudgetByteCount: Int

  public var pages: [Data] {
    guard pageCount > 0 else { return [] }
    return (0..<pageCount).map { pageIndex in
      let start = pageIndex * AK47LCDFormat.transferPageByteCount
      return data.subdata(in: start..<(start + AK47LCDFormat.transferPageByteCount))
    }
  }
}

public enum AK47LCDContainerEncoder {
  public static func encode(
    project: AK47LCDAnimationProject,
    configuration: AK47LCDContainerEncoderConfiguration = .init()
  ) throws -> AK47LCDEncodedContainer {
    let frameCount = project.frames.count
    guard (1...AK47LCDFormat.maximumFrameCount).contains(frameCount) else {
      throw AK47LCDAnimationError.invalidFrameCount(frameCount)
    }
    let budget = configuration.partitionBudgetByteCount
    guard budget > 0,
      budget <= AK47LCDFormat.maximumContainerByteCount,
      budget.isMultiple(of: AK47LCDFormat.transferPageByteCount)
    else {
      throw AK47LCDAnimationError.invalidPartitionBudget(budget)
    }

    let (frameBytes, frameBytesOverflow) = AK47LCDFormat.rgb565FrameByteCount
      .multipliedReportingOverflow(by: frameCount)
    let (unpaddedBytes, unpaddedOverflow) = AK47LCDFormat.headerByteCount
      .addingReportingOverflow(frameBytes)
    guard !frameBytesOverflow, !unpaddedOverflow else {
      throw AK47LCDAnimationError.arithmeticOverflow
    }
    let pageSize = AK47LCDFormat.transferPageByteCount
    let (roundingNumerator, roundingOverflow) = unpaddedBytes.addingReportingOverflow(pageSize - 1)
    guard !roundingOverflow else { throw AK47LCDAnimationError.arithmeticOverflow }
    let pageCount = roundingNumerator / pageSize
    let (paddedBytes, paddedOverflow) = pageCount.multipliedReportingOverflow(by: pageSize)
    guard !paddedOverflow else { throw AK47LCDAnimationError.arithmeticOverflow }
    guard paddedBytes <= budget else {
      throw AK47LCDAnimationError.partitionBudgetExceeded(required: paddedBytes, budget: budget)
    }

    var deviceDelays: [AK47LCDDeviceDelay] = []
    deviceDelays.reserveCapacity(frameCount)
    for (index, frame) in project.frames.enumerated() {
      guard frame.image.width == AK47LCDFormat.canvasWidth,
        frame.image.height == AK47LCDFormat.canvasHeight
      else {
        throw AK47LCDAnimationError.invalidDimensions(
          width: frame.image.width,
          height: frame.image.height
        )
      }
      guard frame.image.isOpaque else {
        throw AK47LCDAnimationError.transparentDeviceFrame(frameIndex: index)
      }
      do {
        deviceDelays.append(try AK47LCDDeviceDelay(verifiedSourceDelay: frame.sourceDelay))
      } catch {
        throw AK47LCDAnimationError.sourceDelayNotDeviceEncodable(
          frameIndex: index,
          milliseconds: frame.sourceDelay.milliseconds
        )
      }
    }

    let paddingByte = configuration.pagePadding.rawValue
    var container = Data(repeating: paddingByte, count: paddedBytes)
    // Header padding is always FF, independently of the transport-page tail.
    container.replaceSubrange(
      0..<AK47LCDFormat.headerByteCount,
      with: repeatElement(UInt8(0xFF), count: AK47LCDFormat.headerByteCount)
    )
    container[0] = UInt8(frameCount)
    for (index, delay) in deviceDelays.enumerated() {
      container[index + 1] = delay.rawValue
    }

    container.withUnsafeMutableBytes { destinationBuffer in
      guard let destination = destinationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
      else { return }
      for (frameIndex, frame) in project.frames.enumerated() {
        let frameOffset =
          AK47LCDFormat.headerByteCount
          + (frameIndex * AK47LCDFormat.rgb565FrameByteCount)
        frame.image.pixels.withUnsafeBytes { sourceBuffer in
          guard let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return
          }
          let pixelCount = AK47LCDFormat.canvasWidth * AK47LCDFormat.canvasHeight
          for pixelIndex in 0..<pixelCount {
            let sourceOffset = pixelIndex * 4
            let red = UInt16(source[sourceOffset] >> 3)
            let green = UInt16(source[sourceOffset + 1] >> 2)
            let blue = UInt16(source[sourceOffset + 2] >> 3)
            let rgb565 = (red << 11) | (green << 5) | blue
            let destinationOffset = frameOffset + (pixelIndex * 2)
            destination[destinationOffset] = UInt8(truncatingIfNeeded: rgb565)
            destination[destinationOffset + 1] = UInt8(truncatingIfNeeded: rgb565 >> 8)
          }
        }
      }
    }

    return AK47LCDEncodedContainer(
      data: container,
      frameCount: frameCount,
      sourceDelaysMilliseconds: project.frames.map(\.sourceDelay.milliseconds),
      encodedDeviceDelays: deviceDelays.map(\.rawValue),
      nominalEncodedDelaysMilliseconds: deviceDelays.map(\.nominalMilliseconds),
      effectiveDeviceDelaysMilliseconds: deviceDelays.map(\.effectiveFirmwareMilliseconds),
      firmwareMinimumAppliedFrameIndices: deviceDelays.enumerated().compactMap {
        $0.element.usesFirmwareMinimum ? $0.offset : nil
      },
      unpaddedByteCount: unpaddedBytes,
      pageCount: pageCount,
      paddingByte: paddingByte,
      partitionBudgetByteCount: budget
    )
  }
}
