import AK47InspectorCore
import SwiftUI

struct AK47PerKeyLightingDraft: Equatable {
  private static let supportedLightIndices = Set(AK47PhysicalLayout.keys.map(\.lightIndex))
  static let offColor = AK47InspectorCore.RGBColor(red: 0, green: 0, blue: 0)

  private(set) var entriesByLightIndex: [Int: PerKeyLighting]

  init(entries: [PerKeyLighting] = []) {
    var indexed: [Int: PerKeyLighting] = [:]
    for entry in entries {
      indexed[entry.position] = entry
    }
    entriesByLightIndex = indexed
  }

  var entries: [PerKeyLighting] {
    let physicalEntries = AK47PhysicalLayout.keys.map { key in
      entry(at: key.lightIndex)!
    }
    let unsupportedEntries = entriesByLightIndex.values.filter {
      !Self.supportedLightIndices.contains($0.position)
    }
    return (physicalEntries + unsupportedEntries).sorted { $0.position < $1.position }
  }

  var configuredKeyCount: Int {
    AK47PhysicalLayout.keys.count
  }

  var missingKeyCount: Int {
    0
  }

  var unsupportedEntryCount: Int {
    entriesByLightIndex.keys.count { !Self.supportedLightIndices.contains($0) }
  }

  var isApplyReady: Bool {
    true
  }

  var litKeyCount: Int {
    AK47PhysicalLayout.keys.count { key in
      color(at: key.lightIndex) != Self.offColor
    }
  }

  var offKeyCount: Int {
    AK47PhysicalLayout.keys.count - litKeyCount
  }

  var hasLitKeys: Bool {
    litKeyCount > 0
  }

  func entry(at lightIndex: Int) -> PerKeyLighting? {
    if let entry = entriesByLightIndex[lightIndex] {
      return entry
    }
    guard Self.supportedLightIndices.contains(lightIndex) else { return nil }
    return PerKeyLighting(position: lightIndex, color: Self.offColor, intensityPercent: 100)
  }

  func color(at lightIndex: Int) -> AK47InspectorCore.RGBColor? {
    entry(at: lightIndex)?.color
  }

  @discardableResult
  mutating func setColor(_ color: AK47InspectorCore.RGBColor, at lightIndex: Int) -> Bool {
    guard Self.supportedLightIndices.contains(lightIndex) else { return false }

    let previousColor = self.color(at: lightIndex)
    guard previousColor != color else { return false }
    if color == Self.offColor {
      entriesByLightIndex.removeValue(forKey: lightIndex)
    } else {
      entriesByLightIndex[lightIndex] = PerKeyLighting(
        position: lightIndex,
        color: color,
        intensityPercent: 100
      )
    }
    return previousColor != color
  }

  mutating func fill(_ color: AK47InspectorCore.RGBColor) {
    for key in AK47PhysicalLayout.keys {
      setColor(color, at: key.lightIndex)
    }
  }

  mutating func clear(lightIndex: Int) {
    setColor(Self.offColor, at: lightIndex)
  }

  /// Clears the 84 editable physical keys while round-tripping unknown entries loaded from a
  /// profile. Unknown positions are intentionally never changed by visible-key editing tools.
  mutating func clearAll() {
    for lightIndex in Self.supportedLightIndices {
      entriesByLightIndex.removeValue(forKey: lightIndex)
    }
  }

  func toggleTargetColor(
    brushColor: AK47InspectorCore.RGBColor,
    at lightIndex: Int
  ) -> AK47InspectorCore.RGBColor? {
    guard Self.supportedLightIndices.contains(lightIndex) else { return nil }
    return color(at: lightIndex) == brushColor ? Self.offColor : brushColor
  }

  @discardableResult
  mutating func toggle(
    brushColor: AK47InspectorCore.RGBColor,
    at lightIndex: Int
  ) -> Bool {
    guard let targetColor = toggleTargetColor(brushColor: brushColor, at: lightIndex) else {
      return false
    }
    return setColor(targetColor, at: lightIndex)
  }
}

struct AK47PerKeyLightingStroke: Equatable {
  private(set) var targetColor: AK47InspectorCore.RGBColor?
  private(set) var visitedLightIndices: Set<Int> = []

  mutating func nextTargetColor(
    at lightIndex: Int,
    draft: AK47PerKeyLightingDraft,
    brushColor: AK47InspectorCore.RGBColor
  ) -> AK47InspectorCore.RGBColor? {
    guard !visitedLightIndices.contains(lightIndex) else { return nil }
    guard
      let resolvedTarget = targetColor
        ?? draft.toggleTargetColor(brushColor: brushColor, at: lightIndex)
    else { return nil }

    targetColor = resolvedTarget
    visitedLightIndices.insert(lightIndex)
    return resolvedTarget
  }

