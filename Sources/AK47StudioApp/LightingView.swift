import AK47InspectorCore
import Foundation
import SwiftUI

struct AK47LightingConfigurationCapabilities: OptionSet, Equatable, Sendable {
  let rawValue: UInt8

  static let brightness = Self(rawValue: 0x01)
  static let speed = Self(rawValue: 0x02)
  static let horizontalDirection = Self(rawValue: 0x04)
  static let verticalDirection = Self(rawValue: 0x08)
  static let directRGB = Self(rawValue: 0x10)
  static let paletteToggle = Self(rawValue: 0x20)
}

enum AK47OnboardLightingEffect: Int, CaseIterable, Identifiable, Sendable {
  case staticMode = 1
  case singleOn
  case singleOff
  case glittering
  case falling
  case colourful
  case breath
  case spectrum
  case outward
  case scrolling
  case rolling
  case rotating
  case explode
  case launch
  case ripples
  case flowing
  case pulsating
  case tilt
  case shuttle

  var id: Int { rawValue }
  var effectIdentifier: String { "ak47-onboard-\(rawValue)" }
  static let offResourceName = "LED Off"

  /// Exact spelling from the Windows application's 1033/1042 language resources.
  var resourceName: String {
    switch self {
    case .staticMode: "Static"
    case .singleOn: "SingleOn"
    case .singleOff: "SingleOff"
    case .glittering: "Glittering"
    case .falling: "Falling"
    case .colourful: "Colourful"
    case .breath: "Breath"
    case .spectrum: "Spectrum"
    case .outward: "Outward"
    case .scrolling: "Scrolling"
    case .rolling: "Rolling"
    case .rotating: "Rotating"
    case .explode: "Explode"
    case .launch: "Launch"
    case .ripples: "Ripples"
    case .flowing: "Flowing"
    case .pulsating: "Pulsating"
    case .tilt: "Tilt"
    case .shuttle: "Shuttle"
    }
  }

  /// Directly verified `config_func` bits from the non-PRO AK47 application.
  var configurationCapabilities: AK47LightingConfigurationCapabilities {
    switch self {
    case .staticMode:
      [.brightness, .directRGB, .paletteToggle]
    case .colourful, .spectrum:
      [.brightness, .speed]
    case .scrolling:
      [.brightness, .speed, .verticalDirection, .directRGB, .paletteToggle]
    case .rolling, .rotating, .flowing, .tilt:
      [.brightness, .speed, .horizontalDirection, .directRGB, .paletteToggle]
    case .singleOn, .singleOff, .glittering, .falling, .breath, .outward, .explode,
      .launch, .ripples, .pulsating, .shuttle:
      [.brightness, .speed, .directRGB, .paletteToggle]
    }
  }

  static func resolve(identifier: String) -> Self? {
    let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for prefix in ["ak47-onboard-", "windows-raw-mode-"] where normalized.hasPrefix(prefix) {
      let suffix = normalized.dropFirst(prefix.count)
      guard let rawValue = Int(suffix) else { return nil }
      return Self(rawValue: rawValue)
    }

    switch normalized {
    case "flow", "flow-preview", "flowing":
      return .flowing
    case "breath":
      return .breath
    case "still", "static":
      return .staticMode
    default:
      return nil
    }
  }
}

struct AK47LightingProfileSelection: Equatable, Sendable {
  let isEnabled: Bool
  let effect: AK47OnboardLightingEffect

  static func migrate(_ lighting: LightingProfile) -> Self {
    let normalized = lighting.effectIdentifier
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if normalized == "windows-raw-mode-0" || normalized == "ak47-onboard-0"
      || normalized == "windows-backup-no-active-lighting"
    {
      return Self(isEnabled: false, effect: .staticMode)
    }
    return Self(
      isEnabled: lighting.enabled,
      effect: AK47OnboardLightingEffect.resolve(identifier: normalized) ?? .staticMode
    )
  }
}

enum AK47LightingProfileField: Hashable, Sendable {
  case enabled
  case effect
  case brightness
  case speed
  case direction
  case colorful
  case baseColor
  case accentColor
  case perKey
}

struct AK47LightingDraftValues: Equatable, Sendable {
  var isEnabled: Bool
  var effect: AK47OnboardLightingEffect
  var brightnessLevel: Int
  var speedLevel: Int
  var direction: Int
  var colorful: Bool
  var baseColor: AK47InspectorCore.RGBColor
  var accentColor: AK47InspectorCore.RGBColor
  var perKey: [PerKeyLighting]

