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

struct LightingView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var model: StudioModel
  @ObservedObject var profileStore: LocalProfileStore
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
  @State private var savedLocally = false
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
          eyebrow: studioText("로컬 내장 효과", "Local onboard effects", language: language),
          title: studioText("조명", "Lighting", language: language),
          detail: studioText(
            "확인된 19개 내장 모드를 실제 84키 배열의 움직이는 근사 시뮬레이션으로 살펴봅니다. 자동 전송되지 않으며, 아래 적용 버튼과 별도 확인을 거칠 때만 선택한 값을 한 번 보냅니다.",
            "Explore the 19 identified onboard modes in an animated approximation on the actual 84-key layout. Nothing is sent automatically; the selected value is sent once only through the Apply button and a separate confirmation.",
            language: language
          )
        )

        lightingCanvas

        HStack(alignment: .top, spacing: 16) {
          controls
          palettePanel
        }

        AK47PerKeyLightingEditor(
          language: language,
          draft: $perKeyDraft,
          selectedLightIndex: $selectedLightIndex,
          paintColor: $perKeyPaintColor,
          onEdit: { savedLocally = false }
        )

        deviceApplyPanel

        DemoNotice()
      }
      .padding(28)
      .frame(maxWidth: 1050)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in loadProfile() }
    .onChange(of: lightingEnabled) { _ in savedLocally = false }
    .onChange(of: effect) { _ in savedLocally = false }
    .onChange(of: brightness) { _ in savedLocally = false }
    .onChange(of: tempo) { _ in savedLocally = false }
    .onChange(of: direction) { _ in savedLocally = false }
    .onChange(of: colorful) { _ in savedLocally = false }
    .onChange(of: firstColor) { _ in savedLocally = false }
    .onChange(of: secondColor) { _ in savedLocally = false }
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
      Text(
        studioText(
          "키별 RGB 전체 표와 밝기를 덮어씁니다. 84키가 모두 채워졌을 때만 전송하며 실패 시 자동 재시도하지 않습니다.",
          "This overwrites the complete per-key RGB table and brightness. It is enabled only when all 84 keys are filled and never retries automatically.",
          language: language
        )
      )
    }
  }

  private var deviceApplyPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "cable.connector")
          .font(.title3)
          .foregroundStyle(StudioPalette.coral)
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("검증된 유선 장치 적용", "Verified wired-device apply", language: language))
            .font(.headline)
          Text(
            studioText(
              "0C45:800A · revision 0x0115 · FF13 Feature 채널에만 전송합니다. 각 작업은 단일 직렬 상태 기계로 실행되고, ACK 오류나 360ms 타임아웃에서 즉시 중단합니다.",
              "Writes only to the 0C45:800A revision 0x0115 FF13 Feature channel. Each action runs through one serial state machine and stops immediately on an ACK error or 360 ms timeout.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        deviceWriteStatus
      }

      Divider()

      HStack(spacing: 12) {
        Button {
          showsOnboardWriteConfirmation = true
        } label: {
          Label(
            lightingEnabled
              ? studioText("현재 내장 모드 적용…", "Apply onboard mode…", language: language)
              : studioText("LED Off 적용…", "Apply LED Off…", language: language),
            systemImage: "lightbulb"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.coral)
        .disabled(!model.canApplyLighting)

        Button {
          showsPerKeyWriteConfirmation = true
        } label: {
          Label(
            studioText("84키 RGB 적용…", "Apply 84-key RGB…", language: language),
            systemImage: "paintbrush.pointed"
          )
        }
        .buttonStyle(.bordered)
        .disabled(!model.canApplyLighting || perKeyDraft.configuredKeyCount != 84)

        Spacer()
        Text("\(perKeyDraft.configuredKeyCount) / 84")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(
        studioText(
          "내장 효과 적용은 0~19번 모드 중 현재 선택 하나만 보냅니다. 19개를 자동 순회하지 않습니다. 키별 RGB는 누락 키가 있으면 차단됩니다.",
          "Onboard apply sends only the currently selected mode from 0...19; it never cycles all modes automatically. Per-key RGB is blocked while any key is missing.",
          language: language
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .studioPanel()
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
    guard perKeyDraft.configuredKeyCount == 84 else { return }
    let values = AK47PhysicalLayout.keys.compactMap { key -> AK47PerKeyRGBValue? in
      guard let entry = perKeyDraft.entry(at: key.lightIndex) else { return nil }
      return AK47PerKeyRGBValue(lightIndex: key.lightIndex, color: entry.color)
    }
    model.applyPerKeyRGB(
      brightness: UInt8(Int(brightness.rounded())),
      values: values
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
        StatusPill(
          label: savedLocally
            ? studioText("로컬 저장됨", "Saved locally", language: language)
            : (!lightingEnabled
              ? AK47OnboardLightingEffect.offResourceName
              : (effect.isReactive
                ? studioText("가상 입력 자동 재생", "Simulated input", language: language)
                : studioText("애니메이션 재생 중", "Animating", language: language))),
          symbol: savedLocally
            ? "checkmark.circle"
            : (!lightingEnabled
              ? "lightbulb.slash" : (effect.isReactive ? "cursorarrow.click" : "waveform")),
          tint: savedLocally
            ? StudioPalette.mint : (lightingEnabled ? StudioPalette.violet : .gray)
        )
      }

      AK47LightingKeyboardPreview(
        language: language,
        effect: effect,
        lightingEnabled: lightingEnabled,
        brightnessLevel: brightness,
        speedLevel: tempo,
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

  private var controls: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(studioText("내장 모드", "Onboard mode", language: language))
        .font(.headline)

      Toggle(
        studioText("조명 켜기", "Lighting enabled", language: language),
        isOn: $lightingEnabled
      )
      .toggleStyle(.switch)

      HStack(spacing: 12) {
        Text(studioText("효과", "Effect", language: language))
        Spacer()
        Picker(studioText("효과", "Effect", language: language), selection: $effect) {
          ForEach(AK47OnboardLightingEffect.allCases) { item in
            Text(String(format: "%02d · %@", item.rawValue, item.resourceName))
              .tag(item)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 230)
      }

      capabilitySummary

      if supportsDirection {
        VStack(alignment: .leading, spacing: 7) {
          Label(
            effect.configurationCapabilities.contains(.horizontalDirection)
              ? studioText("좌우 방향", "Horizontal direction", language: language)
              : studioText("상하 방향", "Vertical direction", language: language),
            systemImage: effect.configurationCapabilities.contains(.horizontalDirection)
              ? "arrow.left.and.right" : "arrow.up.and.down"
          )
          .font(.callout)
          Picker(
            studioText("방향 원시값", "Direction raw value", language: language),
            selection: $direction
          ) {
            Text("Raw 0").tag(0)
            Text("Raw 1").tag(1)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          Text(
            studioText(
              "Windows 앱에서 확인된 원시값을 그대로 보존합니다.",
              "Preserves the raw value identified in the Windows app.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .disabled(!lightingEnabled)
      }

      if effect.configurationCapabilities.contains(.paletteToggle) {
        VStack(alignment: .leading, spacing: 7) {
          Label(
            studioText("색상 방식", "Color mode", language: language),
            systemImage: "paintpalette"
          )
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
        .disabled(!lightingEnabled)
      }

      if effect.configurationCapabilities.contains(.brightness) {
        ControlSlider(
          title: studioText("밝기", "Brightness", language: language),
          value: $brightness,
          symbol: "sun.max",
          valueLabel: "\(Int(brightness.rounded())) / 5"
        )
        .disabled(!lightingEnabled)
      }

      ControlSlider(
        title: studioText("효과 속도", "Effect speed", language: language),
        value: $tempo,
        symbol: "speedometer",
        valueLabel: "\(Int(tempo.rounded())) / 5"
      )
      .disabled(!lightingEnabled || !effect.configurationCapabilities.contains(.speed))
      .opacity(effect.configurationCapabilities.contains(.speed) ? 1 : 0.42)

      HStack {
        Button {
          previewRevision += 1
          savedLocally = false
        } label: {
          Label(
            studioText("미리보기 다시 시작", "Restart preview", language: language),
            systemImage: "arrow.counterclockwise"
          )
        }
        .buttonStyle(.bordered)

        Button(action: saveProfile) {
          Label(
            studioText("프로필에 저장", "Save to profile", language: language),
            systemImage: "square.and.arrow.down"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .studioPanel()
  }

  private var capabilitySummary: some View {
    let capabilities = effect.configurationCapabilities
    return VStack(alignment: .leading, spacing: 7) {
      Text(studioText("확인된 조절 항목", "Identified controls", language: language))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 7) {
        capabilityChip(studioText("밝기", "Brightness", language: language))
        if capabilities.contains(.speed) {
          capabilityChip(studioText("속도", "Speed", language: language))
        }
        if capabilities.contains(.horizontalDirection) {
          capabilityChip(studioText("좌우 방향", "Left/right", language: language))
        }
        if capabilities.contains(.verticalDirection) {
          capabilityChip(studioText("상하 방향", "Up/down", language: language))
        }
        if capabilities.contains(.directRGB) {
          capabilityChip("RGB")
        }
        if capabilities.contains(.paletteToggle) {
          capabilityChip(studioText("팔레트", "Palette", language: language))
        }
      }
    }
  }

  private func capabilityChip(_ label: String) -> some View {
    Text(label)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(StudioPalette.blue.opacity(0.1), in: Capsule())
      .foregroundStyle(StudioPalette.blue)
  }

  private var palettePanel: some View {
    let supportsRGB = effect.configurationCapabilities.contains(.directRGB)
    return VStack(alignment: .leading, spacing: 18) {
      Text(studioText("로컬 색상 시안", "Local color study", language: language))
        .font(.headline)
      ColorPicker(studioText("기본 색", "Base color", language: language), selection: $firstColor)
      ColorPicker(
        studioText("강조 색", "Accent color", language: language),
        selection: $secondColor
      )

      Divider()

      Text(studioText("빠른 조합", "Quick pairs", language: language))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        PaletteButton(colors: [StudioPalette.mint, StudioPalette.violet]) {
          firstColor = StudioPalette.mint
          secondColor = StudioPalette.violet
        }
        PaletteButton(colors: [StudioPalette.blue, StudioPalette.coral]) {
          firstColor = StudioPalette.blue
          secondColor = StudioPalette.coral
        }
        PaletteButton(colors: [.orange, .pink]) {
          firstColor = .orange
          secondColor = .pink
        }
      }
      if !supportsRGB {
        Text(
          studioText(
            "이 모드에서는 직접 RGB 조절 항목이 확인되지 않아 색상 편집을 사용할 수 없습니다.",
            "Direct RGB controls were not identified for this mode, so color editing is unavailable.",
            language: language
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      } else if colorful && effect.configurationCapabilities.contains(.paletteToggle) {
        Text(
          studioText(
            "Colorful을 선택하면 펌웨어 팔레트가 사용됩니다. RGB 값은 단색으로 돌아올 때를 위해 유지됩니다.",
            "Colorful uses the firmware palette. RGB values are retained for switching back to single color.",
            language: language
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .disabled(!lightingEnabled || !supportsRGB)
    .opacity(supportsRGB ? 1 : 0.52)
    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
    .studioPanel()
  }

  private func saveProfile() {
    profileStore.updateLighting(
      LightingProfile(
        enabled: lightingEnabled,
        effectIdentifier: effect.effectIdentifier,
        brightnessPercent: Int(brightness.rounded()) * 20,
        speedPercent: Int(tempo.rounded()) * 20,
        direction: supportsDirection ? direction : 0,
        colorful: effect.configurationCapabilities.contains(.paletteToggle) ? colorful : false,
        baseColor: firstColor.profileRGBColor,
        accentColor: secondColor.profileRGBColor,
        perKey: perKeyDraft.entries
      )
    )
    profileStore.saveSelected()
    savedLocally = if case .saved = profileStore.status { true } else { false }
  }

  private func loadProfile() {
    let lighting = profileStore.selectedProfile.lighting
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
      AK47PhysicalLayout.keys.first(where: {
        perKeyDraft.entry(at: $0.lightIndex) != nil
      })?.lightIndex ?? AK47PhysicalLayout.keys.first?.lightIndex ?? 1
    perKeyPaintColor =
      perKeyDraft.entry(at: selectedLightIndex)?.color.swiftUIColor ?? firstColor
    previewRevision = 0
    savedLocally = false
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

private struct PaletteButton: View {
  let colors: [Color]
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 34, height: 34)
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.12)) }
    }
    .buttonStyle(.plain)
  }
}
