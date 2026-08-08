public enum HIDRole: String, Codable, Equatable, Sendable {
  case keyboard
  case consumer
  case vendorFeature64 = "vendor-feature-64"
  case vendorOutput4096 = "vendor-output-4096"
  case unknown
}

public struct HIDCollectionDescriptor: Equatable, Sendable {
  public let usagePage: UInt64?
  public let usage: UInt64?
  public let maxInputReportSize: UInt64?
  public let maxOutputReportSize: UInt64?
  public let maxFeatureReportSize: UInt64?

  public init(
    usagePage: UInt64?,
    usage: UInt64?,
    maxInputReportSize: UInt64?,
    maxOutputReportSize: UInt64?,
    maxFeatureReportSize: UInt64?
  ) {
    self.usagePage = usagePage
    self.usage = usage
    self.maxInputReportSize = maxInputReportSize
    self.maxOutputReportSize = maxOutputReportSize
    self.maxFeatureReportSize = maxFeatureReportSize
  }
}

public enum HIDRoleClassifier {
  public static func classify(_ descriptor: HIDCollectionDescriptor) -> HIDRole {
    if descriptor.usagePage == 0x0001, descriptor.usage == 0x0006 {
      return .keyboard
    }

    if descriptor.usagePage == 0x000C, descriptor.usage == 0x0001 {
      return .consumer
    }

    if descriptor.usagePage == 0xFF13,
      descriptor.usage == 0x0001,
      descriptor.maxFeatureReportSize == 64
    {
      return .vendorFeature64
    }

    if descriptor.usagePage == 0xFF68,
      descriptor.usage == 0x0061,
      descriptor.maxOutputReportSize == 4_096
    {
      return .vendorOutput4096
    }

    return .unknown
  }
}
