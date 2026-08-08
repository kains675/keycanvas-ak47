import AK47InspectorCore
import SwiftUI

struct DisplayComposerView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var profileStore: LocalProfileStore
  @State private var theme = "Orbit"
  @State private var accent = StudioPalette.mint
  @State private var showClock = true
  @State private var showBattery = true
  @State private var note = "HELLO, MAC"
  @State private var savedLocally = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("240 × 135 시안", "240 × 135 study", language: language),
          title: studioText("디스플레이", "Display", language: language),
          detail: studioText(
            "내장 화면을 위한 구성을 미리 그려 봅니다. 이미지를 업로드하거나 장치에 쓰지 않습니다.",
            "Sketch a composition for the built-in screen. No image is uploaded or written to the device.",
            language: language
          )
        )

        HStack(alignment: .top, spacing: 20) {
          displayPreview
            .frame(maxWidth: .infinity)
          displayControls
            .frame(width: 300)
        }

        HStack(spacing: 14) {
          DisplayPreset(
            name: "Orbit", colors: [StudioPalette.ink, StudioPalette.mint], selection: $theme)
          DisplayPreset(
            name: "Horizon", colors: [StudioPalette.blue, StudioPalette.coral], selection: $theme)
          DisplayPreset(name: "Mono", colors: [.black, .gray], selection: $theme)
        }

        DemoNotice()
      }
      .padding(28)
      .frame(maxWidth: 1060)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in loadProfile() }
    .onChange(of: theme) { _ in savedLocally = false }
    .onChange(of: accent) { _ in savedLocally = false }
    .onChange(of: showClock) { _ in savedLocally = false }
    .onChange(of: showBattery) { _ in savedLocally = false }
    .onChange(of: note) { newValue in
      if newValue.count > 128 {
        note = String(newValue.prefix(128))
      }
      savedLocally = false
    }
  }

  private var displayPreview: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(studioText("화면 미리보기", "Screen preview", language: language))
          .font(.headline)
        Spacer()
        StatusPill(
          label: savedLocally
            ? studioText("로컬 저장됨", "Saved locally", language: language)
            : studioText("렌더링만", "Render only", language: language),
          symbol: savedLocally ? "checkmark.circle" : "eye",
          tint: StudioPalette.mint
        )
      }

      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(StudioPalette.ink)
        LinearGradient(
          colors: previewColors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .opacity(0.72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        Circle()
          .stroke(accent.opacity(0.48), lineWidth: 18)
          .frame(width: 138, height: 138)
          .offset(x: 145, y: -48)

        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 7) {
            KeyCanvasMark(size: 34)
            Text(note.isEmpty ? "KEYCANVAS" : note.uppercased())
              .font(.system(size: 21, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(studioText("로컬 화면 시안", "LOCAL SCREEN STUDY", language: language))
              .font(.caption2.weight(.semibold))
              .tracking(1.1)
              .foregroundStyle(.white.opacity(0.64))
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 5) {
            if showClock {
              Text("10:47")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.white)
            }
            if showBattery {
              Label("82%", systemImage: "battery.75")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            }
          }
        }
        .padding(24)
      }
      .aspectRatio(240 / 135, contentMode: .fit)
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12))
      }
      .shadow(color: StudioPalette.ink.opacity(0.20), radius: 18, y: 8)

      HStack {
        Text("240 × 135 px")
        Spacer()
        Text(studioText("정적 SwiftUI 시안", "Static SwiftUI study", language: language))
      }
      .font(.caption.monospaced())
      .foregroundStyle(.secondary)
    }
    .studioPanel()
  }

  private var displayControls: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(studioText("구성 요소", "Composition", language: language))
        .font(.headline)
      TextField(studioText("짧은 문구", "Short message", language: language), text: $note)
        .textFieldStyle(.roundedBorder)
      ColorPicker(studioText("강조 색", "Accent", language: language), selection: $accent)
      Toggle(studioText("시계 표시", "Show clock", language: language), isOn: $showClock)
      Toggle(studioText("배터리 예시 표시", "Show sample battery", language: language), isOn: $showBattery)
      Divider()
      Label(
        studioText(
          "GIF 가져오기와 전송 기능은 비활성 상태입니다.", "GIF import and transfer are disabled.", language: language
        ),
        systemImage: "lock"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Button(action: saveProfile) {
        Label(
          studioText("프로필에 저장", "Save to profile", language: language),
          systemImage: "square.and.arrow.down"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.blue)
      Spacer(minLength: 0)
    }
    .frame(minHeight: 315, alignment: .topLeading)
    .studioPanel()
  }

  private var previewColors: [Color] {
    switch theme {
    case "Horizon": [StudioPalette.blue, StudioPalette.coral, StudioPalette.ink]
    case "Mono": [.black, .gray.opacity(0.6), .black]
    default:
      [StudioPalette.ink, StudioPalette.violet.opacity(0.75), StudioPalette.mint.opacity(0.6)]
    }
  }

  private func saveProfile() {
    let current = profileStore.selectedProfile.tft
    profileStore.updateTFT(
      TFTProfile(
        enabled: current.enabled,
        canvasWidth: 240,
        canvasHeight: 135,
        frameRate: current.frameRate,
        assets: current.assets,
        playlist: current.playlist,
        themeIdentifier: theme.lowercased(),
        message: note,
        accentColor: accent.profileRGBColor,
        showsClock: showClock,
        showsBattery: showBattery
      )
    )
    profileStore.saveSelected()
    if case .saved = profileStore.status {
      savedLocally = true
    } else {
      savedLocally = false
    }
  }

  private func loadProfile() {
    let tft = profileStore.selectedProfile.tft
    if let identifier = tft.themeIdentifier {
      theme =
        ["Orbit", "Horizon", "Mono"].first(where: {
          $0.lowercased() == identifier.lowercased()
        }) ?? "Orbit"
    } else {
      theme = "Orbit"
    }
    note = tft.message ?? "HELLO, MAC"
    accent = tft.accentColor?.swiftUIColor ?? StudioPalette.mint
    showClock = tft.showsClock ?? true
    showBattery = tft.showsBattery ?? true
    savedLocally = false
  }
}

private struct DisplayPreset: View {
  let name: String
  let colors: [Color]
  @Binding var selection: String

  var body: some View {
    Button {
      selection = name
    } label: {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: 54, height: 34)
        Text(name)
          .font(.callout.weight(.semibold))
        Spacer()
        Image(systemName: selection == name ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selection == name ? StudioPalette.blue : .secondary)
      }
      .frame(maxWidth: .infinity)
      .studioPanel(padding: 12)
    }
    .buttonStyle(.plain)
  }
}
