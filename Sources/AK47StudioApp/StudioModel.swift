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
      case .deviceInspector: "Read-only HID details"
      }
    } else {
      switch self {
      case .dashboard: "작업 공간 한눈에 보기"
      case .keymap: "키 배치 초안 만들기"
      case .lighting: "색상 장면 구성하기"
      case .macros: "로컬 동작 배열하기"
      case .display: "화면 시안 만들기"
      case .settings: "앱 환경 설정"
      case .deviceInspector: "읽기 전용 HID 정보"
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
    inspectorState = .scanning

    do {
      collections = try provider.collections()
      inspectorState = .ready
    } catch {
      collections = []
      inspectorState = .failed(error.localizedDescription)
    }

    lastScan = Date()
  }
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
