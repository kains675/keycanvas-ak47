import Foundation

/// A deliberately asymmetric, one-frame fixture for the first live LCD experiment.
///
/// The four colored corners make horizontal/vertical mirroring, channel swaps,
/// byte order mistakes, and cropping visible without relying on text rendering.
/// It is a fixed protocol fixture rather than a user-editable animation.
public enum AK47LCDDiagnosticFixture {
  public static let cornerSize = 32
  public static let sourceDelayMilliseconds = 100
  public static let expectedDeviceDelayRawValue: UInt8 = 0x32
  public static let expectedPageCount = 16
  public static let expectedContainerByteCount = 65_536
  public static let expectedPaddingByteCount = 480
  public static let expectedContainerSHA256 =
    "312f98fd023d49711f73a677895b1bf48ac246c7dd687c813ed5642f42128bec"

  public static let topLeftColor = AK47LCDRGBAColor(red: 255, green: 0, blue: 0)
  public static let topRightColor = AK47LCDRGBAColor(red: 0, green: 255, blue: 0)
  public static let bottomLeftColor = AK47LCDRGBAColor(red: 0, green: 0, blue: 255)
  public static let bottomRightColor = AK47LCDRGBAColor.white

  public static func makeImage() throws -> AK47LCDRGBAImage {
    let width = AK47LCDFormat.canvasWidth
    let height = AK47LCDFormat.canvasHeight
    var pixels = Data(count: width * height * AK47LCDFormat.rgbaBytesPerPixel)

    pixels.withUnsafeMutableBytes { rawBuffer in
      guard let destination = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }
      for y in 0..<height {
        for x in 0..<width {
          let color: AK47LCDRGBAColor
          if y < cornerSize, x < cornerSize {
            color = topLeftColor
          } else if y < cornerSize, x >= width - cornerSize {
            color = topRightColor
          } else if y >= height - cornerSize, x < cornerSize {
            color = bottomLeftColor
          } else if y >= height - cornerSize, x >= width - cornerSize {
            color = bottomRightColor
          } else {
            color = .black
          }

          let offset = ((y * width) + x) * AK47LCDFormat.rgbaBytesPerPixel
          destination[offset] = color.red
          destination[offset + 1] = color.green
          destination[offset + 2] = color.blue
          destination[offset + 3] = color.alpha
        }
      }
    }

    return try AK47LCDRGBAImage(width: width, height: height, pixels: pixels)
  }

  public static func makeProject() throws -> AK47LCDAnimationProject {
    let frame = try AK47LCDAnimationFrame(
      image: makeImage(),
      sourceDelay: AK47LCDSourceDelay(milliseconds: sourceDelayMilliseconds)
    )
    return try AK47LCDAnimationProject(frames: [frame])
  }

  public static func encode() throws -> AK47LCDEncodedContainer {
    try AK47LCDContainerEncoder.encode(
      project: makeProject(),
      configuration: AK47LCDContainerEncoderConfiguration(
        partitionBudgetByteCount: expectedContainerByteCount,
        pagePadding: .erasedFlash
      )
    )
  }
}
