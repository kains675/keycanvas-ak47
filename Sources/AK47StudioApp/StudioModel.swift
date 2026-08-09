import AK47InspectorCore
import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case korean
  case english

  var id: Self { self }
  var label: String { self == .korean ? "한국어" : "English" }
}

enum StudioSection: String, CaseIterable, Identifiable {
  case dashboard
  case keymap
  case lighting
  case macros
  case display
  case settings
  case deviceInspector

  var id: Self { self }

  func title(in language: AppLanguage) -> String {
    if language == .english {
      switch self {
      case .dashboard: "Dashboard"
      case .keymap: "Keymap"
      case .lighting: "Lighting"
      case .macros: "Macros"
      case .display: "Display"
      case .settings: "Settings"
      case .deviceInspector: "Device Inspector"
      }
    } else {
      switch self {
      case .dashboard: "대시보드"
      case .keymap: "키맵"
      case .lighting: "조명"
      case .macros: "매크로"
      case .display: "디스플레이"
      case .settings: "설정"
      case .deviceInspector: "장치 검사기"
      }
    }
  }

  func subtitle(in language: AppLanguage) -> String {
    if language == .english {
      switch self {
      case .dashboard: "Workspace overview"
      case .keymap: "Explore a draft layout"
      case .lighting: "Build a color scene"
      case .macros: "Arrange local actions"
      case .display: "Compose a screen mockup"
      case .settings: "App preferences"
      case .deviceInspector: "HID diagnostics and bounded RGB query"
      }
    } else {
      switch self {
      case .dashboard: "작업 공간 한눈에 보기"
      case .keymap: "키 배치 초안 만들기"
      case .lighting: "색상 장면 구성하기"
      case .macros: "로컬 동작 배열하기"
      case .display: "화면 시안 만들기"
      case .settings: "앱 환경 설정"
      case .deviceInspector: "HID 진단과 제한적 RGB 조회"
      }
    }
  }

  var symbol: String {
    switch self {
    case .dashboard: "rectangle.grid.1x2"
    case .keymap: "keyboard"
    case .lighting: "lightbulb"
    case .macros: "waveform"
    case .display: "display"
    case .settings: "gearshape"
    case .deviceInspector: "doc.text.magnifyingglass"
    }
  }
}

enum InspectorState: Equatable {
  case idle
  case scanning
  case ready
  case failed(String)
}

enum DeviceReadProbeState: Equatable {
  case idle
  case reading
  case ready(DeviceReadProbeSnapshot)
  case failed(String)
}

enum PerKeyRGBQueryState: Equatable {
  case idle
  case reading
  case ready(AK47PerKeyRGBSnapshot)
  case failed(String)
}

enum DeviceWriteState: Equatable {
  case idle
  case writing(AK47DeviceWriteKind)
  case succeeded(AK47DeviceWriteKind, Date)
  case failed(AK47DeviceWriteKind, String)
}

struct DeviceReadProbeSnapshot: Equatable, Sendable {
  let featureLength: Int
  let featureNonzeroByteCount: Int
  let bulkOutputResult: DeviceReadProbeOutcome
}

enum DeviceReadProbeOutcome: Equatable, Sendable {
  case read(length: Int, nonzeroByteCount: Int)
  case unavailable(String)
}

protocol HIDCollectionProviding {
  func collections() throws -> [HIDCollectionRecord]
}

struct SystemHIDCollectionProvider: HIDCollectionProviding {
  func collections() throws -> [HIDCollectionRecord] {
    try HIDEnumerator.enumerate()
  }
}

struct PreviewHIDCollectionProvider: HIDCollectionProviding {
  var records: [HIDCollectionRecord] = .keyCanvasPreview

  func collections() throws -> [HIDCollectionRecord] {
    records
  }
}

@MainActor
final class StudioModel: ObservableObject {
  @Published var selection: StudioSection
  @Published var language: AppLanguage
  @Published private(set) var collections: [HIDCollectionRecord] = []
  @Published private(set) var inspectorState: InspectorState = .idle
  @Published private(set) var deviceReadProbeState: DeviceReadProbeState = .idle
  @Published private(set) var perKeyRGBQueryState: PerKeyRGBQueryState = .idle
  @Published private(set) var deviceWriteState: DeviceWriteState = .idle
  @Published private(set) var lastScan: Date?

