import AK47InspectorCore
import SwiftUI

struct KeymapView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var profileStore: LocalProfileStore
  @State private var selectedKey = "Space"
  @State private var assignment = "Space"
  @State private var activeLayer = "Base"
  @State private var savedLocally = false

  private let layers = ["Base", "Fn"]

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
        ForEach(Self.assignmentOptions, id: \.self) { option in
          Text(option).tag(option)
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text(studioText("미리보기", "Preview", language: language))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        HStack {
          Image(systemName: "arrow.turn.down.left")
            .foregroundStyle(StudioPalette.blue)
          Text("\(selectedKey) → \(assignment)")
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
          action(for: assignment, selectedKey: selectedKey),
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
    .onChange(of: selectedKey) { newKey in
      assignment = storedAssignment(for: newKey) ?? newKey
      savedLocally = false
    }
    .onChange(of: assignment) { _ in
      savedLocally = false
    }
    .onChange(of: activeLayer) { _ in
      assignment = storedAssignment(for: selectedKey) ?? selectedKey
      savedLocally = false
    }
  }

  private func position(for key: String) -> Int {
    Self.keyPositions.firstIndex(of: key) ?? 0
  }

  private func action(for assignment: String, selectedKey: String) -> KeyAction {
    if assignment == "No action" {
      return .disabled
    }
    if let usage = Self.consumerActions[assignment] {
      return .consumerControl(usage)
    }
    return Self.hidKeyCodes[assignment]
      .map(KeyAction.keyCode)
      ?? Self.hidKeyCodes[selectedKey].map(KeyAction.keyCode)
      ?? .disabled
  }

  private func storedAssignment(for key: String) -> String? {
    guard
      let assignment = profileStore.selectedProfile.keymap.assignments.first(where: {
        $0.layer == (activeLayer == "Fn" ? 1 : 0) && $0.position == position(for: key)
      })
    else {
      return nil
    }

    switch assignment.action {
    case .consumerControl(let usage):
      return Self.consumerActions.first(where: { $0.value == usage })?.key
    case .disabled:
      return "No action"
    case .macro:
      return nil
    case .keyCode(let code):
      return Self.hidKeyCodes.first(where: { $0.value == code })?.key
    }
  }

  private static let keyPositions = [
    "Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "Print Screen", "Delete", "Home",
    "Grave", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Minus", "Equal", "Backspace",
    "Page Up",
    "Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Left Bracket", "Right Bracket",
    "Backslash", "Page Down",
    "Caps Lock", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Semicolon", "Quote", "Return",
    "Insert",
    "Left Shift", "Z", "X", "C", "V", "B", "N", "M", "Comma", "Period", "Slash", "Right Shift",
    "Up", "End",
    "Left Control", "Left Option", "Left Command", "Space", "Right Option", "Fn", "Right Control",
    "Left", "Down", "Right",
  ]

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
    "F11": 0x44, "F12": 0x45, "Print Screen": 0x46, "Insert": 0x49,
    "Home": 0x4A, "Page Up": 0x4B, "Delete": 0x4C, "End": 0x4D,
    "Page Down": 0x4E, "Right": 0x4F, "Left": 0x50, "Down": 0x51, "Up": 0x52,
    "Left Control": 0xE0, "Left Shift": 0xE1, "Left Option": 0xE2,
    "Left Command": 0xE3, "Right Control": 0xE4, "Right Shift": 0xE5,
    "Right Option": 0xE6,
  ]

  private static let consumerActions: [String: UInt16] = [
    "Play / Pause": 0x00CD,
    "Next Track": 0x00B5,
    "Previous Track": 0x00B6,
    "Mute": 0x00E2,
    "Volume Up": 0x00E9,
    "Volume Down": 0x00EA,
  ]

  private static let assignmentOptions =
    ["No action"]
    + ["Play / Pause", "Previous Track", "Next Track", "Mute", "Volume Down", "Volume Up"]
    + keyPositions.filter { hidKeyCodes[$0] != nil }
}

private struct KeyDraft: Identifiable {
  let id: String
  let label: String
  var units: CGFloat = 1
}

private struct KeyboardDraft: View {
  @Binding var selectedKey: String

