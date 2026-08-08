import AK47InspectorCore
import SwiftUI

struct LightingView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var profileStore: LocalProfileStore
  @State private var scene = "Flow"
  @State private var brightness = 0.72
  @State private var tempo = 0.38
  @State private var firstColor = StudioPalette.mint
  @State private var secondColor = StudioPalette.violet
  @State private var previewUpdated = false
  @State private var savedLocally = false

  private let scenes = ["Flow", "Breath", "Still"]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("로컬 장면", "Local scene", language: language),
          title: studioText("조명", "Lighting", language: language),
          detail: studioText(
            "색의 흐름을 만들어 보는 시뮬레이션입니다. 이 값은 키보드로 전송되지 않습니다.",
            "Shape a color flow in this simulation. These values are never sent to the keyboard.",
            language: language
          )
        )

        lightingCanvas

        HStack(alignment: .top, spacing: 16) {
          controls
          palettePanel
        }

        DemoNotice()
      }
      .padding(28)
      .frame(maxWidth: 1050)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in loadProfile() }
    .onChange(of: scene) { _ in savedLocally = false }
    .onChange(of: brightness) { _ in savedLocally = false }
    .onChange(of: tempo) { _ in savedLocally = false }
    .onChange(of: firstColor) { _ in savedLocally = false }
    .onChange(of: secondColor) { _ in savedLocally = false }
  }

  private var lightingCanvas: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(studioText("색상 미리보기", "Color preview", language: language))
            .font(.headline)
          Text(
            studioText(
              "추상 키 배열 · 장치 크기와 무관", "Abstract key field · not device scale", language: language)
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        StatusPill(
          label: savedLocally
            ? studioText("로컬 저장됨", "Saved locally", language: language)
            : (previewUpdated
              ? studioText("미리보기 갱신됨", "Preview updated", language: language)
              : studioText("시뮬레이션", "Simulation", language: language)),
          symbol: savedLocally ? "checkmark.circle" : "sparkles",
          tint: savedLocally ? StudioPalette.mint : StudioPalette.violet
        )
      }

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 12), spacing: 7)
      {
        ForEach(0..<48, id: \.self) { index in
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(keyColor(at: index))
            .frame(height: 30)
            .shadow(color: keyColor(at: index).opacity(0.5 * brightness), radius: 7)
        }
      }
      .padding(18)
      .background(StudioPalette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .studioPanel()
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(studioText("장면 조절", "Scene controls", language: language))
        .font(.headline)

      Picker(studioText("움직임", "Motion", language: language), selection: $scene) {
        ForEach(scenes, id: \.self, content: Text.init)
      }
      .pickerStyle(.segmented)

      ControlSlider(
        title: studioText("밝기", "Brightness", language: language),
        value: $brightness,
        symbol: "sun.max",
        valueLabel: "\(Int(brightness * 100))%"
      )

      ControlSlider(
        title: studioText("흐름 속도", "Flow speed", language: language),
        value: $tempo,
        symbol: "speedometer",
        valueLabel: "\(Int(tempo * 10 + 1))"
      )

      HStack {
        Button {
          previewUpdated.toggle()
          savedLocally = false
        } label: {
          Label(
            studioText("다시 그리기", "Redraw", language: language),
            systemImage: "arrow.clockwise"
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

  private var palettePanel: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(studioText("색상 조합", "Color pair", language: language))
        .font(.headline)
      ColorPicker(studioText("시작 색", "Start color", language: language), selection: $firstColor)
      ColorPicker(studioText("끝 색", "End color", language: language), selection: $secondColor)

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
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
    .studioPanel()
  }

  private func keyColor(at index: Int) -> Color {
    let position = Double(index % 12) / 11
    return position < 0.5
      ? firstColor.opacity(0.45 + brightness * 0.55)
      : secondColor.opacity(0.45 + brightness * 0.55)
  }

  private func saveProfile() {
    profileStore.updateLighting(
      LightingProfile(
        enabled: true,
        effectIdentifier: scene.lowercased(),
        brightnessPercent: Int((brightness * 100).rounded()),
        speedPercent: Int((tempo * 100).rounded()),
        baseColor: firstColor.profileRGBColor,
        accentColor: secondColor.profileRGBColor
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
    let lighting = profileStore.selectedProfile.lighting
    scene =
      scenes.first(where: { $0.lowercased() == lighting.effectIdentifier.lowercased() }) ?? "Flow"
    brightness = Double(lighting.brightnessPercent) / 100
    tempo = Double(lighting.speedPercent) / 100
    firstColor = lighting.baseColor.swiftUIColor
    secondColor = lighting.accentColor?.swiftUIColor ?? StudioPalette.violet
    previewUpdated = false
    savedLocally = false
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
      Slider(value: $value, in: 0...1)
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