  let demoMode = true
  let profileStore: LocalProfileStore
  private let provider: any HIDCollectionProviding

  init(
    provider: any HIDCollectionProviding = SystemHIDCollectionProvider(),
    profileStore: LocalProfileStore? = nil,
    userDefaults: UserDefaults = .standard
  ) {
    self.provider = provider
    self.profileStore = profileStore ?? LocalProfileStore()

    language =
      AppLanguage(
        rawValue: userDefaults.string(forKey: "appLanguage") ?? ""
      ) ?? .korean

    let reopensLastSection = userDefaults.object(forKey: "reopenLastSection") as? Bool ?? true
    if reopensLastSection,
      let rawSection = userDefaults.string(forKey: "lastStudioSection"),
      let section = StudioSection(rawValue: rawSection)
    {
      selection = section
    } else {
      selection = .dashboard
    }
  }

  var isConnected: Bool { !collections.isEmpty }

  var deviceName: String {
    collections.compactMap(\.product).first ?? "Archon AK47"
  }

  func connectionLabel(in language: AppLanguage) -> String {
    switch inspectorState {
    case .scanning: studioText("검사 중", "Scanning", language: language)
    case .failed: studioText("사용 불가", "Unavailable", language: language)
    case .idle, .ready:
      isConnected
        ? studioText("감지됨", "Detected", language: language)
        : studioText("감지되지 않음", "Not detected", language: language)
    }
  }

  func refreshInspector() {
    guard canRefreshInspector else { return }
    inspectorState = .scanning
    deviceReadProbeState = .idle
    perKeyRGBQueryState = .idle
    deviceWriteState = .idle

    do {
      collections = try provider.collections()
      inspectorState = .ready
    } catch {
      collections = []
      inspectorState = .failed(error.localizedDescription)
    }

    lastScan = Date()
  }

  var canRunPerKeyRGBQuery: Bool {
    perKeyRGBQueryRequest != nil && !isDeviceOperationInFlight
  }

  var canRunReadOnlyReportProbe: Bool {
    readProbeIdentity != nil && !isDeviceOperationInFlight
  }

  var canRefreshInspector: Bool {
    inspectorState != .scanning && !isDeviceOperationInFlight
  }

  var canSynchronizeClock: Bool {
    verifiedWiredTarget != nil && !isDeviceOperationInFlight
  }

  var canApplyLighting: Bool {
    verifiedWiredTarget != nil && !isDeviceOperationInFlight
  }

  private var isDeviceOperationInFlight: Bool {
    if case .writing = deviceWriteState { return true }
    return perKeyRGBQueryState == .reading || deviceReadProbeState == .reading
  }

