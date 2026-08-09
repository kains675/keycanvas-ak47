import Foundation

public enum OfflineHIDTraceCodec {
  public static func decode(_ data: Data) throws -> OfflineHIDTrace {
    guard data.count <= OfflineHIDTraceValidator.maximumDocumentBytes else {
      throw OfflineHIDTraceError.documentTooLarge(
        maximum: OfflineHIDTraceValidator.maximumDocumentBytes,
        actual: data.count
      )
    }
    return try JSONDecoder().decode(OfflineHIDTrace.self, from: data)
  }
}
