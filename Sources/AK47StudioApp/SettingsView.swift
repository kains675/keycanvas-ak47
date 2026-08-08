import AK47InspectorCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: StudioModel
  @ObservedObject private var profileStore: LocalProfileStore
  @Environment(\.studioLanguage) private var language
  @AppStorage("reopenLastSection") private var reopenLastSection = true
  @AppStorage("showSafetyNotes") private var showSafetyNotes = true
  @AppStorage("inspectorRefreshesAtLaunch") private var inspectorRefreshesAtLaunch = true
  @State private var sleepTimeout = -1
  @State private var debounce = 5.0
  @State private var reportRate = 1_000
  @State private var functionLayerEnabled = true
  @State private var deviceDraftSaved = false

  init(model: StudioModel) {
    self.model = model
    self._profileStore = ObservedObject(wrappedValue: model.profileStore)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("KeyCanvas 환경", "KeyCanvas preferences", language: language),
          title: studioText("설정", "Settings", language: language),
          detail: studioText(
            "앱의 표시 방식과 읽기 전용 검사 동작을 선택합니다.",
            "Choose how the app looks and how its read-only inspection behaves.",
            language: language
          )
        )

        SettingsGroup(
          title: studioText("로컬 프로필", "Local profile", language: language),
          symbol: "folder"
        ) {
          TextField(
            studioText("프로필 이름", "Profile name", language: language),
            text: Binding(
              get: { profileStore.selectedProfile.name },
              set: { profileStore.renameSelected(to: $0) }
            )
          )
          .textFieldStyle(.roundedBorder)

          HStack {
            Button(studioText("새 프로필", "New profile", language: language)) {
              profileStore.newProfile()
            }
            Button(studioText("로컬에 저장", "Save locally", language: language)) {
              profileStore.saveSelected()
            }
            Button(studioText("JSON 내보내기…", "Export JSON…", language: language)) {
              profileStore.presentExportPanel()
            }
          }

          Text(
            studioText(
              "저장 위치: ~/Library/Application Support/KeyCanvas",
              "Saved in ~/Library/Application Support/KeyCanvas",
              language: language
            )
          )
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)

          Label(
            profileStore.statusLabel,
            systemImage: profileStatusSymbol
          )
          .font(.caption)
          .foregroundStyle(profileStatusTint)
        }

        SettingsGroup(
          title: studioText("언어", "Language", language: language),
          symbol: "character.bubble"
        ) {
          Picker(studioText("앱 언어", "App language", language: language), selection: $model.language)
          {
            ForEach(AppLanguage.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 320)

          Text(
            studioText(
              "언어 선택은 현재 실행 중인 앱에 바로 적용됩니다.",
              "The language choice applies immediately to this running app.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        SettingsGroup(
          title: studioText("장치 설정 초안", "Device settings draft", language: language),
          symbol: "slider.horizontal.3"
        ) {
          Text(
            studioText(
              "이 값은 프로필 형식에만 저장됩니다. 실제 하드웨어 지원 범위가 확인되기 전에는 키보드로 전송되지 않습니다.",
              "These values are stored only in the profile format and are not sent until hardware support is verified.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Picker(studioText("절전 시간", "Sleep timeout", language: language), selection: $sleepTimeout)
          {
            Text(studioText("지정 안 함", "Unspecified", language: language)).tag(-1)
            Text(studioText("사용 안 함", "Never", language: language)).tag(0)
            Text(studioText("1분", "1 minute", language: language)).tag(60)
            Text(studioText("5분", "5 minutes", language: language)).tag(300)
            Text(studioText("30분", "30 minutes", language: language)).tag(1_800)
          }

          VStack(spacing: 6) {
            HStack {
              Text(studioText("디바운스", "Debounce", language: language))
              Spacer()
              Text("\(Int(debounce)) ms")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Slider(value: $debounce, in: 0...20, step: 1)
          }

          Picker(
            studioText("보고율 메타데이터", "Report-rate metadata", language: language),
            selection: $reportRate
          ) {
            ForEach([125, 250, 500, 1_000], id: \.self) { rate in
              Text("\(rate) Hz").tag(rate)
            }
          }

          Toggle(
            studioText("Fn 레이어 사용", "Enable Fn layer", language: language),
            isOn: $functionLayerEnabled)

          Button(action: saveDeviceDraft) {
            Label(
              deviceDraftSaved
                ? studioText("로컬 저장됨", "Saved locally", language: language)
                : studioText("설정 초안 저장", "Save settings draft", language: language),
              systemImage: deviceDraftSaved ? "checkmark" : "square.and.arrow.down"
            )
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.blue)
        }

        SettingsGroup(
          title: studioText("작업 공간", "Workspace", language: language),
          symbol: "rectangle.3.group"
        ) {
          Toggle(
            studioText("마지막 섹션 다시 열기", "Reopen the last section", language: language),
            isOn: $reopenLastSection)
          Toggle(
            studioText("안전 안내 계속 표시", "Keep safety notes visible", language: language),
            isOn: $showSafetyNotes)
        }

        SettingsGroup(
          title: studioText("장치 검사", "Device inspection", language: language),
          symbol: "magnifyingglass"
        ) {
          Toggle(
            studioText("앱 시작 시 읽기 전용 새로고침", "Read-only refresh at launch", language: language),
            isOn: $inspectorRefreshesAtLaunch)
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
              .foregroundStyle(StudioPalette.mint)
            Text(
              studioText(
                "KeyCanvas는 IOHID 레지스트리 속성만 열거합니다. 장치를 열거나 report를 보내는 코드 경로가 없습니다.",
                "KeyCanvas only enumerates IOHID registry properties. It has no code path that opens the device or sends reports.",
                language: language
              )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }
        }

        SettingsGroup(
          title: studioText("이 빌드에 관하여", "About this build", language: language),
          symbol: "info.circle"
        ) {
          LabeledContent(studioText("앱", "App", language: language), value: "KeyCanvas")
          LabeledContent(
            studioText("모드", "Mode", language: language),
            value: studioText("데모 · 읽기 전용", "Demo · read-only", language: language))
          LabeledContent(
            studioText("최소 시스템", "Minimum system", language: language), value: "macOS 13")
          Text(
            studioText(
              "이 프로젝트는 독자적인 인터페이스이며 제조사 소프트웨어나 자산을 포함하지 않습니다.",
              "This is an independent interface and contains no vendor software or assets.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(28)
      .frame(maxWidth: 820)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadDeviceDraft)
    .onChange(of: profileStore.selectedID) { _ in loadDeviceDraft() }
    .onChange(of: sleepTimeout) { _ in deviceDraftSaved = false }
    .onChange(of: debounce) { _ in deviceDraftSaved = false }
    .onChange(of: reportRate) { _ in deviceDraftSaved = false }
    .onChange(of: functionLayerEnabled) { _ in deviceDraftSaved = false }
  }

  private func saveDeviceDraft() {
    profileStore.updateSettings(
      DeviceSettings(
        sleepTimeoutSeconds: sleepTimeout < 0 ? nil : sleepTimeout,
        debounceMilliseconds: Int(debounce),
        reportRateHz: reportRate,
        functionLayerEnabled: functionLayerEnabled
      )
    )
    profileStore.saveSelected()
    if case .saved = profileStore.status {
      deviceDraftSaved = true
    } else {
      deviceDraftSaved = false
    }
  }

  private func loadDeviceDraft() {
    let settings = profileStore.selectedProfile.settings
    sleepTimeout = settings.sleepTimeoutSeconds ?? -1
    debounce = Double(settings.debounceMilliseconds)
    reportRate =
      [125, 250, 500, 1_000].contains(settings.reportRateHz)
      ? settings.reportRateHz
      : 1_000
    functionLayerEnabled = settings.functionLayerEnabled
    deviceDraftSaved = false
  }

  private var profileStatusSymbol: String {
    switch profileStore.status {
    case .failed: "exclamationmark.triangle"
    case .saved: "checkmark.circle"
    case .unsaved: "pencil.circle"
    case .ready: "folder"
    }
  }

  private var profileStatusTint: Color {
    switch profileStore.status {
    case .failed: StudioPalette.coral
    case .saved: StudioPalette.mint
    case .unsaved: StudioPalette.violet
    case .ready: .secondary
    }
  }
}

private struct SettingsGroup<Content: View>: View {
  let title: String
  let symbol: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(title, systemImage: symbol)
        .font(.headline)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studioPanel()
  }
}