  mutating func reset() {
    targetColor = nil
    visitedLightIndices = []
  }
}

enum AK47PerKeyLightingHitTesting {
  static func key(at point: CGPoint, in availableSize: CGSize) -> AK47PhysicalKey? {
    guard availableSize.width > 0, availableSize.height > 0 else { return nil }

    let scale = min(
      availableSize.width / AK47PhysicalLayout.canvasSize.width,
      availableSize.height / AK47PhysicalLayout.canvasSize.height
    )
    guard scale > 0 else { return nil }

    let renderedSize = CGSize(
      width: AK47PhysicalLayout.canvasSize.width * scale,
      height: AK47PhysicalLayout.canvasSize.height * scale
    )
    let renderedFrame = CGRect(
      x: (availableSize.width - renderedSize.width) / 2,
      y: (availableSize.height - renderedSize.height) / 2,
      width: renderedSize.width,
      height: renderedSize.height
    )
    guard renderedFrame.contains(point) else { return nil }

    let layoutPoint = CGPoint(
      x: (point.x - renderedFrame.minX) / scale,
      y: (point.y - renderedFrame.minY) / scale
    )
    return AK47PhysicalLayout.keys.first { key in
      CGRect(x: key.x, y: key.y, width: key.width, height: key.height)
        .contains(layoutPoint)
    }
  }
}

struct AK47PerKeyLightingEditor: View {
  let language: AppLanguage
  @Binding var draft: AK47PerKeyLightingDraft
  @Binding var selectedLightIndex: Int
  @Binding var paintColor: Color
  let onEdit: () -> Void

  @State private var isPickingColor = false
  @State private var bulkUndo: BulkUndo?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      heading
      toolControls

