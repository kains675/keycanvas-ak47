import AK47InspectorCore
import AppKit
import SwiftUI

private struct StudioLanguageKey: EnvironmentKey {
  static let defaultValue: AppLanguage = .korean
}

extension EnvironmentValues {
  var studioLanguage: AppLanguage {
    get { self[StudioLanguageKey.self] }
    set { self[StudioLanguageKey.self] = newValue }
  }
}

func studioText(_ korean: String, _ english: String, language: AppLanguage) -> String {
  language == .korean ? korean : english
}

extension AK47InspectorCore.RGBColor {
  var swiftUIColor: Color {
    Color(
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255
    )
  }
}

extension Color {
  var profileRGBColor: AK47InspectorCore.RGBColor {
    let converted = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
    return AK47InspectorCore.RGBColor(
      red: UInt8((min(max(converted.redComponent, 0), 1) * 255).rounded()),
      green: UInt8((min(max(converted.greenComponent, 0), 1) * 255).rounded()),
      blue: UInt8((min(max(converted.blueComponent, 0), 1) * 255).rounded())
    )
  }
}

enum StudioPalette {
  static let ink = Color(red: 0.10, green: 0.12, blue: 0.16)
  static let muted = Color(red: 0.43, green: 0.47, blue: 0.54)
  static let mint = Color(red: 0.20, green: 0.78, blue: 0.65)
  static let blue = Color(red: 0.31, green: 0.55, blue: 0.96)
  static let violet = Color(red: 0.60, green: 0.42, blue: 0.96)
  static let coral = Color(red: 0.98, green: 0.47, blue: 0.50)
}

struct StudioPanel: ViewModifier {
  var padding: CGFloat = 18

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08))
      }
  }
}

extension View {
  func studioPanel(padding: CGFloat = 18) -> some View {
    modifier(StudioPanel(padding: padding))
  }
}

struct KeyCanvasMark: View {
  var size: CGFloat = 34

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        .fill(StudioPalette.ink)

      RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
        .stroke(Color.white.opacity(0.78), lineWidth: max(1, size * 0.045))
        .padding(size * 0.19)

      WaveRibbon()
        .stroke(
          LinearGradient(
            colors: [StudioPalette.mint, StudioPalette.blue, StudioPalette.violet],
            startPoint: .leading,
            endPoint: .trailing
          ),
          style: StrokeStyle(lineWidth: max(2, size * 0.10), lineCap: .round)
        )
        .padding(size * 0.16)
    }
    .frame(width: size, height: size)
    .accessibilityLabel("KeyCanvas")
  }
}

private struct WaveRibbon: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.14))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.14),
      control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY),
      control2: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.maxY)
    )
    return path
  }
}

struct StudioSectionHeader: View {
  let eyebrow: String
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(eyebrow.uppercased())
        .font(.caption.weight(.semibold))
        .tracking(1.3)
        .foregroundStyle(StudioPalette.blue)
      Text(title)
        .font(.system(size: 28, weight: .bold, design: .rounded))
      Text(detail)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct StatusPill: View {
  let label: String
  let symbol: String
  var tint: Color = StudioPalette.mint

  var body: some View {
    Label(label, systemImage: symbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(tint.opacity(0.12), in: Capsule())
  }
}

struct MetricTile: View {
  let title: String
  let value: String
  let symbol: String
  var tint: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.title3.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.headline.monospacedDigit())
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .studioPanel(padding: 14)
  }
}

struct DemoNotice: View {
  @Environment(\.studioLanguage) private var language
  @AppStorage("showSafetyNotes") private var showSafetyNotes = true
  var compact = false

  var body: some View {
    Group {
      if showSafetyNotes {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "pencil.and.outline")
            .foregroundStyle(StudioPalette.violet)
          VStack(alignment: .leading, spacing: 2) {
            Text(studioText("데모 작업 공간", "Demo workspace", language: language))
              .font(.caption.weight(.semibold))
            if !compact {
              Text(
                studioText(
                  "편집과 저장만으로는 전송되지 않습니다. 지원되는 장치 작업은 해당 적용 버튼과 별도 확인을 거친 경우에만 한 번 실행됩니다.",
                  "Editing and saving never transmit data. A supported device operation runs once only after its apply button and separate confirmation.",
                  language: language
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
        }
        .padding(10)
        .background(
          StudioPalette.violet.opacity(0.09),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
      }
    }
  }
}
