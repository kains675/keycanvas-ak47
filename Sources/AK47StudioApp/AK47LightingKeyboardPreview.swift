import AK47InspectorCore
import SwiftUI

struct AK47LightingKeyboardPreview: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let language: AppLanguage
  let effect: AK47OnboardLightingEffect
  let lightingEnabled: Bool
  let brightnessLevel: Double
  let speedLevel: Double
  let baseColor: AK47InspectorCore.RGBColor
  let accentColor: AK47InspectorCore.RGBColor
  let revision: Int

  @State private var epoch = Date()
  @State private var manualPresses: [AK47LightingPreviewPress] = []

  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 1.0 / 30.0,
        paused: !lightingEnabled || reduceMotion
      )
    ) { context in
      keyboard(at: previewTime(for: context.date))
    }
    .aspectRatio(
      AK47PhysicalLayout.canvasSize.width / AK47PhysicalLayout.canvasSize.height,
      contentMode: .fit
    )
    .onChange(of: effect) { _ in restart() }
    .onChange(of: revision) { _ in restart() }
    .onChange(of: lightingEnabled) { enabled in
      if enabled { restart() }
    }
  }

  private func keyboard(at time: TimeInterval) -> some View {
    let samples =
      lightingEnabled
      ? AK47LightingPreviewEngine.frame(
        effect: effect,
        time: time,
        speedLevel: speedLevel,
        brightnessLevel: brightnessLevel,
        baseColor: AK47LightingPreviewRGB(baseColor),
        accentColor: AK47LightingPreviewRGB(accentColor),
        manualPresses: manualPresses,
        includesSimulatedInput: effect.isReactive && !reduceMotion
      )
      : Dictionary(
        uniqueKeysWithValues: AK47PhysicalLayout.keys.map { ($0.id, AK47LightingPreviewSample.off) }
      )

    return GeometryReader { proxy in
      let scale = min(
        proxy.size.width / AK47PhysicalLayout.canvasSize.width,
        proxy.size.height / AK47PhysicalLayout.canvasSize.height
      )
      let xOffset = (proxy.size.width - AK47PhysicalLayout.canvasSize.width * scale) / 2
      let yOffset = (proxy.size.height - AK47PhysicalLayout.canvasSize.height * scale) / 2

      ZStack(alignment: .topLeading) {
        ForEach(AK47PhysicalLayout.keys) { key in
          previewKey(
            key,
            sample: samples[key.id] ?? .off,
            time: time,
            scale: scale
          )
          .position(
            x: xOffset + key.center.x * scale,
            y: yOffset + key.center.y * scale
          )
        }

        indicatorDots(scale: scale)
          .position(x: xOffset + 52.5 * scale, y: yOffset + 16 * scale)

        displayPlaceholder(scale: scale)
          .position(
            x: xOffset + AK47PhysicalLayout.lcdFrame.midX * scale,
            y: yOffset + AK47PhysicalLayout.lcdFrame.midY * scale
          )

        knobPlaceholder(scale: scale)
          .position(
            x: xOffset + AK47PhysicalLayout.knobFrame.midX * scale,
            y: yOffset + AK47PhysicalLayout.knobFrame.midY * scale
          )
      }
    }
  }

  private func previewKey(
    _ key: AK47PhysicalKey,
    sample: AK47LightingPreviewSample,
    time: TimeInterval,
    scale: CGFloat
  ) -> some View {
    let color = Color(
      red: sample.color.red,
      green: sample.color.green,
      blue: sample.color.blue
    )
    return Button {
      guard lightingEnabled, effect.isReactive else { return }
      manualPresses.append(AK47LightingPreviewEngine.press(for: key, at: time))
      if manualPresses.count > 16 {
        manualPresses.removeFirst(manualPresses.count - 16)
      }
    } label: {
      RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
        .fill(Color.white.opacity(0.055))
        .overlay {
          RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
            .fill(color.opacity(sample.intensity * 0.9))
        }
        .overlay {
          RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: max(0.5, scale * 0.7))
        }
        .overlay {
          Text(key.label)
            .font(
              .system(
                size: max(6.5, (key.width <= 32 ? 8.5 : 9) * scale),
                weight: .semibold,
                design: .rounded
              )
            )
            .foregroundStyle(Color.white.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, max(1, 3 * scale))
        }
        .shadow(
          color: color.opacity(sample.intensity * 0.68),
          radius: max(1, 7 * scale)
        )
    }
    .buttonStyle(.plain)
    .disabled(!lightingEnabled || !effect.isReactive)
    .frame(width: key.width * scale, height: key.height * scale)
    .accessibilityLabel(key.id)
    .accessibilityHidden(!effect.isReactive)
    .accessibilityHint(
      studioText(
        "조명 미리보기에서 이 키의 입력을 시뮬레이션합니다.",
        "Simulate this key press in the lighting preview.",
        language: language
      )
    )
  }

  private func indicatorDots(scale: CGFloat) -> some View {
    VStack(spacing: max(1, 4 * scale)) {
      ForEach(0..<3, id: \.self) { _ in
        Circle()
          .fill(Color.white.opacity(0.34))
          .frame(width: max(2, 5 * scale), height: max(2, 5 * scale))
      }
    }
  }

  private func displayPlaceholder(scale: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: max(3, 7 * scale), style: .continuous)
      .fill(
        LinearGradient(
          colors: [StudioPalette.blue.opacity(0.38), StudioPalette.violet.opacity(0.24)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(
        width: AK47PhysicalLayout.lcdFrame.width * scale,
        height: AK47PhysicalLayout.lcdFrame.height * scale
      )
      .overlay {
        Text("LCD")
          .font(.system(size: max(6, 8 * scale), weight: .bold, design: .rounded))
          .tracking(max(0.5, scale))
          .foregroundStyle(Color.white.opacity(0.72))
      }
      .overlay {
        RoundedRectangle(cornerRadius: max(3, 7 * scale), style: .continuous)
          .strokeBorder(Color.white.opacity(0.12))
      }
      .accessibilityLabel(studioText("240×135 LCD", "240 by 135 LCD", language: language))
  }

  private func knobPlaceholder(scale: CGFloat) -> some View {
    Circle()
      .fill(Color.white.opacity(0.11))
      .frame(
        width: AK47PhysicalLayout.knobFrame.width * scale,
        height: AK47PhysicalLayout.knobFrame.height * scale
      )
      .overlay {
        Circle()
          .strokeBorder(Color.white.opacity(0.18), lineWidth: max(0.5, scale))
          .padding(max(1, 2 * scale))
      }
      .overlay(alignment: .top) {
        Capsule()
          .fill(Color.white.opacity(0.42))
          .frame(width: max(1, 2 * scale), height: max(3, 7 * scale))
          .padding(.top, max(2, 5 * scale))
      }
      .accessibilityLabel(studioText("회전 노브", "Rotary knob", language: language))
  }

  private func previewTime(for date: Date) -> TimeInterval {
    reduceMotion ? 0 : max(0, date.timeIntervalSince(epoch))
  }

  private func restart() {
    epoch = Date()
    manualPresses = []
  }
}
