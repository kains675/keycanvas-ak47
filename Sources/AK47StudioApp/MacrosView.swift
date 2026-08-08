import AK47InspectorCore
import Foundation
import SwiftUI

struct MacrosView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var profileStore: LocalProfileStore
  @State private var selectedID = ""
  @State private var macros: [MacroDraft] = []
  @State private var savedLocally = false
  @State private var tapKeyCode: UInt16 = 0x2C

  private var selectedIndex: Int? {
    macros.firstIndex(where: { $0.id == selectedID })
  }

  var body: some View {
    VStack(spacing: 0) {
      StudioSectionHeader(
        eyebrow: studioText("로컬 프로필", "Local profile", language: language),
        title: studioText("매크로", "Macros", language: language),
        detail: studioText(
          "검증 가능한 키 동작과 지연을 로컬 JSON 프로필에 구성합니다. 장치 저장은 비활성 상태입니다.",
          "Build validated key actions and delays in the local JSON profile. Device storage is disabled.",
          language: language
        )
      )
      .padding(28)

      Divider()

      HSplitView {
        macroList
          .frame(minWidth: 220, idealWidth: 250, maxWidth: 290)
        sequenceEditor
          .frame(minWidth: 560)
      }
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in loadProfile() }
  }

  private var macroList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(studioText("매크로 목록", "Macro list", language: language))
          .font(.headline)
        Spacer()
        Button(action: addMacro) {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help(studioText("새 매크로", "New macro", language: language))
      }

      ForEach(macros) { macro in
        Button {
          selectedID = macro.id
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "waveform")
              .foregroundStyle(selectedID == macro.id ? StudioPalette.blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(macro.name)
                .font(.callout.weight(.medium))
              Text("\(macro.steps.count) events · ×\(macro.repeatCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          .padding(10)
          .background(
            selectedID == macro.id ? StudioPalette.blue.opacity(0.11) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
          )
        }
        .buttonStyle(.plain)
      }

      Spacer()
      DemoNotice(compact: true)
    }
    .padding(18)
    .background(.regularMaterial)
  }

  @ViewBuilder
  private var sequenceEditor: some View {
    if let index = selectedIndex {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
              TextField(
                studioText("매크로 이름", "Macro name", language: language),
                text: Binding(
                  get: { macros[index].name },
                  set: {
                    macros[index].name = String($0.prefix(128))
                    savedLocally = false
                  }
                )
              )
              .font(.title2.weight(.bold))
              .textFieldStyle(.plain)

              Text(macros[index].id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            Spacer()
            StatusPill(
              label: savedLocally
                ? studioText("로컬 저장됨", "Saved locally", language: language)
                : studioText("장치에 저장되지 않음", "Not on device", language: language),
              symbol: savedLocally ? "checkmark.circle" : "internaldrive",
              tint: savedLocally ? StudioPalette.mint : StudioPalette.coral
            )
          }

          Stepper(
            studioText("반복", "Repeat", language: language) + ": \(macros[index].repeatCount)",
            value: Binding(
              get: { macros[index].repeatCount },
              set: {
                macros[index].repeatCount = $0
                savedLocally = false
              }
            ),
            in: 1...100
          )
          .frame(maxWidth: 280)

          VStack(spacing: 0) {
            if macros[index].steps.isEmpty {
              VStack(spacing: 10) {
                Image(systemName: "plus.square.dashed")
                  .font(.largeTitle)
                  .foregroundStyle(.secondary)
                Text(studioText("아직 동작이 없습니다", "No actions yet", language: language))
                  .font(.headline)
                Text(
                  studioText(
                    "아래 버튼으로 키 탭이나 지연을 추가하세요.",
                    "Add a key tap or delay with the controls below.",
                    language: language
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, minHeight: 220)
            } else {
              ForEach(Array(macros[index].steps.enumerated()), id: \.element.id) {
                eventIndex, step in
                MacroStepRow(index: eventIndex + 1, step: step) {
                  macros[index].steps.remove(at: eventIndex)
                  savedLocally = false
                }
                if eventIndex < macros[index].steps.count - 1 {
                  Divider().padding(.leading, 50)
                }
              }
            }
          }
          .studioPanel(padding: 12)

          HStack {
            Picker(studioText("키", "Key", language: language), selection: $tapKeyCode) {
              ForEach(MacroKeyOption.all) { option in
                Text(option.name).tag(option.code)
              }
            }
            .frame(width: 150)

            Button(action: addKeyTap) {
              Label(
                studioText("키 탭 추가", "Add key tap", language: language),
                systemImage: "keyboard")
            }
            .buttonStyle(.bordered)

            Button(action: addDelay) {
              Label(
                studioText("20 ms 지연 추가", "Add 20 ms delay", language: language),
                systemImage: "timer")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: saveProfile) {
              Label(
                studioText("프로필에 저장", "Save to profile", language: language),
                systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioPalette.blue)
          }

          if case .failed(let message) = profileStore.status {
            Label(message, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(StudioPalette.coral)
              .textSelection(.enabled)
          }
        }
        .padding(26)
      }
    } else {
      VStack(spacing: 12) {
        Image(systemName: "waveform")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)
        Text(studioText("매크로가 없습니다", "No macros", language: language))
          .font(.title3.weight(.semibold))
        Text(studioText("왼쪽의 + 버튼으로 시작하세요.", "Use the + button to begin.", language: language))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func addMacro() {
    let draft = MacroDraft(
      id: UUID().uuidString.lowercased(),
      name: studioText("새 매크로", "New macro", language: language),
      repeatCount: 1,
      steps: []
    )
    macros.append(draft)
    selectedID = draft.id
    savedLocally = false
  }

  private func addKeyTap() {
    guard let index = selectedIndex else { return }
    macros[index].steps.append(contentsOf: [
      MacroStep(event: .keyDown(tapKeyCode)),
      MacroStep(event: .delay(milliseconds: 20)),
      MacroStep(event: .keyUp(tapKeyCode)),
    ])
    savedLocally = false
  }

  private func addDelay() {
    guard let index = selectedIndex else { return }
    macros[index].steps.append(MacroStep(event: .delay(milliseconds: 20)))
    savedLocally = false
  }

  private func saveProfile() {
    profileStore.replaceMacros(macros.map(\.definition))
    profileStore.saveSelected()
    if case .saved = profileStore.status {
      savedLocally = true
    } else {
      savedLocally = false
    }
  }

  private func loadProfile() {
    let definitions = profileStore.selectedProfile.macros
    macros = definitions.isEmpty ? MacroDraft.samples : definitions.map(MacroDraft.init)
    selectedID = macros.first?.id ?? ""
    savedLocally = false
  }
}

private struct MacroDraft: Identifiable {
  var id: String
  var name: String
  var repeatCount: Int
  var steps: [MacroStep]

  init(id: String, name: String, repeatCount: Int, steps: [MacroStep]) {
    self.id = id
    self.name = name
    self.repeatCount = repeatCount
    self.steps = steps
  }

  init(_ definition: MacroDefinition) {
    id = definition.identifier
    name = definition.name
    repeatCount = definition.repeatCount
    steps = definition.events.map(MacroStep.init)
  }

  var definition: MacroDefinition {
    MacroDefinition(
      identifier: id,
      name: name,
      repeatCount: repeatCount,
      events: steps.map(\.event)
    )
  }

  static let samples = [
    MacroDraft(
      id: "quick-launcher",
      name: "Quick launcher",
      repeatCount: 1,
      steps: [
        MacroStep(event: .keyDown(0xE3)),
        MacroStep(event: .delay(milliseconds: 18)),
        MacroStep(event: .keyDown(0x2C)),
        MacroStep(event: .delay(milliseconds: 18)),
        MacroStep(event: .keyUp(0x2C)),
        MacroStep(event: .keyUp(0xE3)),
      ]
    ),
    MacroDraft(
      id: "window-overview",
      name: "Window overview",
      repeatCount: 1,
      steps: [
        MacroStep(event: .keyDown(0xE0)),
        MacroStep(event: .keyDown(0x52)),
        MacroStep(event: .delay(milliseconds: 20)),
        MacroStep(event: .keyUp(0x52)),
        MacroStep(event: .keyUp(0xE0)),
      ]
    ),
  ]
}

private struct MacroStep: Identifiable {
  let id = UUID()
  var event: MacroEvent

  init(event: MacroEvent) {
    self.event = event
  }

  var action: String {
    switch event {
    case .keyDown: "Key down"
    case .keyUp: "Key up"
    case .delay: "Delay"
    }
  }

  var value: String {
    switch event {
    case .keyDown(let code), .keyUp(let code): keyName(code)
    case .delay(let milliseconds): "\(milliseconds) ms"
    }
  }
}

private struct MacroStepRow: View {
  let index: Int
  let step: MacroStep
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Text("\(index)")
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(StudioPalette.blue)
        .frame(width: 28, height: 28)
        .background(StudioPalette.blue.opacity(0.11), in: Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(step.action)
          .font(.callout.weight(.medium))
        Text(step.value)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: remove) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
    }
    .padding(10)
  }
}

private func keyName(_ code: UInt16) -> String {
  MacroKeyOption.all.first(where: { $0.code == code })?.name
    ?? String(format: "HID 0x%04X", code)
}

private struct MacroKeyOption: Identifiable {
  let name: String
  let code: UInt16
  var id: UInt16 { code }

  static let all: [MacroKeyOption] =
    [
      MacroKeyOption(name: "Space", code: 0x2C),
      MacroKeyOption(name: "Return", code: 0x28),
      MacroKeyOption(name: "Escape", code: 0x29),
      MacroKeyOption(name: "Tab", code: 0x2B),
      MacroKeyOption(name: "Backspace", code: 0x2A),
      MacroKeyOption(name: "Arrow Up", code: 0x52),
      MacroKeyOption(name: "Arrow Down", code: 0x51),
      MacroKeyOption(name: "Arrow Left", code: 0x50),
      MacroKeyOption(name: "Arrow Right", code: 0x4F),
      MacroKeyOption(name: "Left Control", code: 0xE0),
      MacroKeyOption(name: "Left Option", code: 0xE2),
      MacroKeyOption(name: "Left Command", code: 0xE3),
    ]
    + zip(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), UInt16(0x04)...UInt16(0x1D)).map {
      MacroKeyOption(name: String($0.0), code: $0.1)
    }
}
