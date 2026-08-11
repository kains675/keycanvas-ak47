import AK47InspectorCore
import Foundation
import SwiftUI

struct KeymapView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var profileStore: LocalProfileStore
  @State private var selectedKey = "Space"
  @State private var assignment = KeymapAssignmentChoice.keyCode(0x2C)
  @State private var activeLayer = "Base"
  @State private var savedLocally = false

  private let layers = ["Base", "Fn"]

  private var assignmentOptions: [KeymapAssignmentChoice] {
    var options: [KeymapAssignmentChoice] = [.disabled]
    options.append(contentsOf: Self.consumerActionOrder.map { .consumerControl($0.usage) })
    options.append(
      contentsOf: AK47PhysicalLayout.keyIDs.compactMap { key in
        Self.hidKeyCodes[key].map(KeymapAssignmentChoice.keyCode)
      }
    )
    options.append(
      contentsOf: profileStore.selectedProfile.macros.map {
        .macro(identifier: $0.identifier)
      }
    )
    if !options.contains(assignment) {
      options.append(assignment)
    }

    var seen: Set<KeymapAssignmentChoice> = []
    return options.filter { seen.insert($0).inserted }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 20) {
        StudioSectionHeader(
          eyebrow: studioText("초안 편집기", "Draft editor", language: language),
          title: studioText("키맵", "Keymap", language: language),
          detail: studioText(
            "키를 선택해 로컬 할당을 살펴보세요. 어떤 내용도 장치로 전송되지 않습니다.",
            "Select a key and explore a local assignment. Nothing is sent to the device.",
            language: language
          )
        )

        Picker(studioText("레이어", "Layer", language: language), selection: $activeLayer) {
          ForEach(layers, id: \.self) { layer in
            Text(layer == "Base" ? studioText("기본", "Base", language: language) : "Fn")
              .tag(layer)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
      }
      .padding(28)

      Divider()

      HSplitView {
        ScrollView([.horizontal, .vertical]) {
          KeyboardDraft(selectedKey: $selectedKey)
            .padding(30)
        }
        .frame(minWidth: 620)

        keyInspector
          .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)
      }
    }
  }

  private var keyInspector: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(studioText("선택한 키", "SELECTED KEY", language: language))
          .font(.caption2.weight(.semibold))
          .tracking(1.1)
          .foregroundStyle(.secondary)
        Text(selectedKey)
          .font(.title2.weight(.bold))
      }

      Divider()

      Picker(studioText("할당", "Assignment", language: language), selection: $assignment) {
        ForEach(assignmentOptions, id: \.self) { option in
          Text(assignmentLabel(for: option)).tag(option)
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text(studioText("미리보기", "Preview", language: language))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        HStack {
          Image(systemName: assignmentSymbol)
            .foregroundStyle(StudioPalette.blue)
          Text("\(selectedKey) → \(assignmentLabel(for: assignment))")
            .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioPalette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      }

      Spacer()
      DemoNotice()

      Button {
        profileStore.setKeyAssignment(
          assignment.action,
          position: position(for: selectedKey),
          layer: activeLayer == "Fn" ? 1 : 0
        )
        profileStore.saveSelected()
        if case .saved = profileStore.status {
          savedLocally = true
        } else {
          savedLocally = false
        }
      } label: {
        Label(
          savedLocally
            ? studioText("로컬 초안 저장됨", "Draft saved locally", language: language)
            : studioText("로컬 초안 저장", "Save local draft", language: language),
          systemImage: savedLocally ? "checkmark" : "square.and.arrow.down"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.blue)
    }
    .padding(22)
    .background(.regularMaterial)
    .onAppear(perform: loadStoredAssignment)
    .onChange(of: selectedKey) { newKey in
      assignment = storedAssignment(for: newKey) ?? defaultAssignment(for: newKey)
      savedLocally = false
    }
    .onChange(of: assignment) { _ in
      savedLocally = false
    }
    .onChange(of: activeLayer) { _ in
      loadStoredAssignment()
    }
    .onChange(of: profileStore.selectedID) { _ in
      loadStoredAssignment()
    }
    .onChange(of: profileStore.selectedProfile.macros) { _ in
      if case .macro(let identifier) = assignment,
        !profileStore.selectedProfile.macros.contains(where: { $0.identifier == identifier })
      {
        loadStoredAssignment()
      }
    }
  }

  private var assignmentSymbol: String {
    switch assignment {
    case .macro:
      return "waveform"
    case .consumerControl:
      return "speaker.wave.2"
    case .disabled:
      return "nosign"
    case .keyCode:
      return "arrow.turn.down.left"
    }
  }

  private func loadStoredAssignment() {
    assignment = storedAssignment(for: selectedKey) ?? defaultAssignment(for: selectedKey)
    savedLocally = false
  }

  private func defaultAssignment(for key: String) -> KeymapAssignmentChoice {
    Self.hidKeyCodes[key].map(KeymapAssignmentChoice.keyCode) ?? .disabled
  }

  private func assignmentLabel(for choice: KeymapAssignmentChoice) -> String {
    switch choice {
    case .disabled:
      return studioText("동작 없음", "No action", language: language)
    case .keyCode(let code):
      return Self.hidKeyCodes.first(where: { $0.value == code })?.key
        ?? String(format: "HID 0x%04X", code)
    case .consumerControl(let usage):
      return Self.consumerActions.first(where: { $0.value == usage })?.key
        ?? String(format: "Consumer 0x%04X", usage)
    case .macro(let identifier):
      let name = profileStore.selectedProfile.macros.first(where: {
        $0.identifier == identifier
      })?.name
      return name.map {
        studioText("매크로 · \($0)", "Macro · \($0)", language: language)
      }
        ?? studioText(
          "누락된 매크로 · \(identifier)",
          "Missing macro · \(identifier)",
          language: language
        )
    }
  }

  private func position(for key: String) -> Int {
    AK47PhysicalLayout.profilePosition(for: key) ?? 0
  }

  private func storedAssignment(for key: String) -> KeymapAssignmentChoice? {
    guard
      let assignment = profileStore.selectedProfile.keymap.assignments.first(where: {
        $0.layer == (activeLayer == "Fn" ? 1 : 0) && $0.position == position(for: key)
      })
    else {
      return nil
    }

    return KeymapAssignmentChoice(action: assignment.action)
  }

  private static let hidKeyCodes: [String: UInt16] = [
    "A": 0x04, "B": 0x05, "C": 0x06, "D": 0x07, "E": 0x08, "F": 0x09,
    "G": 0x0A, "H": 0x0B, "I": 0x0C, "J": 0x0D, "K": 0x0E, "L": 0x0F,
    "M": 0x10, "N": 0x11, "O": 0x12, "P": 0x13, "Q": 0x14, "R": 0x15,
    "S": 0x16, "T": 0x17, "U": 0x18, "V": 0x19, "W": 0x1A, "X": 0x1B,
    "Y": 0x1C, "Z": 0x1D, "1": 0x1E, "2": 0x1F, "3": 0x20, "4": 0x21,
    "5": 0x22, "6": 0x23, "7": 0x24, "8": 0x25, "9": 0x26, "0": 0x27,
    "Return": 0x28, "Esc": 0x29, "Backspace": 0x2A, "Tab": 0x2B, "Space": 0x2C,
    "Minus": 0x2D, "Equal": 0x2E, "Left Bracket": 0x2F, "Right Bracket": 0x30,
    "Backslash": 0x31, "Semicolon": 0x33, "Quote": 0x34, "Grave": 0x35,
    "Comma": 0x36, "Period": 0x37, "Slash": 0x38, "Caps Lock": 0x39,
    "F1": 0x3A, "F2": 0x3B, "F3": 0x3C, "F4": 0x3D, "F5": 0x3E,
    "F6": 0x3F, "F7": 0x40, "F8": 0x41, "F9": 0x42, "F10": 0x43,
    "F11": 0x44, "F12": 0x45, "Insert": 0x49,
    "Home": 0x4A, "Page Up": 0x4B, "Delete": 0x4C, "End": 0x4D,
    "Page Down": 0x4E, "Right": 0x4F, "Left": 0x50, "Down": 0x51, "Up": 0x52,
    "Left Control": 0xE0, "Left Shift": 0xE1, "Left Option": 0xE2,
    "Left Command": 0xE3, "Right Control": 0xE4, "Right Shift": 0xE5,
    "Right Option": 0xE6, "Menu": 0x65,
  ]

  private static let consumerActions: [String: UInt16] = [
    "Play / Pause": 0x00CD,
    "Next Track": 0x00B5,
    "Previous Track": 0x00B6,
    "Mute": 0x00E2,
    "Volume Up": 0x00E9,
    "Volume Down": 0x00EA,
  ]

  private static let consumerActionOrder: [(name: String, usage: UInt16)] = [
    ("Play / Pause", 0x00CD),
    ("Previous Track", 0x00B6),
    ("Next Track", 0x00B5),
    ("Mute", 0x00E2),
    ("Volume Down", 0x00EA),
    ("Volume Up", 0x00E9),
  ]
}