      AK47PerKeyLightingCanvas(
        language: language,
        draft: draft,
        selectedLightIndex: selectedLightIndex,
        brushColor: paintColor.profileRGBColor,
        isPickingColor: isPickingColor,
        onSetColor: setColor,
        onSampleColor: sampleColor
      )
      .padding(18)
      .background(StudioPalette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

      completionStatus
      bulkControls

      if draft.unsupportedEntryCount > 0 {
        Label(
          studioText(
            "이 레이아웃에서 알 수 없는 슬롯 \(draft.unsupportedEntryCount)개는 프로필에 그대로 보존됩니다.",
            "\(draft.unsupportedEntryCount) unknown layout slots are preserved unchanged in the profile.",
            language: language
          ),
          systemImage: "shippingbox"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .studioPanel()
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(studioText("키별 RGB 페인터", "Per-key RGB painter", language: language))
        .font(.headline)
      Text(
        studioText(
          "키를 누르면 선택한 색상과 꺼짐을 오갑니다. 드래그하면 첫 키에서 정해진 색상을 경로 전체에 적용합니다.",
          "Press a key to toggle between the selected color and off. Dragging applies the first key's target across the stroke.",
          language: language
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var selectedKey: AK47PhysicalKey? {
    AK47PhysicalLayout.keys.first { $0.lightIndex == selectedLightIndex }
  }

  private var toolControls: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .bottom, spacing: 16) {
        paintColorPicker
        colorSamplerButton
        Spacer(minLength: 8)
        selectionSummary
      }

      VStack(alignment: .leading, spacing: 12) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 16) {
            paintColorPicker
            colorSamplerButton
            Spacer(minLength: 8)
            selectionSummary
          }
          VStack(alignment: .leading, spacing: 10) {
            paintColorPicker
            colorSamplerButton
            selectionSummary
          }
        }
      }
    }
  }

  private var colorSamplerButton: some View {
    Button {
      isPickingColor.toggle()
    } label: {
      Label(
        isPickingColor
          ? studioText("가져오기 취소", "Cancel picking", language: language)
          : studioText("키에서 색상 가져오기", "Pick color from key", language: language),
        systemImage: isPickingColor ? "xmark" : "eyedropper"
      )
    }
    .buttonStyle(.bordered)
    .tint(isPickingColor ? StudioPalette.blue : nil)
    .accessibilityHint(
      isPickingColor
        ? studioText(
          "다시 누르면 색상 가져오기를 취소합니다.", "Press again to cancel color picking.", language: language)
        : studioText(
          "다음에 누른 키의 색상을 선택 색상으로 가져옵니다.", "Uses the next key's color as the selected color.",
          language: language)
    )
  }

  private var selectionSummary: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(studioText("선택한 키", "Selected key", language: language))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(selectedKey?.label ?? "—")
        .font(.callout.weight(.semibold))
    }
    .frame(minWidth: 100, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var paintColorPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      ColorPicker(
        studioText("브러시 색상", "Brush color", language: language),
        selection: $paintColor,
        supportsOpacity: false
      )
      HStack(spacing: 7) {
        brushPreset(.white, name: studioText("흰색", "White", language: language))
        brushPreset(StudioPalette.mint, name: studioText("민트", "Mint", language: language))
        brushPreset(StudioPalette.blue, name: studioText("파랑", "Blue", language: language))
        brushPreset(StudioPalette.violet, name: studioText("보라", "Violet", language: language))
        brushPreset(StudioPalette.coral, name: studioText("코랄", "Coral", language: language))
      }
    }
    .frame(minWidth: 145, maxWidth: 210)
    .accessibilityHint(
      studioText(
        "키를 켤 때 사용할 색상입니다. 검정 RGB(0, 0, 0)은 꺼짐으로 취급합니다.",
        "The color used when turning a key on. Black RGB(0, 0, 0) is treated as off.",
        language: language
      )
    )
  }

  private func brushPreset(_ color: Color, name: String) -> some View {
    Button {
      paintColor = color
    } label: {
      Circle()
        .fill(color)
        .frame(width: 22, height: 22)
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.2)) }
    }
    .buttonStyle(.plain)
    .help(name)
    .accessibilityLabel(name)
  }

  private var completionStatus: some View {
    Label(
      studioText(
        "켜짐 \(draft.litKeyCount)키 · 꺼짐 \(draft.offKeyCount)키 · 검정 RGB는 꺼짐",
        "\(draft.litKeyCount) lit · \(draft.offKeyCount) off · Black RGB means off",
        language: language
      ),
      systemImage: "checkmark.circle.fill"
    )
    .font(.caption.weight(.semibold))
    .foregroundStyle(StudioPalette.mint)
  }

  private var bulkControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(studioText("빠른 작업", "Quick actions", language: language))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          fillAllButton
          clearAllButton
          Spacer(minLength: 8)
          undoControl
        }

        VStack(alignment: .leading, spacing: 10) {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
              fillAllButton
              clearAllButton
            }
            VStack(alignment: .leading, spacing: 8) {
              fillAllButton
              clearAllButton
            }
          }
          undoControl
        }
      }
    }
  }

  private var fillAllButton: some View {
    Button(action: fillAll) {
      Label(
        studioText("전체를 선택 색상으로", "Set all to selected color", language: language),
        systemImage: "paintbrush.fill"
      )
    }
    .buttonStyle(.bordered)
    .accessibilityHint(
      studioText(
        "기존 색상을 덮어쓰며 직후 실행 취소할 수 있습니다.",
        "Overwrites existing colors and can be undone immediately.",
        language: language
      )
    )
  }

  private var clearAllButton: some View {
    Button(role: .destructive, action: clearAll) {
      Label(
        studioText("전체 조명 끄기", "Turn all off", language: language),
        systemImage: "lightbulb.slash"
      )
    }
    .buttonStyle(.bordered)
    .disabled(!draft.hasLitKeys)
    .accessibilityHint(
      studioText(
        "84키를 모두 검정 RGB로 바꾸며 직후 실행 취소할 수 있습니다.",
        "Sets all 84 keys to black RGB and can be undone immediately.",
        language: language
      )
    )
  }

  @ViewBuilder
  private var undoControl: some View {
    if let bulkUndo {
      HStack(spacing: 8) {
        Text(bulkUndo.message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Button(studioText("실행 취소", "Undo", language: language), action: undoBulkEdit)
          .buttonStyle(.borderless)
          .accessibilityHint(
            studioText(
              "바로 전 빠른 작업 이전 상태로 돌아갑니다.",
              "Restores the state before the last quick action.",
              language: language
            )
          )
      }
    }
  }

  private func setColor(_ color: AK47InspectorCore.RGBColor, at lightIndex: Int) {
    selectedLightIndex = lightIndex
    if draft.setColor(color, at: lightIndex) {
      bulkUndo = nil
      onEdit()
    }
  }

  private func sampleColor(at lightIndex: Int) {
    selectedLightIndex = lightIndex
    guard let sampledColor = draft.color(at: lightIndex) else { return }
    paintColor = sampledColor.swiftUIColor
    isPickingColor = false
  }

  private func fillAll() {
    performBulkEdit(
      message: studioText("전체 채우기를 적용했습니다.", "Filled all keys.", language: language)
    ) { draft in
      draft.fill(paintColor.profileRGBColor)
    }
  }

  private func clearAll() {
    performBulkEdit(
      message: studioText("84키 조명을 모두 껐습니다.", "Turned all 84 keys off.", language: language)
    ) { draft in
      draft.clearAll()
    }
  }

  private func performBulkEdit(
    message: String,
    mutation: (inout AK47PerKeyLightingDraft) -> Void
  ) {
    let before = draft
    mutation(&draft)
    guard draft != before else { return }
    bulkUndo = BulkUndo(draft: before, message: message)
    onEdit()
  }

  private func undoBulkEdit() {
    guard let bulkUndo else { return }
    draft = bulkUndo.draft
    self.bulkUndo = nil
    onEdit()
  }

  private struct BulkUndo {
    let draft: AK47PerKeyLightingDraft
    let message: String
  }
}

