import AK47InspectorCore
import SwiftUI

struct AK47PerKeyLightingDraft: Equatable {
  private(set) var entriesByLightIndex: [Int: PerKeyLighting]

  init(entries: [PerKeyLighting] = []) {
    var indexed: [Int: PerKeyLighting] = [:]
    for entry in entries {
      indexed[entry.position] = entry
    }
    entriesByLightIndex = indexed
  }

  var entries: [PerKeyLighting] {
    entriesByLightIndex.values.sorted { $0.position < $1.position }
  }

  var configuredKeyCount: Int {
    let supported = Set(AK47PhysicalLayout.keys.map(\.lightIndex))
    return entriesByLightIndex.keys.count { supported.contains($0) }
  }

  func entry(at lightIndex: Int) -> PerKeyLighting? {
    entriesByLightIndex[lightIndex]
  }

  mutating func setColor(_ color: AK47InspectorCore.RGBColor, at lightIndex: Int) {
    guard AK47PhysicalLayout.keys.contains(where: { $0.lightIndex == lightIndex }) else { return }
    entriesByLightIndex[lightIndex] = PerKeyLighting(
      position: lightIndex,
      color: color,
      intensityPercent: 100
    )
  }

  mutating func fill(_ color: AK47InspectorCore.RGBColor) {
    for key in AK47PhysicalLayout.keys {
      setColor(color, at: key.lightIndex)
    }
  }

  mutating func clear(lightIndex: Int) {
    entriesByLightIndex.removeValue(forKey: lightIndex)
  }

  mutating func clearAll() {
    entriesByLightIndex.removeAll()
  }
}

struct AK47PerKeyLightingEditor: View {
  let language: AppLanguage
  @Binding var draft: AK47PerKeyLightingDraft
  @Binding var selectedLightIndex: Int
  @Binding var paintColor: Color
  let onEdit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(studioText("키별 RGB 페인터", "Per-key RGB painter", language: language))
            .font(.headline)
          Text(
            studioText(
              "실제 84키와 펌웨어 RGB 슬롯을 그대로 사용해 로컬 프로필을 편집합니다.",
              "Edit the local profile using the actual 84 keys and firmware RGB slots.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Text(
          studioText(
            "\(draft.configuredKeyCount) / 84키",
            "\(draft.configuredKeyCount) / 84 keys",
            language: language
          )
        )
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
      }

