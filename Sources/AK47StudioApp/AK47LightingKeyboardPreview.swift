import AK47InspectorCore
import SwiftUI

struct AK47LightingKeyboardPreview: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let language: AppLanguage
  let effect: AK47OnboardLightingEffect
  let lightingEnabled: Bool
  let brightnessLevel: Double
  let speedLevel: Double
  let direction: Int
  let colorful: Bool
  let baseColor: AK47InspectorCore.RGBColor
  let revision: Int

  @StateObject private var session = AK47LightingPreviewSession()

  var body: some View {
    keyboard(frame: session.frame)
      .aspectRatio(
        AK47PhysicalLayout.canvasSize.width / AK47PhysicalLayout.canvasSize.height,
        contentMode: .fit
      )
      .onAppear {
        synchronizeSession(restart: true)
        session.setPaused(!lightingEnabled || reduceMotion)
        session.start()
      }
      .onDisappear { session.stop() }
      .onChange(of: previewConfiguration) { configuration in
        session.configure(
          configuration,
          includesDeterministicDemoInput: effect.isReactive && !reduceMotion
        )
        session.setPaused(!lightingEnabled || reduceMotion)
      }
      .onChange(of: revision) { _ in synchronizeSession(restart: true) }
      .onChange(of: reduceMotion) { _ in
        synchronizeSession(restart: false)
        session.setPaused(!lightingEnabled || reduceMotion)
      }
  }

  private var previewConfiguration: AK47LightingPreviewConfiguration {
    AK47LightingPreviewConfiguration(
      effect: effect,
      isEnabled: lightingEnabled,
      speedLevel: Int(speedLevel.rounded()),
      brightnessLevel: Int(brightnessLevel.rounded()),
      direction: direction,
      colorful: colorful,
      baseColor: AK47LightingPreviewRGB(baseColor)
    )
  }

  private func synchronizeSession(restart: Bool) {
    session.configure(
      previewConfiguration,
      restart: restart,
      includesDeterministicDemoInput: effect.isReactive && !reduceMotion
    )
  }

  private func keyboard(frame: AK47LightingPreviewFrame) -> some View {
    GeometryReader { proxy in
      let scale = min(
        proxy.size.width / AK47PhysicalLayout.canvasSize.width,
        proxy.size.height / AK47PhysicalLayout.canvasSize.height
      )
      let xOffset = (proxy.size.width - AK47PhysicalLayout.canvasSize.width * scale) / 2
      let yOffset = (proxy.size.height - AK47PhysicalLayout.canvasSize.height * scale) / 2

      ZStack(alignment: .topLeading) {
        ForEach(Array(AK47PhysicalLayout.keys.enumerated()), id: \.element.id) { ordinal, key in
          if let keyIndex = AK47LightingPreviewKeyIndex(rawValue: ordinal) {
            previewKey(
              key,
              keyIndex: keyIndex,
              pixel: frame[keyIndex],
              scale: scale
            )
            .position(
              x: xOffset + key.center.x * scale,
              y: yOffset + key.center.y * scale
            )
          }
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
    keyIndex: AK47LightingPreviewKeyIndex,
    pixel: AK47LightingPreviewPixel,
    scale: CGFloat
  ) -> some View {
    let color = Color(
      red: pixel.normalizedRed,
      green: pixel.normalizedGreen,
      blue: pixel.normalizedBlue
    )
    return Button {
      guard lightingEnabled, effect.isReactive else { return }
      session.enqueueTap(key: keyIndex)
    } label: {
      RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
        .fill(Color.white.opacity(0.055))
        .overlay {
          RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
            .fill(color.opacity(0.9))
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
          color: color.opacity(pixel.normalizedIntensity * 0.68),
          radius: max(1, 7 * scale)
        )
    }
    .buttonStyle(.plain)
    .disabled(!lightingEnabled || !effect.isReactive)
    .frame(width: key.width * scale, height: key.height * scale)
    .accessibilityLabel(key.id)
    .accessibilityHidden(!lightingEnabled || !effect.isReactive)
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
}