private struct KeyboardDraft: View {
  @Binding var selectedKey: String

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        KeyCanvasMark(size: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text("AK47 · 84 KEY")
            .font(.caption.weight(.bold))
            .tracking(1.2)
          Text("PHYSICAL LAYOUT")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        StatusPill(label: "240×135 LCD · KNOB", symbol: "dial.medium", tint: StudioPalette.violet)
      }

      ZStack(alignment: .topLeading) {
        indicatorDots
          .offset(x: 50, y: 5)

        displayPlaceholder
          .offset(x: AK47PhysicalLayout.lcdFrame.minX, y: AK47PhysicalLayout.lcdFrame.minY)

        knobPlaceholder
          .offset(x: AK47PhysicalLayout.knobFrame.minX, y: AK47PhysicalLayout.knobFrame.minY)

        ForEach(AK47PhysicalLayout.keys) { key in
          KeycapButton(key: key, isSelected: selectedKey == key.id) {
            selectedKey = key.id
          }
          .offset(x: key.x, y: key.y)
        }
      }
      .frame(
        width: AK47PhysicalLayout.canvasSize.width,
        height: AK47PhysicalLayout.canvasSize.height,
        alignment: .topLeading
      )
    }
    .padding(20)
    .background(
      StudioPalette.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(Color.white.opacity(0.08))
    }
  }

  private var indicatorDots: some View {
    VStack(spacing: 4) {
      ForEach(0..<3, id: \.self) { _ in
        Circle()
          .fill(Color.white.opacity(0.34))
          .frame(width: 5, height: 5)
      }
    }
  }

  private var displayPlaceholder: some View {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
      .fill(
        LinearGradient(
          colors: [StudioPalette.blue.opacity(0.38), StudioPalette.violet.opacity(0.24)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: 70, height: 32)
      .overlay {
        Text("LCD")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .tracking(1)
          .foregroundStyle(Color.white.opacity(0.72))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12))
      }
      .accessibilityLabel("240 by 135 LCD")
  }

  private var knobPlaceholder: some View {
    Circle()
      .fill(Color.white.opacity(0.11))
      .frame(width: 32, height: 32)
      .overlay {
        Circle()
          .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
          .padding(2)
      }
      .overlay(alignment: .top) {
        Capsule()
          .fill(Color.white.opacity(0.42))
          .frame(width: 2, height: 7)
          .padding(.top, 5)
      }
      .accessibilityLabel("Rotary knob")
  }
}

private struct KeycapButton: View {
  let key: AK47PhysicalKey
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(key.label)
        .font(.system(size: key.width <= 32 ? 8.5 : 9, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
        .frame(width: key.width, height: key.height)
        .background(
          isSelected ? StudioPalette.blue : Color.white.opacity(0.08),
          in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Color.white.opacity(isSelected ? 0.28 : 0.10))
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(key.id)
  }
}