  func synchronizeClockNow(lcdItemNumber: UInt8 = 1) {
    let value: AK47ClockSyncValue
    do {
      value = try AK47ClockSyncValue(date: Date(), lcdItemNumber: lcdItemNumber)
    } catch {
      deviceWriteState = .failed(.clockSync, error.localizedDescription)
      return
    }
    runDeviceWrite(kind: .clockSync) { target in
      try AK47DeviceWriteAdapter.synchronizeClock(
        target: target,
        value: value,
        authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .clockSync)
      )
    }
  }

  func applyOnboardLighting(_ value: AK47OnboardLightingValue) {
    runDeviceWrite(kind: .onboardLighting) { target in
      try AK47DeviceWriteAdapter.applyOnboardLighting(
        target: target,
        value: value,
        authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .onboardLighting)
      )
    }
  }

  func applyPerKeyRGB(brightness: UInt8, values: [AK47PerKeyRGBValue]) {
    runDeviceWrite(kind: .perKeyRGB) { target in
      try AK47DeviceWriteAdapter.applyPerKeyRGB(
        target: target,
        brightness: brightness,
        values: values,
        authorization: AK47DeviceWriteAuthorization(explicitlyConfirming: .perKeyRGB)
      )
    }
  }

  private func runDeviceWrite(
    kind: AK47DeviceWriteKind,
    operation: @escaping @Sendable (AK47WiredDeviceTarget) throws -> Void
  ) {
    guard !isDeviceOperationInFlight else { return }
    guard let target = verifiedWiredTarget else {
      deviceWriteState = .failed(
        kind,
        studioText(
          "검증된 유선 AK47 revision 0x0115와 정확한 4개 HID collection을 찾지 못했습니다.",
          "The verified wired AK47 revision 0x0115 with its exact four HID collections was not found.",
          language: language
        )
      )
      return
    }

    deviceWriteState = .writing(kind)
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        do {
          try operation(target)
          return Optional<String>.none
        } catch {
          return Optional(error.localizedDescription)
        }
      }.value

      if let result {
        deviceWriteState = .failed(kind, result)
      } else {
        deviceWriteState = .succeeded(kind, Date())
      }
    }
  }

  /// Runs the single verified RGB readback transaction after explicit UI confirmation.
  /// The result remains in memory and is never copied into a profile automatically.
  func runPerKeyRGBQueryOnce() {
    guard !isDeviceOperationInFlight else { return }
    guard let request = perKeyRGBQueryRequest else {
      perKeyRGBQueryState = .failed(
        studioText(
          "검증된 유선 AK47 revision 0x0115 설정 채널을 정확히 하나 찾지 못했습니다.",
          "A single verified wired AK47 revision 0x0115 command channel was not found.",
          language: language
        )
      )
      return
    }

    perKeyRGBQueryState = .reading
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result { try AK47PerKeyRGBQueryAdapter.query(request) }
      }.value

      switch result {
      case .success(let snapshot):
        perKeyRGBQueryState = .ready(snapshot)
      case .failure(let error):
        perKeyRGBQueryState = .failed(error.localizedDescription)
      }
    }
  }

  /// Opens only the two exact vendor collections and performs GetReport.
  /// No request selector, SetReport, output write, retry, or persistence occurs.
  func runReadOnlyReportProbe() {
    guard !isDeviceOperationInFlight else { return }
    guard let identity = readProbeIdentity else {
      deviceReadProbeState = .failed(
        studioText(
          "정확히 일치하는 단일 유선 AK47을 찾지 못했습니다.",
          "A single, exact wired AK47 match was not found.",
          language: language
        )
      )
      return
    }

    deviceReadProbeState = .reading
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result { try Self.performReadOnlyProbe(identity: identity) }
      }.value

      switch result {
      case .success(let snapshot):
        deviceReadProbeState = .ready(snapshot)
      case .failure(let error):
        deviceReadProbeState = .failed(error.localizedDescription)
      }
    }
  }

  private var readProbeIdentity: ReadProbeIdentity? {
    let groups = HIDPhysicalDeviceGrouper.group(collections)
    let exact = groups.filter { group in
      group.identifier.vendorID == HIDEnumerator.vendorID
        && group.identifier.productID == HIDEnumerator.productID
        && group.collections.contains(where: { $0.product == "Archon AK47" })
        && group.candidates.command.count == 1
        && group.candidates.bulkOutput.count == 1
    }
    guard exact.count == 1, let group = exact.first else { return nil }
    return ReadProbeIdentity(
      product: "Archon AK47",
      locationID: group.identifier.locationID
    )
  }

  private var perKeyRGBQueryRequest: AK47PerKeyRGBQueryRequest? {
    let commandRecords = collections.filter { record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == "Archon AK47"
        && record.transport == "USB"
        && record.versionNumber == 0x0115
        && record.usagePage == 0xFF13
        && record.usage == 0x0001
        && record.maxInputReportSize == 64
        && record.maxOutputReportSize == 64
        && record.maxFeatureReportSize == 64
    }
    guard commandRecords.count == 1,
      let record = commandRecords.first,
      let locationID = record.locationID
    else {
      return nil
    }
    return AK47PerKeyRGBQueryRequest(
      locationID: locationID,
      versionNumber: 0x0115
    )
  }

  private var verifiedWiredTarget: AK47WiredDeviceTarget? {
    let commandRecords = collections.filter { record in
      record.vendorID == HIDEnumerator.vendorID
        && record.productID == HIDEnumerator.productID
        && record.product == "Archon AK47"
        && record.transport == "USB"
        && record.versionNumber == 0x0115
        && record.usagePage == 0xFF13
        && record.usage == 0x0001
        && record.maxInputReportSize == 64
        && record.maxOutputReportSize == 64
        && record.maxFeatureReportSize == 64
    }
    guard commandRecords.count == 1,
      let command = commandRecords.first,
      let locationID = command.locationID
    else {
      return nil
    }
    let samePhysicalDevice = collections.filter { record in
      record.vendorID == command.vendorID
        && record.productID == command.productID
        && record.product == command.product
        && record.transport == command.transport
        && record.versionNumber == command.versionNumber
        && record.locationID == locationID
    }
    guard samePhysicalDevice.count == 4 else { return nil }
    return AK47WiredDeviceTarget(
      locationID: locationID,
      versionNumber: 0x0115
    )
  }

  nonisolated private static func performReadOnlyProbe(
    identity: ReadProbeIdentity
  ) throws -> DeviceReadProbeSnapshot {
    let feature = try HIDReadOnlyReportReader.read(
      HIDReadOnlyReportRequest(
        vendorID: HIDEnumerator.vendorID,
        productID: HIDEnumerator.productID,
        product: identity.product,
        locationID: identity.locationID,
        usagePage: 0xFF13,
        usage: 0x0001,
        reportType: .feature,
        reportID: 0,
        expectedLength: 64
      )
    )

    let outputOutcome: DeviceReadProbeOutcome
    do {
      let output = try HIDReadOnlyReportReader.read(
        HIDReadOnlyReportRequest(
          vendorID: HIDEnumerator.vendorID,
          productID: HIDEnumerator.productID,
          product: identity.product,
          locationID: identity.locationID,
          usagePage: 0xFF68,
          usage: 0x0061,
          reportType: .output,
          reportID: 0,
          expectedLength: 4_096
        )
      )
      outputOutcome = .read(
        length: output.bytes.count,
        nonzeroByteCount: output.bytes.filter { $0 != 0 }.count
      )
    } catch {
      outputOutcome = .unavailable(error.localizedDescription)
    }

    return DeviceReadProbeSnapshot(
      featureLength: feature.bytes.count,
      featureNonzeroByteCount: feature.bytes.filter { $0 != 0 }.count,
      bulkOutputResult: outputOutcome
    )
  }
}