      AK47PerKeyLightingCanvas(
        language: language,
        draft: draft,
        selectedLightIndex: selectedLightIndex,
        onSelect: select
      )
      .padding(18)
      .background(StudioPalette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          selectionSummary
          paintColorPicker
          Spacer(minLength: 4)
          paintButton
          fillClearMenu
        }

        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            selectionSummary
            paintColorPicker
          }
          HStack(spacing: 12) {
            paintButton
            fillClearMenu
          }
        }
      }
    }
    .studioPanel()
  }

  private var selectedKey: AK47PhysicalKey? {
    AK47PhysicalLayout.keys.first { $0.lightIndex == selectedLightIndex }
  }

  private var selectionSummary: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(selectedKey?.label ?? "—")
        .font(.callout.weight(.semibold))
      Text("RGB slot \(selectedLightIndex)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .frame(minWidth: 90, alignment: .leading)
  }

  private var paintColorPicker: some View {
    ColorPicker(
      studioText("칠할 색", "Paint color", language: language),
      selection: $paintColor,
      supportsOpacity: false
    )
    .frame(maxWidth: 190)
  }

  private var paintButton: some View {
    Button(action: paintSelected) {
      Label(
        studioText("선택 키 칠하기", "Paint selected", language: language),
        systemImage: "paintbrush"
      )
    }
    .buttonStyle(.borderedProminent)
    .tint(StudioPalette.blue)
  }

  private var fillClearMenu: some View {
    Menu {
      Button(action: fillAll) {
        Label(
          studioText("전체 채우기", "Fill all", language: language),
          systemImage: "paintbrush.fill"
        )
      }
      Button(action: clearSelected) {
        Label(
          studioText("선택 키 지우기", "Clear selected", language: language),
          systemImage: "eraser"
        )
      }
      .disabled(draft.entry(at: selectedLightIndex) == nil)
      Divider()
      Button(role: .destructive, action: clearAll) {
        Label(
          studioText("전체 지우기", "Clear all", language: language),
          systemImage: "trash"
        )
      }
      .disabled(draft.entries.isEmpty)
    } label: {
      Label(
        studioText("채우기·지우기", "Fill & clear", language: language),
        systemImage: "ellipsis.circle"
      )
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  private func select(_ lightIndex: Int) {
    selectedLightIndex = lightIndex
    if let color = draft.entry(at: lightIndex)?.color {
      paintColor = color.swiftUIColor
    }
  }

  private func paintSelected() {
    draft.setColor(paintColor.profileRGBColor, at: selectedLightIndex)
    onEdit()
  }

  private func fillAll() {
    draft.fill(paintColor.profileRGBColor)
    onEdit()
  }

  private func clearSelected() {
    draft.clear(lightIndex: selectedLightIndex)
    onEdit()
  }

  private func clearAll() {
    draft.clearAll()
    onEdit()
  }
}

private struct AK47PerKeyLightingCanvas: View {
  let language: AppLanguage
  let draft: AK47PerKeyLightingDraft
  let selectedLightIndex: Int
  let onSelect: (Int) -> Void

  var body: some View {
    GeometryReader { proxy in
      let scale = min(
        proxy.size.width / AK47PhysicalLayout.canvasSize.width,
        proxy.size.height / AK47PhysicalLayout.canvasSize.height
      )
      let xOffset = (proxy.size.width - AK47PhysicalLayout.canvasSize.width * scale) / 2
      let yOffset = (proxy.size.height - AK47PhysicalLayout.canvasSize.height * scale) / 2

      ZStack(alignment: .topLeading) {
        ForEach(AK47PhysicalLayout.keys) { key in
          keyButton(key, scale: scale)
            .position(
              x: xOffset + key.center.x * scale,
              y: yOffset + key.center.y * scale
            )
        }

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
    .aspectRatio(
      AK47PhysicalLayout.canvasSize.width / AK47PhysicalLayout.canvasSize.height,
      contentMode: .fit
    )
  }

  private func keyButton(_ key: AK47PhysicalKey, scale: CGFloat) -> some View {
    let entry = draft.entry(at: key.lightIndex)
    let color = entry?.color.swiftUIColor ?? Color.white.opacity(0.035)
    let selected = selectedLightIndex == key.lightIndex

    return Button {
      onSelect(key.lightIndex)
    } label: {
      RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
        .fill(Color.white.opacity(0.055))
        .overlay {
          RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
            .fill(color.opacity(entry == nil ? 0.35 : 0.88))
        }
        .overlay {
          RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
            .strokeBorder(
              selected ? StudioPalette.blue : Color.white.opacity(0.12),
              lineWidth: selected ? max(1.5, scale * 2) : max(0.5, scale * 0.7)
            )
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
            .foregroundStyle(Color.white.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, max(1, 3 * scale))
        }
        .shadow(
          color: entry == nil ? .clear : color.opacity(0.55),
          radius: max(1, 6 * scale)
        )
    }
    .buttonStyle(.plain)
    .frame(width: key.width * scale, height: key.height * scale)
    .accessibilityLabel(key.id)
    .accessibilityValue(accessibilityValue(for: entry))
  }

  private func accessibilityValue(for entry: PerKeyLighting?) -> String {
    guard let entry else {
      return studioText("색상 없음", "No color", language: language)
    }
    return "RGB \(entry.color.red), \(entry.color.green), \(entry.color.blue)"
  }

  private func displayPlaceholder(scale: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: max(3, 7 * scale), style: .continuous)
      .fill(Color.white.opacity(0.08))
      .frame(
        width: AK47PhysicalLayout.lcdFrame.width * scale,
        height: AK47PhysicalLayout.lcdFrame.height * scale
      )
      .overlay {
        Text("LCD")
          .font(.system(size: max(6, 8 * scale), weight: .bold, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.58))
      }
      .accessibilityHidden(true)
  }

  private func knobPlaceholder(scale: CGFloat) -> some View {
    Circle()
      .fill(Color.white.opacity(0.1))
      .overlay { Circle().strokeBorder(Color.white.opacity(0.18)) }
      .frame(
        width: AK47PhysicalLayout.knobFrame.width * scale,
        height: AK47PhysicalLayout.knobFrame.height * scale
      )
      .accessibilityHidden(true)
  }
}
