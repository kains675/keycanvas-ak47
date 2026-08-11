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

enum LCDDiagnosticUploadState: Equatable {
  case idle
  case uploading(completedPages: Int, totalPages: Int)
  case succeeded(acknowledgedPages: Int, Date)
  case failed(acknowledgedPages: Int, String)
}

enum LCDQualifiedAnimationUploadState: Equatable {
  case idle
  case uploading(completedPages: Int, totalPages: Int)
  case succeeded(frameCount: Int, acknowledgedPages: Int, Date)
  case failed(acknowledgedPages: Int, String)
}

enum LCDQualifiedAnimationUploadPurpose: Equatable, Sendable {
  case maximumBoundaryTrial
  case qualified

  func accepts(frameCount: Int) -> Bool {
    switch self {
    case .maximumBoundaryTrial:
      frameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
    case .qualified:
      (1...AK47LCDUploadAdapter.qualifiedMaximumFrameCount).contains(frameCount)
    }
  }
}

struct LCDQualifiedAnimationSnapshot: Identifiable, Sendable {
  let id = UUID()
  let purpose: LCDQualifiedAnimationUploadPurpose
  let project: AK47LCDAnimationProject
  let plan: AK47LCDUploadPlan
  let summary: AK47LCDQualifiedUploadPlanSummary
}

enum LCDQualifiedAnimationPreparationError: LocalizedError {
  case exactTargetRequired
  case operationUnavailable
  case qualificationRequired
  case exactMaximumBoundaryFrameCountRequired(actual: Int)

  var errorDescription: String? {
    switch self {
    case .exactTargetRequired:
      "The exact wired AK47 revision 0x0115 target and four-collection topology are required."
    case .operationUnavailable:
      "Another device operation is active or the target is safety-quarantined."
    case .qualificationRequired:
      "The final durable 140-frame qualification receipt is required."
    case .exactMaximumBoundaryFrameCountRequired(let actual):
      "The maximum-boundary trial requires exactly 140 frames; this edit has \(actual)."
    }
  }
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
    let records = try HIDEnumerator.enumerate()
    AK47DeviceQuarantineRecovery.observeSuccessfulHardwareEnumeration(records)
    AK47LCDExtendedUploadQualification.observeSuccessfulHardwareEnumeration(records)
    return records
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
  @Published private(set) var lcdDiagnosticUploadState: LCDDiagnosticUploadState = .idle
  @Published private(set) var lcdQualifiedAnimationUploadState: LCDQualifiedAnimationUploadState =
    .idle
  @Published private(set) var lcdQualifiedAnimationVisualReviewSnapshot:
    LCDQualifiedAnimationSnapshot?
  @Published private(set) var lcdExtendedQualificationViewState: LCDExtendedQualificationViewState
  @Published private(set) var lcdExtendedQualificationError: String?
  @Published private(set) var deviceQuarantineRecoveryState =
    AK47DeviceQuarantineRecovery.state
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
    lcdExtendedQualificationViewState = Self.extendedQualificationViewState(
      AK47LCDExtendedUploadQualification.snapshot
    )

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
    deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
    refreshLCDExtendedQualificationViewState()

