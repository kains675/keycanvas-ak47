public struct HIDCollectionRecord: Codable, Equatable, Sendable {
  public let vendorID: UInt64
  public let productID: UInt64
  public let product: String?
  public let manufacturer: String?
  public let serialNumber: String?
  public let transport: String?
  public let locationID: UInt64?
  public let usagePage: UInt64?
  public let usage: UInt64?
  public let maxInputReportSize: UInt64?
  public let maxOutputReportSize: UInt64?
  public let maxFeatureReportSize: UInt64?
  public let role: HIDRole

  public init(
    vendorID: UInt64,
    productID: UInt64,
    product: String?,
    manufacturer: String?,
    serialNumber: String? = nil,
    transport: String?,
    locationID: UInt64?,
    usagePage: UInt64?,
    usage: UInt64?,
    maxInputReportSize: UInt64?,
    maxOutputReportSize: UInt64?,
    maxFeatureReportSize: UInt64?
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.manufacturer = manufacturer
    self.serialNumber = serialNumber
    self.transport = transport
    self.locationID = locationID
    self.usagePage = usagePage
    self.usage = usage
    self.maxInputReportSize = maxInputReportSize
    self.maxOutputReportSize = maxOutputReportSize
    self.maxFeatureReportSize = maxFeatureReportSize
    self.role = HIDRoleClassifier.classify(
      HIDCollectionDescriptor(
        usagePage: usagePage,
        usage: usage,
        maxInputReportSize: maxInputReportSize,
        maxOutputReportSize: maxOutputReportSize,
        maxFeatureReportSize: maxFeatureReportSize
      )
    )
  }
}