  static func projecting(
    _ profile: LightingProfile,
    fallbackAccentColor: AK47InspectorCore.RGBColor
  ) -> Self {
    let selection = AK47LightingProfileSelection.migrate(profile)
    return Self(
      isEnabled: selection.isEnabled,
      effect: selection.effect,
      brightnessLevel: displayedLevel(for: profile.brightnessPercent),
      speedLevel: displayedLevel(for: profile.speedPercent),
      direction: (0...1).contains(profile.direction) ? profile.direction : 0,
      colorful: profile.colorful,
      baseColor: profile.baseColor,
      accentColor: profile.accentColor ?? fallbackAccentColor,
      perKey: AK47PerKeyLightingDraft(entries: profile.perKey).entries
    )
  }

  fileprivate func matches(_ other: Self, field: AK47LightingProfileField) -> Bool {
    switch field {
    case .enabled: isEnabled == other.isEnabled
    case .effect: effect == other.effect
    case .brightness: brightnessLevel == other.brightnessLevel
    case .speed: speedLevel == other.speedLevel
    case .direction: direction == other.direction
    case .colorful: colorful == other.colorful
    case .baseColor: baseColor == other.baseColor
    case .accentColor: accentColor == other.accentColor
    case .perKey: perKey == other.perKey
    }
  }

  private static func displayedLevel(for percent: Int) -> Int {
    min(5, max(1, Int((Double(percent) / 20).rounded())))
  }
}

/// Keeps the exact on-disk profile as a baseline and replaces only fields the user has edited.
/// This prevents lossy UI projections (five-step sliders, fallback colors, migrated identifiers)
/// from silently changing a profile merely because the Lighting view was opened.
struct AK47LightingProfileEditingState: Equatable, Sendable {
  private(set) var baseline: LightingProfile
  private(set) var editedFields: Set<AK47LightingProfileField> = []

  init(baseline: LightingProfile) {
    self.baseline = baseline
  }

  mutating func observe(
    _ field: AK47LightingProfileField,
    values: AK47LightingDraftValues,
    fallbackAccentColor: AK47InspectorCore.RGBColor
  ) -> Bool {
    if editedFields.contains(field) {
      return true
    }

    let projectedBaseline = AK47LightingDraftValues.projecting(
      baseline,
      fallbackAccentColor: fallbackAccentColor
    )
    guard !values.matches(projectedBaseline, field: field) else {
      return false
    }
    editedFields.insert(field)
    return true
  }

  mutating func markEdited(_ fields: Set<AK47LightingProfileField>) {
    editedFields.formUnion(fields)
  }

  func composing(values: AK47LightingDraftValues) -> LightingProfile {
    var result = baseline
    if editedFields.contains(.enabled) {
      result.enabled = values.isEnabled
    }
    if editedFields.contains(.effect) {
      result.effectIdentifier = values.effect.effectIdentifier
    }
    if editedFields.contains(.brightness) {
      result.brightnessPercent = values.brightnessLevel * 20
    }
    if editedFields.contains(.speed) {
      result.speedPercent = values.speedLevel * 20
    }
    if editedFields.contains(.direction) {
      result.direction = values.direction
    }
    if editedFields.contains(.colorful) {
      result.colorful = values.colorful
    }
    if editedFields.contains(.baseColor) {
      result.baseColor = values.baseColor
    }
    if editedFields.contains(.accentColor) {
      result.accentColor = values.accentColor
    }
    if editedFields.contains(.perKey) {
      result.perKey = values.perKey
    }
    return result
  }
}

enum AK47PerKeyLightingApplyValues {
  static let offColor = AK47InspectorCore.RGBColor(red: 0, green: 0, blue: 0)

  /// The device protocol always expects all 84 firmware slots. An unpainted local-profile slot
  /// is represented as black at the apply boundary so a sparse draft remains safe to transmit.
  static func composing(from draft: AK47PerKeyLightingDraft) -> [AK47PerKeyRGBValue] {
    AK47PhysicalLayout.keys.map { key in
      AK47PerKeyRGBValue(
        lightIndex: key.lightIndex,
        color: draft.entry(at: key.lightIndex)?.color ?? offColor
      )
    }
  }