    lastScan = Date()
  }

  var canRunPerKeyRGBQuery: Bool {
    perKeyRGBQueryRequest != nil && liveDeviceOperationsAreAllowed
  }

  var canRunReadOnlyReportProbe: Bool {
    readProbeIdentity != nil && liveDeviceOperationsAreAllowed
  }

  var canRefreshInspector: Bool {
    inspectorState != .scanning && !isDeviceOperationInFlight
  }

  var canSynchronizeClock: Bool {
    verifiedWiredTarget != nil && liveDeviceOperationsAreAllowed
  }

  var canApplyLighting: Bool {
    verifiedWiredTarget != nil && liveDeviceOperationsAreAllowed
  }

  var hasVerifiedLCDDiagnosticTarget: Bool {
    verifiedWiredTarget != nil
  }

  var canRunLCDDiagnosticUpload: Bool {
    verifiedWiredTarget != nil && liveDeviceOperationsAreAllowed
  }

  var qualificationAllowsFreshLCDDiagnostic: Bool {
    switch lcdExtendedQualificationViewState {
    case .receiptUnavailable, .invalidatedRequiresFreshDiagnostic:
      true
    case .awaitingVisualAttestation, .awaitingObservedAbsence, .awaitingExactReappearance,
      .awaitingWiredPowerRemovalAttestation, .awaitingMaximumBoundaryTrial,
      .maximumBoundaryTransferInProgress, .awaitingMaximumBoundaryVisualAttestation,
      .awaitingMaximumBoundaryObservedAbsence, .awaitingMaximumBoundaryExactReappearance,
      .awaitingMaximumBoundaryWiredPowerRemovalAttestation,
      .maximumBoundaryVisualMismatchQuarantinePending, .qualified,
      .canonicalTransferInProgress, .canonicalVisualMismatchQuarantinePending,
      .extendedTransferInProgress, .awaitingExtendedVisualAttestation,
      .extendedVisualMismatchQuarantinePending, .interruptedTransferQuarantinePending,
      .blocked:
      false
    }
  }

  var canRecordLCDCanonicalVisualAttestation: Bool {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    guard snapshot.state == .awaitingCanonicalFixtureVisualAttestation,
      let receiptTarget = snapshot.target,
      let currentTarget = verifiedWiredTarget
    else { return false }
    return receiptTarget == currentTarget && !isDeviceOperationInFlight
  }

  var canReportLCDCanonicalVisualMismatch: Bool {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    return
      (snapshot.state == .awaitingCanonicalFixtureVisualAttestation
      || snapshot.state == .canonicalVisualMismatchQuarantinePending)
      && snapshot.target != nil
      && !isDeviceOperationInFlight
  }

  var canRecordLCDUSBModeCablePowerCycleAttestation: Bool {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    guard let receiptTarget = snapshot.target, let currentTarget = verifiedWiredTarget else {
      return false
    }
    switch snapshot.state {
    case .awaitingUSBPowerCycleAttestation,
      .awaitingMaximumBoundaryUSBPowerCycleAttestation:
      break
    default:
      return false
    }
    return receiptTarget == currentTarget && !isDeviceOperationInFlight
  }

  var canPrepareMaximumBoundaryLCDAnimation: Bool {
    guard let target = verifiedWiredTarget, liveDeviceOperationsAreAllowed else { return false }
    return AK47LCDExtendedUploadQualification.state(for: target)
      == .awaitingMaximumBoundaryTrial
  }

  var canPrepareQualifiedLCDAnimation: Bool {
    guard let target = verifiedWiredTarget, liveDeviceOperationsAreAllowed else { return false }
    guard
      case .qualified(let maximumFrameCount) =
        AK47LCDExtendedUploadQualification.state(for: target)
    else { return false }
    return maximumFrameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
  }

  var canPrepareAnyLCDAnimation: Bool {
    canPrepareMaximumBoundaryLCDAnimation || canPrepareQualifiedLCDAnimation
  }

  var canConfirmQualifiedLCDAnimationVisualResult: Bool {
    let receipt = AK47LCDExtendedUploadQualification.snapshot
    guard let target = receipt.target,
      verifiedWiredTarget == target,
      let review = lcdQualifiedAnimationVisualReviewSnapshot,
      receipt.pendingContainerSHA256 == review.summary.containerSHA256,
      receipt.pendingFrameCount == review.summary.frameCount,
      receipt.pendingPageCount == review.summary.pageCount,
      !isDeviceOperationInFlight
    else { return false }
    switch receipt.state {
    case .awaitingMaximumBoundaryVisualAttestation:
      return review.purpose == .maximumBoundaryTrial
    case .awaitingExtendedVisualAttestation:
      return review.purpose == .qualified
    default:
      return false
    }
  }

  var canReportQualifiedLCDAnimationVisualMismatch: Bool {
    let receipt = AK47LCDExtendedUploadQualification.snapshot
    guard
      receipt.target != nil,
      receipt.pendingContainerSHA256 != nil,
      !isDeviceOperationInFlight
    else { return false }
    switch receipt.state {
    case .awaitingMaximumBoundaryVisualAttestation,
      .maximumBoundaryVisualMismatchQuarantinePending,
      .awaitingExtendedVisualAttestation, .extendedVisualMismatchQuarantinePending:
      return true
    default:
      return false
    }
  }

  var canReconcileInterruptedLCDTransfer: Bool {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    switch snapshot.state {
    case .canonicalTransferInProgress, .maximumBoundaryTransferInProgress,
      .extendedTransferInProgress,
      .interruptedTransferQuarantinePending:
      return snapshot.target != nil && !isDeviceOperationInFlight
    default:
      return false
    }
  }

  var canInspectFactoryDefaultPlan: Bool {
    verifiedWiredTarget != nil && !isDeviceOperationInFlight
  }

  var canAcknowledgeFullPowerCycle: Bool {
    deviceQuarantineRecoveryState == .awaitingFullPowerCycleAcknowledgement
      && verifiedWiredTarget != nil
      && !isDeviceOperationInFlight
  }

  func acknowledgeFullPowerCycle() throws {
    guard canAcknowledgeFullPowerCycle, let target = verifiedWiredTarget else {
      throw AK47DeviceWriteError.operationGatePoisoned
    }
    try AK47DeviceQuarantineRecovery.acknowledgeFullPowerCycle(for: target)
    deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
  }

  private var isDeviceOperationInFlight: Bool {
    if case .writing = deviceWriteState { return true }
    if case .uploading = lcdDiagnosticUploadState { return true }
    if case .uploading = lcdQualifiedAnimationUploadState { return true }
    return perKeyRGBQueryState == .reading || deviceReadProbeState == .reading
  }

  private var liveDeviceOperationsAreAllowed: Bool {
    !isDeviceOperationInFlight
      && deviceQuarantineRecoveryState == .notQuarantined
      && lcdQualificationAllowsOtherDeviceOperations
  }

  private var lcdQualificationAllowsOtherDeviceOperations: Bool {
    switch AK47LCDExtendedUploadQualification.snapshot.state {
    case .unavailable, .awaitingMaximumBoundaryTrial, .qualified,
      .invalidatedRequiresFreshDiagnostic:
      true
    case .persistenceUnavailable, .awaitingCanonicalFixtureVisualAttestation,
      .awaitingObservedUSBDisconnection, .awaitingExactSamePortReappearance,
      .awaitingUSBPowerCycleAttestation, .maximumBoundaryTransferInProgress,
      .awaitingMaximumBoundaryVisualAttestation,
      .awaitingMaximumBoundaryObservedUSBDisconnection,
      .awaitingMaximumBoundaryExactSamePortReappearance,
      .awaitingMaximumBoundaryUSBPowerCycleAttestation,
      .maximumBoundaryVisualMismatchQuarantinePending, .canonicalTransferInProgress,
      .canonicalVisualMismatchQuarantinePending, .extendedTransferInProgress,
      .awaitingExtendedVisualAttestation, .extendedVisualMismatchQuarantinePending,
      .interruptedTransferQuarantinePending:
      false
    }
  }

  /// Builds the immutable dry-run plan shown by the UI. There is deliberately
  /// no HID submission path for this plan in the current application.
  func preflightFactoryDefaults() throws -> AK47FactoryResetPlan {
    guard !isDeviceOperationInFlight, let target = verifiedWiredTarget else {
      throw AK47DeviceWriteError.invalidTarget(
        "the exact wired revision 0x0115 target and four-collection topology are required"
      )
    }
    return try AK47FactoryResetPreflight.plan(target: target)
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

  /// Sends only the allowlisted one-frame/four-corner fixture after the view's
  /// operation-specific confirmation. Arbitrary editor projects never enter
  /// this path, and a new one-use authorization is bound to this exact plan.
  func uploadLCDDiagnosticFixtureOnce() {
    guard !isDeviceOperationInFlight else { return }
    guard let target = verifiedWiredTarget else {
      lcdDiagnosticUploadState = .failed(
        acknowledgedPages: 0,
        studioText(
          "검증된 유선 AK47 revision 0x0115와 정확한 4개 HID collection을 찾지 못했습니다.",
          "The verified wired AK47 revision 0x0115 with its exact four HID collections was not found.",
          language: language
        )
      )
      return
    }
    guard deviceQuarantineRecoveryState == .notQuarantined else {
      lcdDiagnosticUploadState = .failed(
        acknowledgedPages: 0,
        studioText(
          "장치 작업이 격리되어 있습니다. selector를 USB 위치에 둔 cable-removal 복구 절차를 먼저 마쳐야 합니다.",
          "Device operations are quarantined. Complete the required USB-mode cable-removal recovery first.",
          language: language
        )
      )
      return
    }

    let plan: AK47LCDUploadPlan
    do {
      plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
        target: target,
        container: AK47LCDDiagnosticFixture.encode()
      )
    } catch {
      lcdDiagnosticUploadState = .failed(
        acknowledgedPages: 0,
        error.localizedDescription
      )
      return
    }

    let authorization = AK47LCDUploadAuthorization(explicitlyConfirming: plan)
    let totalPages = plan.container.pageCount
    lcdDiagnosticUploadState = .uploading(completedPages: 0, totalPages: totalPages)

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        var acknowledgedPages = 0
        do {
          try AK47LCDUploadAdapter.uploadSingleFrame(
            plan: plan,
            authorization: authorization
          ) { completedPages, reportedTotal in
            acknowledgedPages = completedPages
            DispatchQueue.main.async { [weak self] in
              guard let self else { return }
              if case .uploading = self.lcdDiagnosticUploadState {
                self.lcdDiagnosticUploadState = .uploading(
                  completedPages: completedPages,
                  totalPages: reportedTotal
                )
              }
            }
          }
          return (acknowledgedPages, Optional<String>.none)
        } catch {
          return (acknowledgedPages, Optional(error.localizedDescription))
        }
      }.value

      if let message = result.1 {
        lcdDiagnosticUploadState = .failed(
          acknowledgedPages: result.0,
          message
        )
      } else {
        lcdDiagnosticUploadState = .succeeded(
          acknowledgedPages: result.0,
          Date()
        )
      }
      deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
      refreshLCDExtendedQualificationViewState()
    }
  }

  func recordLCDCanonicalVisualAttestation() {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    guard canRecordLCDCanonicalVisualAttestation, let target = snapshot.target else {
      lcdExtendedQualificationError =
        LCDQualifiedAnimationPreparationError.qualificationRequired.localizedDescription
      refreshLCDExtendedQualificationViewState()
      return
    }
    do {
      try AK47LCDExtendedUploadQualification.recordCanonicalFixtureVisualAttestation(
        for: target,
        attestation: AK47LCDCanonicalFixtureVisualAttestation(
          explicitlyConfirmingCanonicalCornersAt: Date()
        )
      )
      lcdExtendedQualificationError = nil
    } catch {
      lcdExtendedQualificationError = error.localizedDescription
    }
    refreshLCDExtendedQualificationViewState()
  }

  @discardableResult
  func reportLCDCanonicalVisualMismatch() -> Bool {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    guard canReportLCDCanonicalVisualMismatch, let target = snapshot.target else {
      lcdExtendedQualificationError =
        "No exact pending canonical LCD visual-review receipt is available."
      refreshLCDExtendedQualificationViewState()
      return false
    }
    do {
      try AK47LCDExtendedUploadQualification.reportCanonicalFixtureVisualMismatch(
        for: target
      )
      lcdExtendedQualificationError = nil
    } catch {
      lcdExtendedQualificationError = error.localizedDescription
    }
    deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
    refreshLCDExtendedQualificationViewState()
    return AK47LCDExtendedUploadQualification.snapshot.state
      == .invalidatedRequiresFreshDiagnostic
  }

  func recordLCDUSBModeCablePowerCycleAttestation() {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    guard canRecordLCDUSBModeCablePowerCycleAttestation, let target = snapshot.target else {
      lcdExtendedQualificationError =
        LCDQualifiedAnimationPreparationError.qualificationRequired.localizedDescription
      refreshLCDExtendedQualificationViewState()
      return
    }
    do {
      let attestation = AK47LCDUSBModeCablePowerCycleAttestation(
        explicitlyConfirmingUSBModeCableRemovalAt: Date()
      )
      switch snapshot.state {
      case .awaitingUSBPowerCycleAttestation:
        try AK47LCDExtendedUploadQualification.acknowledgeUSBModeCablePowerCycle(
          for: target,
          attestation: attestation
        )
      case .awaitingMaximumBoundaryUSBPowerCycleAttestation:
        try AK47LCDExtendedUploadQualification
          .acknowledgeMaximumBoundaryUSBModeCablePowerCycle(
            for: target,
            attestation: attestation
          )
      default:
        throw LCDQualifiedAnimationPreparationError.qualificationRequired
      }
      lcdExtendedQualificationError = nil
    } catch {
      lcdExtendedQualificationError = error.localizedDescription
    }
    refreshLCDExtendedQualificationViewState()
  }

  /// Copies the current in-memory editor value before detached encoding. Later
  /// editor mutations cannot change the returned plan, summary, or digest.
  func prepareQualifiedLCDAnimation(
    project: AK47LCDAnimationProject
  ) async throws -> LCDQualifiedAnimationSnapshot {
    guard !isDeviceOperationInFlight else {
      throw LCDQualifiedAnimationPreparationError.operationUnavailable
    }
    guard let target = verifiedWiredTarget else {
      throw LCDQualifiedAnimationPreparationError.exactTargetRequired
    }
    let purpose: LCDQualifiedAnimationUploadPurpose
    switch AK47LCDExtendedUploadQualification.state(for: target) {
    case .awaitingMaximumBoundaryTrial:
      guard
        LCDQualifiedAnimationUploadPurpose.maximumBoundaryTrial.accepts(
          frameCount: project.frames.count
        )
      else {
        throw LCDQualifiedAnimationPreparationError.exactMaximumBoundaryFrameCountRequired(
          actual: project.frames.count
        )
      }
      purpose = .maximumBoundaryTrial
    case .qualified(let maximumFrameCount)
    where maximumFrameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount:
      purpose = .qualified
    default:
      throw LCDQualifiedAnimationPreparationError.qualificationRequired
    }

    let immutableProject = project
    let container = try await Task.detached(priority: .userInitiated) {
      try AK47LCDUploadAdapter.encodeQualifiedAnimation(immutableProject)
    }.value

    guard !isDeviceOperationInFlight, verifiedWiredTarget == target else {
      throw LCDQualifiedAnimationPreparationError.operationUnavailable
    }
    let refreshedState = AK47LCDExtendedUploadQualification.state(for: target)
    switch purpose {
    case .maximumBoundaryTrial:
      guard refreshedState == .awaitingMaximumBoundaryTrial else {
        throw LCDQualifiedAnimationPreparationError.qualificationRequired
      }
    case .qualified:
      guard case .qualified(let maximumFrameCount) = refreshedState,
        maximumFrameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
      else {
        throw LCDQualifiedAnimationPreparationError.qualificationRequired
      }
    }

    let plan = try AK47LCDUploadPreflight.makeSyntheticPlan(
      target: target,
      container: container
    )
    let summary: AK47LCDQualifiedUploadPlanSummary
    switch purpose {
    case .maximumBoundaryTrial:
      summary = try AK47LCDUploadAdapter.makeMaximumBoundaryTrialPlanSummary(plan)
    case .qualified:
      summary = try AK47LCDUploadAdapter.makeQualifiedPlanSummary(plan)
    }
    return LCDQualifiedAnimationSnapshot(
      purpose: purpose,
      project: immutableProject,
      plan: plan,
      summary: summary
    )
  }

  func uploadQualifiedLCDAnimation(_ snapshot: LCDQualifiedAnimationSnapshot) {
    guard !isDeviceOperationInFlight else { return }
    let plan = snapshot.plan
    guard let target = verifiedWiredTarget, target == plan.target else {
      lcdQualifiedAnimationUploadState = .failed(
        acknowledgedPages: 0,
        LCDQualifiedAnimationPreparationError.exactTargetRequired.localizedDescription
      )
      return
    }
    guard liveDeviceOperationsAreAllowed else {
      lcdQualifiedAnimationUploadState = .failed(
        acknowledgedPages: 0,
        LCDQualifiedAnimationPreparationError.operationUnavailable.localizedDescription
      )
      return
    }
    let currentState = AK47LCDExtendedUploadQualification.state(for: target)
    let purposeIsAllowed: Bool
    switch snapshot.purpose {
    case .maximumBoundaryTrial:
      purposeIsAllowed =
        currentState == .awaitingMaximumBoundaryTrial
        && snapshot.purpose.accepts(frameCount: plan.container.frameCount)
    case .qualified:
      if case .qualified(let maximumFrameCount) = currentState {
        purposeIsAllowed =
          maximumFrameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
          && snapshot.purpose.accepts(frameCount: plan.container.frameCount)
      } else {
        purposeIsAllowed = false
      }
    }
    guard purposeIsAllowed else {
      lcdQualifiedAnimationUploadState = .failed(
        acknowledgedPages: 0,
        LCDQualifiedAnimationPreparationError.qualificationRequired.localizedDescription
      )
      refreshLCDExtendedQualificationViewState()
      return
    }

    let totalPages = plan.container.pageCount
    lcdQualifiedAnimationVisualReviewSnapshot = nil
    lcdQualifiedAnimationUploadState = .uploading(completedPages: 0, totalPages: totalPages)

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        var acknowledgedPages = 0
        do {
          let progress: (Int, Int) -> Void = { completedPages, reportedTotal in
            acknowledgedPages = completedPages
            DispatchQueue.main.async { [weak self] in
              guard let self else { return }
              if case .uploading = self.lcdQualifiedAnimationUploadState {
                self.lcdQualifiedAnimationUploadState = .uploading(
                  completedPages: completedPages,
                  totalPages: reportedTotal
                )
              }
            }
          }
          switch snapshot.purpose {
          case .maximumBoundaryTrial:
            try AK47LCDUploadAdapter.uploadMaximumBoundaryTrial(
              plan: plan,
              authorization: AK47LCDMaximumBoundaryUploadAuthorization(
                explicitlyConfirming: plan
              ),
              progress: progress
            )
          case .qualified:
            try AK47LCDUploadAdapter.uploadQualifiedAnimation(
              plan: plan,
              authorization: AK47LCDQualifiedUploadAuthorization(explicitlyConfirming: plan),
              progress: progress
            )
          }
          return (acknowledgedPages, Optional<String>.none)
        } catch {
          return (acknowledgedPages, Optional(error.localizedDescription))
        }
      }.value

      if let message = result.1 {
        lcdQualifiedAnimationUploadState = .failed(
          acknowledgedPages: result.0,
          message
        )
      } else {
        lcdQualifiedAnimationUploadState = .succeeded(
          frameCount: plan.container.frameCount,
          acknowledgedPages: result.0,
          Date()
        )
        lcdQualifiedAnimationVisualReviewSnapshot = snapshot
      }
      deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
      refreshLCDExtendedQualificationViewState()
    }
  }

  @discardableResult
  func recordQualifiedLCDAnimationVisualResult() -> Bool {
    let receipt = AK47LCDExtendedUploadQualification.snapshot
    guard canConfirmQualifiedLCDAnimationVisualResult,
      let target = receipt.target,
      let digest = receipt.pendingContainerSHA256
    else {
      lcdExtendedQualificationError =
        "The exact immutable expected preview is unavailable, so a correct visual result cannot be recorded."
      refreshLCDExtendedQualificationViewState()
      return false
    }
    do {
      let attestation = AK47LCDQualifiedUploadVisualAttestation(
        explicitlyConfirmingContainerSHA256: digest,
        at: Date()
      )
      switch receipt.state {
      case .awaitingMaximumBoundaryVisualAttestation:
        try AK47LCDExtendedUploadQualification.recordMaximumBoundaryVisualAttestation(
          for: target,
          attestation: attestation
        )
      case .awaitingExtendedVisualAttestation:
        try AK47LCDExtendedUploadQualification.recordQualifiedUploadVisualAttestation(
          for: target,
          attestation: attestation
        )
      default:
        throw LCDQualifiedAnimationPreparationError.qualificationRequired
      }
      lcdQualifiedAnimationVisualReviewSnapshot = nil
      lcdExtendedQualificationError = nil
    } catch {
      lcdExtendedQualificationError = error.localizedDescription
    }
    refreshLCDExtendedQualificationViewState()
    switch AK47LCDExtendedUploadQualification.snapshot.state {
    case .awaitingMaximumBoundaryObservedUSBDisconnection:
      return true
    case .qualified(let maximumFrameCount):
      return maximumFrameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
    default:
      return false
    }
  }

  @discardableResult
  func reportQualifiedLCDAnimationVisualMismatch() -> Bool {
    let receipt = AK47LCDExtendedUploadQualification.snapshot
    guard canReportQualifiedLCDAnimationVisualMismatch,
      let target = receipt.target,
      let digest = receipt.pendingContainerSHA256
    else {
      lcdExtendedQualificationError =
        "No exact pending LCD visual-review receipt is available."
      refreshLCDExtendedQualificationViewState()
      return false
    }
    do {
      switch receipt.state {
      case .awaitingMaximumBoundaryVisualAttestation,
        .maximumBoundaryVisualMismatchQuarantinePending:
        try AK47LCDExtendedUploadQualification.reportMaximumBoundaryVisualMismatch(
          for: target,
          containerSHA256: digest
        )
      case .awaitingExtendedVisualAttestation, .extendedVisualMismatchQuarantinePending:
        try AK47LCDExtendedUploadQualification.reportQualifiedUploadVisualMismatch(
          for: target,
          containerSHA256: digest
        )
      default:
        throw LCDQualifiedAnimationPreparationError.qualificationRequired
      }
      lcdQualifiedAnimationVisualReviewSnapshot = nil
      lcdExtendedQualificationError = nil
    } catch {
      lcdExtendedQualificationError = error.localizedDescription
    }
    deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
    refreshLCDExtendedQualificationViewState()
    return AK47LCDExtendedUploadQualification.snapshot.state
      == .invalidatedRequiresFreshDiagnostic
  }

  @discardableResult
  func reconcileInterruptedLCDTransfer() -> Bool {
    let snapshot = AK47LCDExtendedUploadQualification.snapshot
    guard canReconcileInterruptedLCDTransfer, let target = snapshot.target else {
      lcdExtendedQualificationError =
        "No exact interrupted LCD transfer receipt is available for reconciliation."
      refreshLCDExtendedQualificationViewState()
      return false
    }
    do {
      try AK47LCDExtendedUploadQualification.reconcileInterruptedTransfer(for: target)
      lcdExtendedQualificationError = nil
    } catch {
      lcdExtendedQualificationError = error.localizedDescription
    }
    deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
    refreshLCDExtendedQualificationViewState()
    return AK47LCDExtendedUploadQualification.snapshot.state
      == .invalidatedRequiresFreshDiagnostic
  }

  private func refreshLCDExtendedQualificationViewState() {
    lcdExtendedQualificationViewState = Self.extendedQualificationViewState(
      AK47LCDExtendedUploadQualification.snapshot
    )
  }

  static func extendedQualificationViewState(
    _ snapshot: AK47LCDExtendedUploadQualificationSnapshot
  ) -> LCDExtendedQualificationViewState {
    switch snapshot.state {
    case .unavailable:
      .receiptUnavailable
    case .persistenceUnavailable:
      .blocked(
        "The durable LCD qualification receipt could not be loaded. Live LCD transfer remains locked."
      )
    case .awaitingCanonicalFixtureVisualAttestation:
      .awaitingVisualAttestation
    case .awaitingObservedUSBDisconnection:
      .awaitingObservedAbsence
    case .awaitingExactSamePortReappearance:
      .awaitingExactReappearance
    case .awaitingUSBPowerCycleAttestation:
      .awaitingWiredPowerRemovalAttestation
    case .awaitingMaximumBoundaryTrial:
      .awaitingMaximumBoundaryTrial
    case .maximumBoundaryTransferInProgress:
      .maximumBoundaryTransferInProgress
    case .awaitingMaximumBoundaryVisualAttestation:
      if let digest = snapshot.pendingContainerSHA256,
        let frameCount = snapshot.pendingFrameCount,
        let pageCount = snapshot.pendingPageCount
      {
        .awaitingMaximumBoundaryVisualAttestation(
          containerSHA256: digest,
          frameCount: frameCount,
          pageCount: pageCount
        )
      } else {
        .blocked("The durable maximum-boundary visual-review receipt is incomplete.")
      }
    case .awaitingMaximumBoundaryObservedUSBDisconnection:
      .awaitingMaximumBoundaryObservedAbsence
    case .awaitingMaximumBoundaryExactSamePortReappearance:
      .awaitingMaximumBoundaryExactReappearance
    case .awaitingMaximumBoundaryUSBPowerCycleAttestation:
      .awaitingMaximumBoundaryWiredPowerRemovalAttestation
    case .maximumBoundaryVisualMismatchQuarantinePending:
      .maximumBoundaryVisualMismatchQuarantinePending
    case .qualified(let maximumFrameCount):
      .qualified(maximumFrameCount: maximumFrameCount)
    case .canonicalTransferInProgress:
      .canonicalTransferInProgress
    case .canonicalVisualMismatchQuarantinePending:
      .canonicalVisualMismatchQuarantinePending
    case .extendedTransferInProgress:
      .extendedTransferInProgress
    case .awaitingExtendedVisualAttestation:
      if let digest = snapshot.pendingContainerSHA256,
        let frameCount = snapshot.pendingFrameCount,
        let pageCount = snapshot.pendingPageCount
      {
        .awaitingExtendedVisualAttestation(
          containerSHA256: digest,
          frameCount: frameCount,
          pageCount: pageCount
        )
      } else {
        .blocked("The durable LCD visual-review receipt is incomplete.")
      }
    case .extendedVisualMismatchQuarantinePending:
      .extendedVisualMismatchQuarantinePending
    case .interruptedTransferQuarantinePending:
      .interruptedTransferQuarantinePending
    case .invalidatedRequiresFreshDiagnostic:
      .invalidatedRequiresFreshDiagnostic
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
      deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
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
        Result {
          try AK47PerKeyRGBQueryAdapter.query(
            request,
            authorization: AK47PerKeyRGBQueryAuthorization(
              explicitlyConfirming: request
            )
          )
        }
      }.value

      switch result {
      case .success(let snapshot):
        perKeyRGBQueryState = .ready(snapshot)
      case .failure(let error):
        perKeyRGBQueryState = .failed(error.localizedDescription)
      }
      deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
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
      deviceQuarantineRecoveryState = AK47DeviceQuarantineRecovery.state
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
    let command = group.candidates.command[0]
    return ReadProbeIdentity(
      product: "Archon AK47",
      locationID: group.identifier.locationID,
      versionNumber: command.versionNumber,
      serialNumber: command.serialNumber
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
      versionNumber: 0x0115,
      serialNumber: record.serialNumber
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
      versionNumber: 0x0115,
      serialNumber: command.serialNumber
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
        versionNumber: identity.versionNumber,
        serialNumber: identity.serialNumber,
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
          versionNumber: identity.versionNumber,
          serialNumber: identity.serialNumber,
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
  let versionNumber: UInt64?
  let serialNumber: String?
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
