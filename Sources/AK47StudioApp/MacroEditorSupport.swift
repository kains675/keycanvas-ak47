import AK47InspectorCore
import Foundation

enum KeymapAssignmentChoice: Hashable {
  case keyCode(UInt16)
  case consumerControl(UInt16)
  case macro(identifier: String)
  case disabled

  init(action: KeyAction) {
    switch action {
    case .keyCode(let code):
      self = .keyCode(code)
    case .consumerControl(let usage):
      self = .consumerControl(usage)
    case .macro(let identifier):
      self = .macro(identifier: identifier)
    case .disabled:
      self = .disabled
    }
  }

  var action: KeyAction {
    switch self {
    case .keyCode(let code):
      return .keyCode(code)
    case .consumerControl(let usage):
      return .consumerControl(usage)
    case .macro(let identifier):
      return .macro(identifier: identifier)
    case .disabled:
      return .disabled
    }
  }
}

struct MacroStepDraft: Identifiable, Equatable {
  let id: UUID
  var event: MacroEvent

  init(id: UUID = UUID(), event: MacroEvent) {
    self.id = id
    self.event = event
  }
}

struct MacroDraft: Identifiable, Equatable {
  var id: String
  var name: String
  var repeatCount: Int
  var steps: [MacroStepDraft]

  init(id: String, name: String, repeatCount: Int, steps: [MacroStepDraft]) {
    self.id = id
    self.name = name
    self.repeatCount = repeatCount
    self.steps = steps
  }

  init(_ definition: MacroDefinition) {
    id = definition.identifier
    name = definition.name
    repeatCount = definition.repeatCount
    steps = definition.events.map { MacroStepDraft(event: $0) }
  }

  var definition: MacroDefinition {
    MacroDefinition(
      identifier: id,
      name: name,
      repeatCount: repeatCount,
      events: steps.map(\.event)
    )
  }

  func duplicate(identifier: String, name: String) -> MacroDraft {
    MacroDraft(
      id: identifier,
      name: name,
      repeatCount: repeatCount,
      steps: steps.map { MacroStepDraft(event: $0.event) }
    )
  }

  mutating func moveStep(from source: Int, to destination: Int) {
    guard steps.indices.contains(source), steps.indices.contains(destination), source != destination
    else { return }
    let step = steps.remove(at: source)
    steps.insert(step, at: destination)
  }
}

enum MacroEditorIntegrity {
  static func drafts(from definitions: [MacroDefinition]) -> [MacroDraft] {
    definitions.map(MacroDraft.init)
  }

  static func references(
    to identifier: String,
    in keymap: KeymapProfile
  ) -> [KeyAssignment] {
    keymap.assignments.filter { assignment in
      guard case .macro(let candidate) = assignment.action else { return false }
      return candidate == identifier
    }
  }

  static func validationIssues(
    for macros: [MacroDraft],
    in profile: DeviceProfile
  ) -> [ProfileValidationIssue] {
    var candidate = profile
    candidate.macros = macros.map(\.definition)
    return candidate.validationIssues().filter { issue in
      issue.path.hasPrefix("macros[") || issue.code == "unknown-macro"
    }
  }
}