private struct ReadProbeIdentity: Equatable, Sendable {
  let product: String
  let locationID: UInt64?
}

extension Array where Element == HIDCollectionRecord {
  static var keyCanvasPreview: [HIDCollectionRecord] {
    [
      HIDCollectionRecord(
        vendorID: 0x0C45,
        productID: 0x800A,
        product: "Archon AK47",
        manufacturer: "SONiX",
        transport: "USB",
        versionNumber: 0x0115,
        locationID: 0x0014_0000,
        usagePage: 0x0001,
        usage: 0x0006,
        maxInputReportSize: 8,
        maxOutputReportSize: 1,
        maxFeatureReportSize: 0
      ),
      HIDCollectionRecord(
        vendorID: 0x0C45,
        productID: 0x800A,
        product: "Archon AK47",
        manufacturer: "SONiX",
        transport: "USB",
        versionNumber: 0x0115,
        locationID: 0x0014_0000,
        usagePage: 0x000C,
        usage: 0x0001,
        maxInputReportSize: 16,
        maxOutputReportSize: 1,
        maxFeatureReportSize: 1
      ),
      HIDCollectionRecord(
        vendorID: 0x0C45,
        productID: 0x800A,
        product: "Archon AK47",
        manufacturer: "SONiX",
        transport: "USB",
        versionNumber: 0x0115,
        locationID: 0x0014_0000,
        usagePage: 0xFF68,
        usage: 0x0061,
        maxInputReportSize: 64,
        maxOutputReportSize: 4_096,
        maxFeatureReportSize: 0
      ),
      HIDCollectionRecord(
        vendorID: 0x0C45,
        productID: 0x800A,
        product: "Archon AK47",
        manufacturer: "SONiX",
        transport: "USB",
        versionNumber: 0x0115,
        locationID: 0x0014_0000,
        usagePage: 0xFF13,
        usage: 0x0001,
        maxInputReportSize: 64,
        maxOutputReportSize: 64,
        maxFeatureReportSize: 64
      ),
    ]
  }
}
