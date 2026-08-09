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
            "앱 표시 방식과 로컬 초안, 명시적으로 확인하는 제한적 장치 작업을 관리합니다.",
            "Manage appearance, local drafts, and explicitly confirmed bounded device operations.",
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

          Divider()

          VStack(alignment: .leading, spacing: 10) {
            Button {
              profileStore.presentWindowsBackupImportPanel(language: language)
            } label: {
              Label(
                studioText(
                  "Windows 백업 가져오기…",
                  "Import Windows backup…",
                  language: language
                ),
                systemImage: "square.and.arrow.down.on.square"
              )
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioPalette.blue)

            Text(
              studioText(
                "Windows 설정 앱을 닫은 뒤 ‘Archon AK47 Driver Files’ 폴더를 직접 선택하세요. SQLite DB는 읽기 전용으로 제한 조회하고, 화면용 PNG 프레임은 원본 치수와 지연 시간이 보존된 GIF로 앱 로컬 폴더에 복사합니다. 화면 캔버스는 240×135이며, 프로그램을 실행하거나 네트워크·키보드에 접근하지 않습니다.",
                "Close the Windows settings app, then select the ‘Archon AK47 Driver Files’ folder itself. KeyCanvas reads a bounded set of SQLite fields in read-only mode and preserves screen PNG frames as local GIFs with their source dimensions and delays. The screen canvas remains 240×135; no program is launched and neither the network nor keyboard is accessed.",
                language: language
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
              studioText(
                "Windows 숫자 설정의 단위나 의미가 확인되지 않은 값은 임의로 변환하지 않고 원시 가져오기 메타데이터로만 보존합니다.",
                "Windows numeric settings whose units or meanings are unverified are retained only as raw import metadata, without guessed conversions.",
                language: language
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
            profileStore.statusLabel(in: language),
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
              "이 절전·디바운스·보고율·Fn 값은 프로필 형식에만 저장되며 현재 빌드에서는 키보드로 전송되지 않습니다.",
              "These sleep, debounce, report-rate, and Fn values stay in the profile format and are not transmitted by this build.",
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
                "기본 새로고침과 직접 report 진단은 읽기 전용입니다. 키별 F5 조회, 시계 동기화, 선택한 내장 모드 하나, 완성된 84키 RGB 적용은 각각 별도 확인이 필요합니다. 유선 revision 0x0115의 FF13 Feature 채널만 사용하며, 세 적용 작업은 35ms 간격을 두고 모든 비동기 작업은 360ms로 제한합니다. ACK byte 3을 검증하고 재시도·output·LCD·키맵·매크로·펌웨어 작업은 하지 않습니다.",
                "Normal refresh and direct report diagnostics are read only. The per-key F5 query, clock sync, one selected onboard mode, and a complete 84-key RGB apply each require separate confirmation. Only the wired revision 0x0115 FF13 Feature channel is used; the three apply paths use 35 ms pacing and every asynchronous operation has a 360 ms limit. ACK byte 3 is validated, with no retry, output, LCD, keymap, macro, or firmware operation.",
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
            value: studioText(
              "로컬 편집 · 확인형 장치 작업", "Local editing · confirmed device operations",
              language: language))
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
    case .imported: "square.and.arrow.down.on.square"
    case .unsaved: "pencil.circle"
    case .ready: "folder"
    }
  }

  private var profileStatusTint: Color {
    switch profileStore.status {
    case .failed: StudioPalette.coral
    case .saved: StudioPalette.mint
    case .imported: StudioPalette.mint
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
