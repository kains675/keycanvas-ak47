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
  @State private var editorNotice: MacroEditorNotice?
  @State private var macroPendingDeletionID: String?

  private var selectedIndex: Int? {
    macros.firstIndex(where: { $0.id == selectedID })
  }

  private var validationIssues: [ProfileValidationIssue] {
    MacroEditorIntegrity.validationIssues(for: macros, in: profileStore.selectedProfile)
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
    .alert(
      studioText("매크로 삭제", "Delete macro", language: language),
      isPresented: Binding(
        get: { macroPendingDeletionID != nil },
        set: { if !$0 { macroPendingDeletionID = nil } }
      )
    ) {
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {
        macroPendingDeletionID = nil
      }
      Button(studioText("삭제", "Delete", language: language), role: .destructive) {
        confirmDeleteMacro()
      }
    } message: {
      Text(
        studioText(
          "이 매크로를 로컬 초안에서 삭제합니다. 변경 사항은 프로필을 저장할 때 확정됩니다.",
          "This removes the macro from the local draft. The change is committed when you save the profile.",
          language: language
        )
      )
    }
  }

  private var macroList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(studioText("매크로 목록", "Macro list", language: language))
          .font(.headline)
        Spacer()
        Button(action: addExampleMacro) {
          Image(systemName: "sparkles")
        }
        .buttonStyle(.borderless)
        .help(studioText("예제 매크로 추가", "Add example macro", language: language))

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
              Text(
                studioText(
                  "동작 \(macro.steps.count)개 · ×\(macro.repeatCount)",
                  "\(macro.steps.count) events · ×\(macro.repeatCount)",
                  language: language
                )
              )
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
      if let editorNotice {
        Label(editorNotice.message, systemImage: editorNotice.symbol)
          .font(.caption)
          .foregroundStyle(editorNotice.tint)
          .fixedSize(horizontal: false, vertical: true)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(editorNotice.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      }
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
                    markEdited()
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
            HStack(spacing: 8) {
              Button(action: duplicateSelectedMacro) {
                Image(systemName: "plus.square.on.square")
              }
              .buttonStyle(.bordered)
              .help(studioText("매크로 복제", "Duplicate macro", language: language))

              Button(action: requestDeleteSelectedMacro) {
                Image(systemName: "trash")
              }
              .buttonStyle(.bordered)
              .tint(StudioPalette.coral)
              .help(studioText("매크로 삭제", "Delete macro", language: language))
            }
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
                markEdited()
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
                eventIndex, _ in
                MacroStepRow(
                  index: eventIndex + 1,
                  step: Binding(
                    get: { macros[index].steps[eventIndex] },
                    set: {
                      macros[index].steps[eventIndex] = $0
                      markEdited()
                    }
                  ),
                  canMoveUp: eventIndex > 0,
                  canMoveDown: eventIndex < macros[index].steps.count - 1,
                  moveUp: { moveStep(at: eventIndex, by: -1) },
                  moveDown: { moveStep(at: eventIndex, by: 1) },
                  remove: {
                    macros[index].steps.remove(at: eventIndex)
                    markEdited()
                  }
                )
                if eventIndex < macros[index].steps.count - 1 {
                  Divider().padding(.leading, 50)
                }
              }
            }
          }
          .studioPanel(padding: 12)

          if !validationIssues.isEmpty {
            MacroValidationPanel(issues: validationIssues)
          }

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
            .disabled(!validationIssues.isEmpty)
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
        Text(
          studioText(
            "새 매크로를 만들거나 명시적으로 예제를 추가하세요.",
            "Create a macro or explicitly add an example.",
            language: language
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          Button(action: addMacro) {
            Label(
              studioText("새 매크로", "New macro", language: language),
              systemImage: "plus")
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.blue)

          Button(action: addExampleMacro) {
            Label(
              studioText("예제 추가", "Add example", language: language),
              systemImage: "sparkles")
          }
          .buttonStyle(.bordered)
        }

        Button(action: saveProfile) {
          Label(
            studioText("빈 매크로 목록 저장", "Save empty macro list", language: language),
            systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderless)
        .disabled(!validationIssues.isEmpty)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func addMacro() {
    let draft = MacroDraft(
      id: freshMacroIdentifier(),
      name: uniqueMacroName(studioText("새 매크로", "New macro", language: language)),
      repeatCount: 1,
      steps: []
    )
    macros.append(draft)
    selectedID = draft.id
    markEdited()
  }

  private func addExampleMacro() {
    let draft = MacroDraft(
      id: freshMacroIdentifier(),
      name: uniqueMacroName(
        studioText("빠른 실행 예제", "Quick launcher example", language: language)
      ),
      repeatCount: 1,
      steps: [
        MacroStepDraft(event: .keyDown(0xE3)),
        MacroStepDraft(event: .delay(milliseconds: 20)),
        MacroStepDraft(event: .keyDown(0x2C)),
        MacroStepDraft(event: .delay(milliseconds: 20)),
        MacroStepDraft(event: .keyUp(0x2C)),
        MacroStepDraft(event: .keyUp(0xE3)),
      ]
    )
    macros.append(draft)
    selectedID = draft.id
    markEdited()
  }

  private func addKeyTap() {
    guard let index = selectedIndex else { return }
    macros[index].steps.append(contentsOf: [
      MacroStepDraft(event: .keyDown(tapKeyCode)),
      MacroStepDraft(event: .delay(milliseconds: 20)),
      MacroStepDraft(event: .keyUp(tapKeyCode)),
    ])
    markEdited()
  }

  private func addDelay() {
    guard let index = selectedIndex else { return }
    macros[index].steps.append(MacroStepDraft(event: .delay(milliseconds: 20)))
    markEdited()
  }

  private func saveProfile() {
    guard validationIssues.isEmpty else {
      editorNotice = MacroEditorNotice(
        message: studioText(
          "검증 오류를 수정한 뒤 저장해 주세요.",
          "Fix the validation errors before saving.",
          language: language
        ),
        symbol: "exclamationmark.triangle",
        tint: StudioPalette.coral
      )
      return
    }
    profileStore.replaceMacros(macros.map(\.definition))
    profileStore.saveSelected()
    if case .saved = profileStore.status {
      savedLocally = true
      editorNotice = nil
    } else {
      savedLocally = false
    }
  }

  private func loadProfile() {
    macros = MacroEditorIntegrity.drafts(from: profileStore.selectedProfile.macros)
    selectedID = macros.first?.id ?? ""
    savedLocally = false
    editorNotice = nil
    macroPendingDeletionID = nil
  }

  private func duplicateSelectedMacro() {
    guard let index = selectedIndex else { return }
    let source = macros[index]
    let copyName = uniqueMacroName(
      studioText("\(source.name) 복사본", "\(source.name) Copy", language: language)
    )
    let copy = source.duplicate(identifier: freshMacroIdentifier(), name: copyName)
    macros.insert(copy, at: index + 1)
    selectedID = copy.id
    markEdited()
  }

  private func requestDeleteSelectedMacro() {
    guard let index = selectedIndex else { return }
    let macro = macros[index]
    let references = MacroEditorIntegrity.references(
      to: macro.id,
      in: profileStore.selectedProfile.keymap
    )
    guard references.isEmpty else {
      editorNotice = MacroEditorNotice(
        message: studioText(
          "‘\(macro.name)’ 매크로가 키맵 \(references.count)곳에 할당되어 있어 삭제할 수 없습니다. 먼저 키맵 할당을 변경해 주세요.",
          "‘\(macro.name)’ is assigned to \(references.count) keymap location(s). Change those assignments before deleting it.",
          language: language
        ),
        symbol: "lock.trianglebadge.exclamationmark",
        tint: StudioPalette.coral
      )
      return
    }
    macroPendingDeletionID = macro.id
  }

  private func confirmDeleteMacro() {
    guard let identifier = macroPendingDeletionID,
      let index = macros.firstIndex(where: { $0.id == identifier })
    else {
      macroPendingDeletionID = nil
      return
    }
    macros.remove(at: index)
    selectedID = macros.indices.contains(index) ? macros[index].id : macros.last?.id ?? ""
    macroPendingDeletionID = nil
    markEdited()
  }

  private func moveStep(at index: Int, by offset: Int) {
    guard let macroIndex = selectedIndex else { return }
    macros[macroIndex].moveStep(from: index, to: index + offset)
    markEdited()
  }

  private func freshMacroIdentifier() -> String {
    let existing = Set(macros.map(\.id))
    var identifier: String
    repeat {
      identifier = UUID().uuidString.lowercased()
    } while existing.contains(identifier)
    return identifier
  }

  private func uniqueMacroName(_ preferredName: String) -> String {
    let existing = Set(macros.map(\.name))
    var suffix = ""
    var number = 1
    while true {
      let availableCount = max(1, 128 - suffix.count)
      let stem = String(preferredName.prefix(availableCount))
      let candidate = stem + suffix
      if !existing.contains(candidate) {
        return candidate
      }
      number += 1
      suffix = " \(number)"
    }
  }

  private func markEdited() {
    savedLocally = false
    editorNotice = nil
  }
}

private struct MacroStepRow: View {
  @Environment(\.studioLanguage) private var language
  let index: Int
  @Binding var step: MacroStepDraft
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Text("\(index)")
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(StudioPalette.blue)
        .frame(width: 28, height: 28)
        .background(StudioPalette.blue.opacity(0.11), in: Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(actionLabel)
          .font(.callout.weight(.medium))
        if case .delay(let milliseconds) = step.event {
          HStack(spacing: 6) {
            TextField(
              studioText("지연", "Delay", language: language),
              value: delayBinding,
              format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 88)
            .overlay {
              if !(1...60_000).contains(milliseconds) {
                RoundedRectangle(cornerRadius: 5)
                  .stroke(StudioPalette.coral, lineWidth: 1)
              }
            }
            Text("ms")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
            Stepper("", value: stepperDelayBinding, in: 1...60_000)
              .labelsHidden()
          }
          Text(studioText("허용 범위: 1–60,000 ms", "Allowed: 1–60,000 ms", language: language))
            .font(.caption2)
            .foregroundStyle(
              (1...60_000).contains(milliseconds) ? Color.secondary : StudioPalette.coral
            )
        } else {
          Text(valueLabel)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      HStack(spacing: 4) {
        Button(action: moveUp) {
          Image(systemName: "chevron.up")
        }
        .disabled(!canMoveUp)
        .help(studioText("위로 이동", "Move up", language: language))

        Button(action: moveDown) {
          Image(systemName: "chevron.down")
        }
        .disabled(!canMoveDown)
        .help(studioText("아래로 이동", "Move down", language: language))
      }
      .buttonStyle(.borderless)
      Button(action: remove) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help(studioText("동작 삭제", "Delete action", language: language))
    }
    .padding(10)
  }

  private var actionLabel: String {
    switch step.event {
    case .keyDown:
      return studioText("키 누르기", "Key down", language: language)
    case .keyUp:
      return studioText("키 떼기", "Key up", language: language)
    case .delay:
      return studioText("지연", "Delay", language: language)
    }
  }

  private var valueLabel: String {
    switch step.event {
    case .keyDown(let code), .keyUp(let code):
      return keyName(code)
    case .delay(let milliseconds):
      return "\(milliseconds) ms"
    }
  }

  private var delayBinding: Binding<Int> {
    Binding(
      get: {
        guard case .delay(let milliseconds) = step.event else { return 20 }
        return milliseconds
      },
      set: { step.event = .delay(milliseconds: $0) }
    )
  }

  private var stepperDelayBinding: Binding<Int> {
    Binding(
      get: { min(max(delayBinding.wrappedValue, 1), 60_000) },
      set: { delayBinding.wrappedValue = $0 }
    )
  }
}

private struct MacroValidationPanel: View {
  @Environment(\.studioLanguage) private var language
  let issues: [ProfileValidationIssue]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        studioText("저장 전에 확인해 주세요", "Fix before saving", language: language),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.callout.weight(.semibold))
      .foregroundStyle(StudioPalette.coral)

      ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
        Text("• \(message(for: issue))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(StudioPalette.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  private func message(for issue: ProfileValidationIssue) -> String {
    let localized: String
    switch issue.code {
    case "invalid-name":
      localized = studioText(
        "매크로 이름은 공백이 아닌 1–128자여야 합니다.",
        "Macro names must contain 1–128 non-whitespace characters.",
        language: language
      )
    case "invalid-repeat-count":
      localized = studioText(
        "반복 횟수는 1–100이어야 합니다.",
        "Repeat count must be between 1 and 100.",
        language: language
      )
    case "invalid-delay":
      localized = studioText(
        "지연은 1–60,000 ms여야 합니다.",
        "Delay must be between 1 and 60,000 ms.",
        language: language
      )
    case "duplicate-key-down":
      localized = studioText(
        "이미 누른 키를 다시 누르고 있습니다.",
        "A key is pressed again before it is released.",
        language: language
      )
    case "unmatched-key-up":
      localized = studioText(
        "누르지 않은 키를 떼는 동작이 있습니다.",
        "A key-up action has no matching key-down action.",
        language: language
      )
    case "unreleased-keys":
      localized = studioText(
        "마지막에 떼지 않은 키가 있습니다.",
        "One or more pressed keys are not released at the end.",
        language: language
      )
    case "unknown-macro":
      localized = studioText(
        "키맵이 존재하지 않는 매크로를 참조합니다.",
        "The keymap references a macro that does not exist.",
        language: language
      )
    default:
      localized = issue.message
    }
    return "\(issue.path): \(localized)"
  }
}

private struct MacroEditorNotice {
  let message: String
  let symbol: String
  let tint: Color
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