private struct AK47PerKeyLightingCanvas: View {
  let language: AppLanguage
  let draft: AK47PerKeyLightingDraft
  let selectedLightIndex: Int
  let brushColor: AK47InspectorCore.RGBColor
  let isPickingColor: Bool
  let onSetColor: (AK47InspectorCore.RGBColor, Int) -> Void
  let onSampleColor: (Int) -> Void

  @State private var visitedLightIndices: Set<Int> = []
  @State private var stroke = AK47PerKeyLightingStroke()

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
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      .contentShape(Rectangle())
      .simultaneousGesture(canvasDragGesture(in: proxy.size))
    }
    .aspectRatio(
      AK47PhysicalLayout.canvasSize.width / AK47PhysicalLayout.canvasSize.height,
      contentMode: .fit
    )
  }

  private func canvasDragGesture(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        guard let hit = AK47PerKeyLightingHitTesting.key(at: value.location, in: size) else {
          return
        }
        if isPickingColor {
          guard !visitedLightIndices.contains(hit.lightIndex) else { return }
          visitedLightIndices.insert(hit.lightIndex)
          if visitedLightIndices.count == 1 {
            onSampleColor(hit.lightIndex)
          }
          return
        }

        guard
          let targetColor = stroke.nextTargetColor(
            at: hit.lightIndex,
            draft: draft,
            brushColor: brushColor
          )
        else { return }
        onSetColor(targetColor, hit.lightIndex)
      }
      .onEnded { _ in
        visitedLightIndices = []
        stroke.reset()
      }
  }

  private func keyButton(_ key: AK47PhysicalKey, scale: CGFloat) -> some View {
    let entry = draft.entry(at: key.lightIndex)
    let storedColor = entry?.color ?? AK47PerKeyLightingDraft.offColor
    let color = storedColor.swiftUIColor
    let isOff = storedColor == AK47PerKeyLightingDraft.offColor
    let selected = selectedLightIndex == key.lightIndex

    return RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
      .fill(Color.white.opacity(0.055))
      .overlay {
        RoundedRectangle(cornerRadius: max(3, 6 * scale), style: .continuous)
          .fill(isOff ? Color.black.opacity(0.72) : color.opacity(0.88))
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
        color: isOff ? .clear : color.opacity(0.55),
        radius: max(1, 6 * scale)
      )
      .frame(width: key.width * scale, height: key.height * scale)
      .contentShape(Rectangle())
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(
        studioText("\(key.label) 키", "\(key.label) key", language: language)
      )
      .accessibilityValue(accessibilityValue(for: entry, selected: selected))
      .accessibilityHint(keyAccessibilityHint)
      .accessibilityAction {
        if isPickingColor {
          onSampleColor(key.lightIndex)
        } else if let targetColor = draft.toggleTargetColor(
          brushColor: brushColor,
          at: key.lightIndex
        ) {
          onSetColor(targetColor, key.lightIndex)
        }
      }
  }

  private var keyAccessibilityHint: String {
    if isPickingColor {
      studioText("이 키의 색상을 브러시로 가져옵니다.", "Copies this key color to the brush.", language: language)
    } else {
      studioText(
        "선택 색상과 조명 꺼짐을 전환합니다.",
        "Toggles between the selected color and off.",
        language: language
      )
    }
  }

  private func accessibilityValue(for entry: PerKeyLighting?, selected: Bool) -> String {
    let selection =
      selected
      ? studioText("선택됨, ", "Selected, ", language: language)
      : ""
    guard let entry, entry.color != AK47PerKeyLightingDraft.offColor else {
      return selection + studioText("조명 꺼짐", "Lighting off", language: language)
    }
    return selection + "RGB \(entry.color.red), \(entry.color.green), \(entry.color.blue)"
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