  static func initialBrushColor(
    selectedColor: AK47InspectorCore.RGBColor?,
    baseColor: AK47InspectorCore.RGBColor,
    fallbackColor: AK47InspectorCore.RGBColor
  ) -> AK47InspectorCore.RGBColor {
    if let selectedColor, selectedColor != offColor {
      return selectedColor
    }
    return baseColor == offColor ? fallbackColor : baseColor
  }

  static func initialSelectedLightIndex(from draft: AK47PerKeyLightingDraft) -> Int? {
    AK47PhysicalLayout.keys.first(where: { key in
      guard let color = draft.entry(at: key.lightIndex)?.color else { return false }
      return color != offColor
    })?.lightIndex ?? AK47PhysicalLayout.keys.first?.lightIndex
  }
}

private enum LightingWorkspace: String, CaseIterable, Identifiable {
  case onboard
  case perKey

  var id: Self { self }
}

struct LightingView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var model: StudioModel
  @ObservedObject var profileStore: LocalProfileStore
  @AppStorage("lightingWorkspace") private var workspace = LightingWorkspace.onboard
  @State private var lightingEnabled = true
  @State private var effect = AK47OnboardLightingEffect.flowing
  @State private var brightness = 4.0
  @State private var tempo = 3.0
  @State private var direction = 0
  @State private var colorful = false
  @State private var firstColor = StudioPalette.mint
  @State private var secondColor = StudioPalette.violet
  @State private var perKeyDraft = AK47PerKeyLightingDraft()
  @State private var selectedLightIndex = AK47PhysicalLayout.keys.first?.lightIndex ?? 1
  @State private var perKeyPaintColor = StudioPalette.mint
  @State private var previewRevision = 0
  @State private var profileEditingState: AK47LightingProfileEditingState?
  @State private var showsOnboardWriteConfirmation = false
  @State private var showsPerKeyWriteConfirmation = false

  init(model: StudioModel) {
    self.model = model
    self.profileStore = model.profileStore
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("효과와 키별 색상", "Effects and per-key color", language: language),
          title: studioText("조명", "Lighting", language: language),
          detail: studioText(
            "내장 효과를 미리 보거나 84키를 직접 칠한 뒤 로컬 프로필에 저장할 수 있습니다. 키보드 전송은 현재 작업의 적용 버튼과 별도 확인을 거친 경우에만 한 번 실행됩니다.",
            "Preview onboard effects or paint all 84 keys, then save the result to a local profile. A device write runs once only from the current workspace's Apply button after a separate confirmation.",
            language: language
          )
        )

        workspacePicker

        switch workspace {
        case .onboard:
          onboardWorkspace
        case .perKey:
          perKeyWorkspace
        }

        DemoNotice()
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 28)
      .padding(.top, 28)
      .frame(maxWidth: 1050)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in loadProfile() }
    .onChange(of: profileStore.status) { status in
      if case .saved = status {
        acceptSelectedLightingAsBaseline()
      }
    }
    .onChange(of: lightingEnabled) { _ in observeProfileField(.enabled) }
    .onChange(of: effect) { _ in observeProfileField(.effect) }
    .onChange(of: brightness) { _ in observeProfileField(.brightness) }
    .onChange(of: tempo) { _ in observeProfileField(.speed) }
    .onChange(of: direction) { _ in observeProfileField(.direction) }
    .onChange(of: colorful) { _ in observeProfileField(.colorful) }
    .onChange(of: firstColor) { _ in observeProfileField(.baseColor) }
    .onChange(of: secondColor) { _ in observeProfileField(.accentColor) }
    .onChange(of: perKeyDraft) { _ in observeProfileField(.perKey) }
    .onDisappear(perform: synchronizeProfileDraft)
    .alert(
      studioText("내장 조명을 키보드에 적용할까요?", "Apply onboard lighting?", language: language),
      isPresented: $showsOnboardWriteConfirmation
    ) {
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
      Button(studioText("한 번 적용", "Apply once", language: language)) {
        applyOnboardLighting()
      }
    } message: {
      Text(
        studioText(
          "현재 키보드의 모드·밝기·속도·방향은 읽어 백업할 수 없습니다. 선택한 값을 한 번 전송하며 실패 시 자동 재시도하지 않습니다.",
          "The current mode, brightness, speed, and direction cannot be read back for backup. The selected values are sent once with no automatic retry.",
          language: language
        )
      )
    }
    .alert(
      studioText("84키 RGB를 키보드에 적용할까요?", "Apply all 84 RGB values?", language: language),
      isPresented: $showsPerKeyWriteConfirmation
    ) {
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
      Button(studioText("한 번 적용", "Apply once", language: language)) {
        applyPerKeyRGB()
      }
    } message: {
      Text(perKeyApplyConfirmationMessage)
    }
  }

  private var workspacePicker: some View {
    Picker(
      studioText("조명 편집 방식", "Lighting editor", language: language),
      selection: $workspace
    ) {
      Label(
        studioText("내장 효과", "Onboard effects", language: language),
        systemImage: "waveform.path"
      )
      .tag(LightingWorkspace.onboard)
      Label(
        studioText("키별 RGB", "Per-key RGB", language: language),
        systemImage: "paintbrush.pointed"
      )
      .tag(LightingWorkspace.perKey)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity)
    .accessibilityLabel(studioText("조명 편집 방식", "Lighting editor", language: language))
  }

  private var onboardWorkspace: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardModePanel

      HStack(alignment: .top, spacing: 16) {
        lightingCanvas
          .frame(minWidth: 460, maxWidth: .infinity)
        onboardControls
          .frame(width: 340)
      }

      workspaceActionBar(for: .onboard)
    }
  }

  private var perKeyWorkspace: some View {
    VStack(alignment: .leading, spacing: 18) {
      perKeyBrightnessPanel
      AK47PerKeyLightingEditor(
        language: language,
        draft: $perKeyDraft,
        selectedLightIndex: $selectedLightIndex,
        paintColor: $perKeyPaintColor,
        onEdit: { markProfileFieldsEdited([.perKey]) }
      )
      workspaceActionBar(for: .perKey)
    }
  }

  private var perKeyBrightnessPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(studioText("키별 RGB 전체 밝기", "Per-key RGB brightness", language: language))
          .font(.headline)
        Text(
          studioText(
            "현재 확인된 프로토콜은 키마다 다른 밝기가 아니라 84키 전체에 공통인 1–5 밝기를 사용합니다. 이 값은 내장 효과의 밝기와 공유됩니다.",
            "The verified protocol provides one shared 1–5 brightness level for all 84 keys, not a separate level per key. This value is shared with onboard-effect brightness.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      ControlSlider(
        title: studioText("전체 밝기", "Overall brightness", language: language),
        value: $brightness,
        symbol: "sun.max",
        valueLabel: "\(Int(brightness.rounded())) / 5"
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studioPanel()
  }

  private func workspaceActionBar(for workspace: LightingWorkspace) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: profileHasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(profileHasUnsavedChanges ? StudioPalette.coral : StudioPalette.mint)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            profileHasUnsavedChanges
              ? studioText("로컬 변경사항이 있습니다", "Local changes are not saved", language: language)
              : studioText("로컬 프로필에 저장됨", "Saved to the local profile", language: language)
          )
          .font(.headline)
          Text(
            studioText(
              "프로필 저장은 이 Mac에만 기록합니다. 키보드 적용은 저장과 별개이며 아래 버튼과 확인창을 거쳐야 합니다.",
              "Saving writes only to this Mac. Applying to the keyboard is separate and requires the button below plus a confirmation dialog.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Divider()

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          workspaceButtons(for: workspace)
          Spacer()
          deviceWriteStatus
        }
        VStack(alignment: .leading, spacing: 12) {
          workspaceButtons(for: workspace)
          deviceWriteStatus
        }
      }

      if let unavailableReason = applyUnavailableReason(for: workspace) {
        Label(unavailableReason, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      DisclosureGroup(studioText("장치 적용 안전 정보", "Device apply safety", language: language)) {
        Text(
          studioText(
            "0C45:800A · revision 0x0115 · FF13 Feature 채널만 사용합니다. 자동 재시도 없이 ACK 오류 또는 360ms 타임아웃에서 중단합니다. 현재 장치 설정은 완전히 읽어 백업할 수 없습니다.",
            "Only the 0C45:800A revision 0x0115 FF13 Feature channel is used. The operation stops on an ACK error or 360 ms timeout without automatic retry. Current device settings cannot be backed up completely.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
      }
      .font(.caption.weight(.semibold))
    }
    .studioPanel()
  }

  private func applyUnavailableReason(for _: LightingWorkspace) -> String? {
    guard !model.canApplyLighting else { return nil }
    return studioText(
      "검증된 유선 AK47이 준비되지 않았거나 다른 장치 작업이 진행 중입니다.",
      "The verified wired AK47 is not ready, or another device operation is in progress.",
      language: language
    )
  }

  @ViewBuilder
  private func workspaceButtons(for workspace: LightingWorkspace) -> some View {
    Button(action: saveProfile) {
      Label(
        profileHasUnsavedChanges
          ? studioText("프로필 저장", "Save profile", language: language)
          : studioText("저장됨", "Saved", language: language),
        systemImage: profileHasUnsavedChanges ? "square.and.arrow.down" : "checkmark"
      )
    }
    .buttonStyle(.bordered)
    .disabled(!profileHasUnsavedChanges)

    switch workspace {
    case .onboard:
      Button {
        showsOnboardWriteConfirmation = true
      } label: {
        Label(
          lightingEnabled
            ? studioText("현재 효과를 키보드에 적용…", "Apply current effect to keyboard…", language: language)
            : studioText("LED Off를 키보드에 적용…", "Apply LED Off to keyboard…", language: language),
          systemImage: lightingEnabled ? "lightbulb" : "lightbulb.slash"
        )
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.coral)
      .disabled(!model.canApplyLighting)
    case .perKey:
      Button {
        showsPerKeyWriteConfirmation = true
      } label: {
        Label(
          studioText("84키 RGB를 키보드에 적용…", "Apply 84-key RGB to keyboard…", language: language),
          systemImage: "paintbrush.pointed"
        )
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.coral)
      .disabled(!model.canApplyLighting)
    }
  }

  @ViewBuilder
  private var deviceWriteStatus: some View {
    switch model.deviceWriteState {
    case .idle:
      StatusPill(
        label: studioText("대기", "Idle", language: language),
        symbol: "hand.raised",
        tint: StudioPalette.muted
      )
    case .writing(let kind):
      HStack(spacing: 8) {
        ProgressView()
        Text(writeKindLabel(kind))
          .font(.caption)
      }
    case .succeeded(let kind, _):
      StatusPill(
        label: studioText(
          "\(writeKindLabel(kind)) 완료", "\(writeKindLabel(kind)) complete", language: language),
        symbol: "checkmark.circle.fill",
        tint: StudioPalette.mint
      )
    case .failed(_, let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(StudioPalette.coral)
        .lineLimit(3)
        .frame(maxWidth: 300, alignment: .trailing)
    }
  }

  private func writeKindLabel(_ kind: AK47DeviceWriteKind) -> String {
    switch kind {
    case .clockSync: studioText("시계 동기화", "Clock sync", language: language)
    case .onboardLighting: studioText("내장 조명", "Onboard lighting", language: language)
    case .perKeyRGB: studioText("키별 RGB", "Per-key RGB", language: language)
    }
  }

  private func applyOnboardLighting() {
    model.applyOnboardLighting(
      AK47OnboardLightingValue(
        mode: lightingEnabled ? UInt8(effect.rawValue) : 0,
        color: firstColor.profileRGBColor,
        colorful: colorful && effect.configurationCapabilities.contains(.paletteToggle),
        brightness: UInt8(Int(brightness.rounded())),
        speed: UInt8(Int(tempo.rounded())),
        direction: UInt8(supportsDirection ? direction : 0)
      )
    )
  }

  private func applyPerKeyRGB() {
    model.applyPerKeyRGB(
      brightness: UInt8(Int(brightness.rounded())),
      values: AK47PerKeyLightingApplyValues.composing(from: perKeyDraft)
    )
  }

  private var perKeyApplyConfirmationMessage: String {
    let values = AK47PerKeyLightingApplyValues.composing(from: perKeyDraft)
    let litKeyCount = values.count { $0.color != AK47PerKeyLightingApplyValues.offColor }
    let offKeyCount = values.count - litKeyCount
    return studioText(
      "84키 RGB 전체 표와 공통 밝기 \(Int(brightness.rounded()))/5를 덮어씁니다. 켜짐 \(litKeyCount)/84키, 나머지 \(offKeyCount)키는 검은색(RGB 0·0·0, 꺼짐)으로 전송합니다. 실패 시 자동 재시도하지 않습니다.",
      "This overwrites the complete 84-key RGB table at shared brightness \(Int(brightness.rounded()))/5. \(litKeyCount)/84 keys are lit; the other \(offKeyCount) are sent as black (RGB 0·0·0, off). The operation never retries automatically.",
      language: language
    )
  }

  private var lightingCanvas: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(studioText("84키 효과 미리보기", "84-key effect preview", language: language))
            .font(.headline)
          Text(
            studioText(
              "펌웨어 이름과 조절 축을 바탕으로 한 KeyCanvas 근사 애니메이션 · 실제 펌웨어의 프레임 수식은 미확인",
              "A KeyCanvas approximation based on firmware names and controls · exact firmware frame math is unverified",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        HStack(spacing: 8) {
          StatusPill(
            label: !lightingEnabled
              ? AK47OnboardLightingEffect.offResourceName
              : (effect.isReactive
                ? studioText("가상 입력", "Simulated input", language: language)
                : studioText("재생 중", "Animating", language: language)),
            symbol: !lightingEnabled
              ? "lightbulb.slash" : (effect.isReactive ? "cursorarrow.click" : "waveform"),
            tint: lightingEnabled ? StudioPalette.violet : .gray
          )
          Button {
            previewRevision += 1
          } label: {
            Image(systemName: "arrow.counterclockwise")
          }
          .buttonStyle(.borderless)
          .help(studioText("미리보기 다시 시작", "Restart preview", language: language))
          .accessibilityLabel(studioText("미리보기 다시 시작", "Restart preview", language: language))
        }
      }

      AK47LightingKeyboardPreview(
        language: language,
        effect: effect,
        lightingEnabled: lightingEnabled,
        brightnessLevel: brightness,
        speedLevel: tempo,
        direction: supportsDirection ? direction : 0,
        baseColor: firstColor.profileRGBColor,
        accentColor: previewAccentColor,
        revision: previewRevision
      )
      .padding(18)
      .background(StudioPalette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

      if effect.isReactive {
        Label(
          studioText(
            "자동 가상 키 입력으로 반복 재생합니다. 미리보기의 키를 클릭하면 그 위치에서도 반응합니다.",
            "A simulated key press repeats automatically. Click a preview key to trigger the effect there too.",
            language: language
          ),
          systemImage: "hand.tap"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .studioPanel()
  }

  private var onboardModePanel: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(studioText("효과 선택", "Choose an effect", language: language))
            .font(.headline)
          Text(
            lightingEnabled
              ? String(format: "%02d · %@", effect.rawValue, effect.resourceName)
              : AK47OnboardLightingEffect.offResourceName
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: lightingEnabled ? "lightbulb.fill" : "lightbulb.slash")
          .foregroundStyle(lightingEnabled ? StudioPalette.mint : .secondary)
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], spacing: 8) {
        onboardModeButton(mode: 0, name: AK47OnboardLightingEffect.offResourceName)
        ForEach(AK47OnboardLightingEffect.allCases) { item in
          onboardModeButton(mode: item.rawValue, name: item.resourceName)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .studioPanel()
  }

  private var onboardControls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(studioText("현재 효과 조절", "Current effect controls", language: language))
        .font(.headline)
      if lightingEnabled {
        parameterControls
      } else {
        Label(
          studioText(
            "LED Off는 조명만 끕니다. 마지막 효과와 조절값은 프로필에 유지됩니다.",
            "LED Off disables lighting while preserving the last effect and controls in the profile.",
            language: language
          ),
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .studioPanel()
  }

  private func onboardModeButton(mode: Int, name: String) -> some View {
    let isSelected = lightingEnabled ? effect.rawValue == mode : mode == 0
    return Button {
      if mode == 0 {
        lightingEnabled = false
        markProfileFieldsEdited([.enabled])
      } else if let selectedEffect = AK47OnboardLightingEffect(rawValue: mode) {
        effect = selectedEffect
        lightingEnabled = true
        markProfileFieldsEdited([.enabled, .effect])
      }
    } label: {
      HStack(spacing: 8) {
        Text(String(format: "%02d", mode))
          .font(.caption2.monospacedDigit().weight(.bold))
          .foregroundStyle(isSelected ? Color.white.opacity(0.76) : .secondary)
        Text(name)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
        if isSelected {
          Image(systemName: "checkmark")
            .font(.caption2.weight(.bold))
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? StudioPalette.blue : Color.primary.opacity(0.045),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .foregroundStyle(isSelected ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(mode), \(name)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var parameterControls: some View {
    if effect.configurationCapabilities.contains(.paletteToggle) {
      VStack(alignment: .leading, spacing: 7) {
        Label(studioText("색상 방식", "Color mode", language: language), systemImage: "paintpalette")
          .font(.callout)
        Picker(
          studioText("색상 방식", "Color mode", language: language),
          selection: $colorful
        ) {
          Text(studioText("단색", "Single color", language: language)).tag(false)
          Text("Colorful").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
    }

    if effect.configurationCapabilities.contains(.directRGB), !colorful {
      ColorPicker(
        studioText("키보드 색상", "Keyboard color", language: language),
        selection: $firstColor,
        supportsOpacity: false
      )
      quickColorPresets
    } else if effect.configurationCapabilities.contains(.directRGB) {
      Label(
        studioText(
          "키보드는 내장 Colorful 팔레트를 사용합니다.",
          "The keyboard uses its onboard Colorful palette.",
          language: language
        ),
        systemImage: "circle.hexagongrid.fill"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    } else {
      Label(
        studioText(
          "이 효과의 색상은 펌웨어가 자동으로 만듭니다.",
          "This effect's colors are generated by the firmware.",
          language: language
        ),
        systemImage: "wand.and.stars"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }

    if effect.configurationCapabilities.contains(.brightness) {
      ControlSlider(
        title: studioText("밝기", "Brightness", language: language),
        value: $brightness,
        symbol: "sun.max",
        valueLabel: "\(Int(brightness.rounded())) / 5"
      )
    }

    if effect.configurationCapabilities.contains(.speed) {
      ControlSlider(
        title: studioText("효과 속도", "Effect speed", language: language),
        value: $tempo,
        symbol: "speedometer",
        valueLabel: "\(Int(tempo.rounded())) / 5"
      )
    }

    if supportsDirection {
      VStack(alignment: .leading, spacing: 7) {
        Label(
          effect.configurationCapabilities.contains(.horizontalDirection)
            ? studioText("좌우 진행 방향", "Horizontal direction", language: language)
            : studioText("상하 진행 방향", "Vertical direction", language: language),
          systemImage: effect.configurationCapabilities.contains(.horizontalDirection)
            ? "arrow.left.and.right" : "arrow.up.and.down"
        )
        .font(.callout)
        Picker(studioText("진행 방향", "Direction", language: language), selection: $direction) {
          Text(studioText("방향 A", "Direction A", language: language)).tag(0)
          Text(studioText("방향 B", "Direction B", language: language)).tag(1)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        Text(
          studioText(
            "A/B는 Windows 앱의 Raw 0/1을 안전하게 보존한 이름입니다.",
            "A/B preserve the Windows application's Raw 0/1 values without claiming an unverified orientation.",
            language: language
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }

    if colorful {
      DisclosureGroup(studioText("근사 미리보기 색상", "Approximate preview color", language: language)) {
        ColorPicker(
          studioText("미리보기 강조색 · 전송 안 됨", "Preview accent · not sent", language: language),
          selection: $secondColor,
          supportsOpacity: false
        )
        .padding(.top, 6)
      }
      .font(.caption.weight(.semibold))
    }
  }

  private var quickColorPresets: some View {
    HStack(spacing: 9) {
      quickColorButton(.white, name: studioText("흰색", "White", language: language))
      quickColorButton(StudioPalette.mint, name: studioText("민트", "Mint", language: language))
      quickColorButton(StudioPalette.blue, name: studioText("파랑", "Blue", language: language))
      quickColorButton(StudioPalette.violet, name: studioText("보라", "Violet", language: language))
      quickColorButton(StudioPalette.coral, name: studioText("코랄", "Coral", language: language))
    }
  }

  private func quickColorButton(_ color: Color, name: String) -> some View {
    Button {
      firstColor = color
      markProfileFieldsEdited([.baseColor])
    } label: {
      Circle()
        .fill(color)
        .frame(width: 28, height: 28)
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.18)) }
    }
    .buttonStyle(.plain)
    .help(name)
    .accessibilityLabel(name)
  }

  private var currentLightingValues: AK47LightingDraftValues {
    AK47LightingDraftValues(
      isEnabled: lightingEnabled,
      effect: effect,
      brightnessLevel: Int(brightness.rounded()),
      speedLevel: Int(tempo.rounded()),
      direction: direction,
      colorful: colorful,
      baseColor: firstColor.profileRGBColor,
      accentColor: secondColor.profileRGBColor,
      perKey: perKeyDraft.entries
    )
  }

  private var currentLightingDraft: LightingProfile {
    guard let profileEditingState else {
      return profileStore.selectedProfile.lighting
    }
    return profileEditingState.composing(values: currentLightingValues)
  }

  private var profileHasUnsavedChanges: Bool {
    switch profileStore.status {
    case .unsaved, .failed:
      true
    case .ready, .saved, .imported:
      false
    }
  }

  private func synchronizeProfileDraft() {
    let draft = currentLightingDraft
    guard profileStore.selectedProfile.lighting != draft else { return }
    profileStore.updateLighting(draft)
  }

  private func saveProfile() {
    synchronizeProfileDraft()
    profileStore.saveSelected()
    if case .saved = profileStore.status {
      acceptSelectedLightingAsBaseline()
    }
  }

  private func loadProfile() {
    let lighting = profileStore.selectedProfile.lighting
    profileEditingState = AK47LightingProfileEditingState(baseline: lighting)
    let selection = AK47LightingProfileSelection.migrate(lighting)
    lightingEnabled = selection.isEnabled
    effect = selection.effect
    brightness = level(for: lighting.brightnessPercent)
    tempo = level(for: lighting.speedPercent)
    direction = (0...1).contains(lighting.direction) ? lighting.direction : 0
    colorful = lighting.colorful
    firstColor = lighting.baseColor.swiftUIColor
    secondColor = lighting.accentColor?.swiftUIColor ?? StudioPalette.violet
    perKeyDraft = AK47PerKeyLightingDraft(entries: lighting.perKey)
    selectedLightIndex =
      AK47PerKeyLightingApplyValues.initialSelectedLightIndex(from: perKeyDraft) ?? 1
    perKeyPaintColor =
      AK47PerKeyLightingApplyValues.initialBrushColor(
        selectedColor: perKeyDraft.entry(at: selectedLightIndex)?.color,
        baseColor: lighting.baseColor,
        fallbackColor: StudioPalette.mint.profileRGBColor
      ).swiftUIColor
    previewRevision = 0
  }

  private func observeProfileField(_ field: AK47LightingProfileField) {
    guard var editingState = profileEditingState else { return }
    let shouldSynchronize = editingState.observe(
      field,
      values: currentLightingValues,
      fallbackAccentColor: StudioPalette.violet.profileRGBColor
    )
    profileEditingState = editingState
    if shouldSynchronize {
      synchronizeProfileDraft()
    }
  }

  private func markProfileFieldsEdited(_ fields: Set<AK47LightingProfileField>) {
    guard var editingState = profileEditingState else { return }
    editingState.markEdited(fields)
    profileEditingState = editingState
    synchronizeProfileDraft()
  }

  private func acceptSelectedLightingAsBaseline() {
    profileEditingState = AK47LightingProfileEditingState(
      baseline: profileStore.selectedProfile.lighting
    )
  }

  private var supportsDirection: Bool {
    let capabilities = effect.configurationCapabilities
    return capabilities.contains(.horizontalDirection) || capabilities.contains(.verticalDirection)
  }

  private var previewAccentColor: AK47InspectorCore.RGBColor {
    guard effect.configurationCapabilities.contains(.paletteToggle), colorful else {
      return firstColor.profileRGBColor
    }
    return secondColor.profileRGBColor
  }

  private func level(for percent: Int) -> Double {
    Double(min(5, max(1, Int((Double(percent) / 20).rounded()))))
  }
}

private struct ControlSlider: View {
  let title: String
  @Binding var value: Double
  let symbol: String
  let valueLabel: String

  var body: some View {
    VStack(spacing: 7) {
      HStack {
        Label(title, systemImage: symbol)
        Spacer()
        Text(valueLabel)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .font(.callout)
      Slider(value: $value, in: 1...5, step: 1)
    }
  }
}