  private let rows: [[KeyDraft]] = [
    [
      KeyDraft(id: "Esc", label: "esc"), KeyDraft(id: "F1", label: "F1"),
      KeyDraft(id: "F2", label: "F2"),
      KeyDraft(id: "F3", label: "F3"), KeyDraft(id: "F4", label: "F4"),
      KeyDraft(id: "F5", label: "F5"),
      KeyDraft(id: "F6", label: "F6"), KeyDraft(id: "F7", label: "F7"),
      KeyDraft(id: "F8", label: "F8"),
      KeyDraft(id: "F9", label: "F9"), KeyDraft(id: "F10", label: "F10"),
      KeyDraft(id: "F11", label: "F11"),
      KeyDraft(id: "F12", label: "F12"), KeyDraft(id: "Print Screen", label: "print"),
      KeyDraft(id: "Delete", label: "del"), KeyDraft(id: "Home", label: "home"),
    ],
    [
      KeyDraft(id: "Grave", label: "`"), KeyDraft(id: "1", label: "1"),
      KeyDraft(id: "2", label: "2"),
      KeyDraft(id: "3", label: "3"), KeyDraft(id: "4", label: "4"), KeyDraft(id: "5", label: "5"),
      KeyDraft(id: "6", label: "6"), KeyDraft(id: "7", label: "7"), KeyDraft(id: "8", label: "8"),
      KeyDraft(id: "9", label: "9"), KeyDraft(id: "0", label: "0"),
      KeyDraft(id: "Minus", label: "−"),
      KeyDraft(id: "Equal", label: "="), KeyDraft(id: "Backspace", label: "delete", units: 2),
      KeyDraft(id: "Page Up", label: "pg up"),
    ],
    [
      KeyDraft(id: "Tab", label: "tab", units: 1.5), KeyDraft(id: "Q", label: "Q"),
      KeyDraft(id: "W", label: "W"),
      KeyDraft(id: "E", label: "E"), KeyDraft(id: "R", label: "R"), KeyDraft(id: "T", label: "T"),
      KeyDraft(id: "Y", label: "Y"), KeyDraft(id: "U", label: "U"), KeyDraft(id: "I", label: "I"),
      KeyDraft(id: "O", label: "O"), KeyDraft(id: "P", label: "P"),
      KeyDraft(id: "Left Bracket", label: "["),
      KeyDraft(id: "Right Bracket", label: "]"), KeyDraft(id: "Backslash", label: "\\", units: 1.5),
      KeyDraft(id: "Page Down", label: "pg dn"),
    ],
    [
      KeyDraft(id: "Caps Lock", label: "caps", units: 1.75), KeyDraft(id: "A", label: "A"),
      KeyDraft(id: "S", label: "S"),
      KeyDraft(id: "D", label: "D"), KeyDraft(id: "F", label: "F"), KeyDraft(id: "G", label: "G"),
      KeyDraft(id: "H", label: "H"), KeyDraft(id: "J", label: "J"), KeyDraft(id: "K", label: "K"),
      KeyDraft(id: "L", label: "L"), KeyDraft(id: "Semicolon", label: ";"),
      KeyDraft(id: "Quote", label: "'"),
      KeyDraft(id: "Return", label: "return", units: 2.25), KeyDraft(id: "Insert", label: "ins"),
    ],
    [
      KeyDraft(id: "Left Shift", label: "shift", units: 2.25), KeyDraft(id: "Z", label: "Z"),
      KeyDraft(id: "X", label: "X"),
      KeyDraft(id: "C", label: "C"), KeyDraft(id: "V", label: "V"), KeyDraft(id: "B", label: "B"),
      KeyDraft(id: "N", label: "N"), KeyDraft(id: "M", label: "M"),
      KeyDraft(id: "Comma", label: ","),
      KeyDraft(id: "Period", label: "."), KeyDraft(id: "Slash", label: "/"),
      KeyDraft(id: "Right Shift", label: "shift", units: 1.75), KeyDraft(id: "Up", label: "↑"),
      KeyDraft(id: "End", label: "end"),
    ],
    [
      KeyDraft(id: "Left Control", label: "ctrl", units: 1.25),
      KeyDraft(id: "Left Option", label: "opt", units: 1.25),
      KeyDraft(id: "Left Command", label: "cmd", units: 1.25),
      KeyDraft(id: "Space", label: "space", units: 5),
      KeyDraft(id: "Right Option", label: "opt", units: 1.25), KeyDraft(id: "Fn", label: "fn"),
      KeyDraft(id: "Right Control", label: "ctrl", units: 1.25), KeyDraft(id: "Left", label: "←"),
      KeyDraft(id: "Down", label: "↓"), KeyDraft(id: "Right", label: "→"),
    ],
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        KeyCanvasMark(size: 28)
        Text("LAYOUT STUDY")
          .font(.caption.weight(.bold))
          .tracking(1.4)
          .foregroundStyle(.secondary)
        Spacer()
        StatusPill(label: "Local draft", symbol: "pencil", tint: StudioPalette.violet)
      }
      .padding(.bottom, 12)

      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 8) {
          ForEach(row) { key in
            KeycapButton(key: key, isSelected: selectedKey == key.id) {
              selectedKey = key.id
            }
          }
        }
      }
    }
    .padding(22)
    .background(
      StudioPalette.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(Color.white.opacity(0.08))
    }
  }
}

private struct KeycapButton: View {
  let key: KeyDraft
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(key.label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
        .frame(width: 46 * key.units + 8 * (key.units - 1), height: 44)
        .background(
          isSelected ? StudioPalette.blue : Color.white.opacity(0.08),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.white.opacity(isSelected ? 0.28 : 0.10))
        }
    }
    .buttonStyle(.plain)
  }
}
