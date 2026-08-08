import Foundation

public struct ProfileValidationIssue: Codable, Equatable, Sendable {
  public let code: String
  public let path: String
  public let message: String

  public init(code: String, path: String, message: String) {
    self.code = code
    self.path = path
    self.message = message
  }
}

public struct ProfileValidationError: Error, Equatable, LocalizedError, Sendable {
  public let issues: [ProfileValidationIssue]

  public init(issues: [ProfileValidationIssue]) {
    self.issues = issues
  }

  public var errorDescription: String? {
    guard !issues.isEmpty else { return "profile validation failed" }
    return
      issues
      .map { "\($0.path): \($0.message)" }
      .joined(separator: "; ")
  }
}

extension DeviceProfile {
  public func validationIssues() -> [ProfileValidationIssue] {
    var issues: [ProfileValidationIssue] = []

    if schemaVersion != Self.currentSchemaVersion {
      issues.append(
        issue(
          "unsupported-schema",
          "schemaVersion",
          "only schema version \(Self.currentSchemaVersion) is supported"
        ))
    }
    validateIdentifier(identifier, path: "identifier", issues: &issues)
    validateName(name, path: "name", issues: &issues)

    let macroIdentifiers = validateMacros(macros, issues: &issues)
    validateKeymap(keymap, macroIdentifiers: macroIdentifiers, issues: &issues)
    validateLighting(lighting, issues: &issues)
    validateTFT(tft, issues: &issues)
    validateSettings(settings, issues: &issues)
    return issues
  }

  public func validated() throws -> DeviceProfile {
    let issues = validationIssues()
    guard issues.isEmpty else {
      throw ProfileValidationError(issues: issues)
    }
    return self
  }
}

public enum ProfileJSONCodec {
  public static func encode(
    _ profile: DeviceProfile,
    prettyPrinted: Bool = true
  ) throws -> Data {
    _ = try profile.validated()
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      prettyPrinted
      ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      : [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(profile)
  }

  public static func encodeString(
    _ profile: DeviceProfile,
    prettyPrinted: Bool = true
  ) throws -> String {
    String(decoding: try encode(profile, prettyPrinted: prettyPrinted), as: UTF8.self)
  }

  public static func decode(_ data: Data, validate: Bool = true) throws -> DeviceProfile {
    let profile = try JSONDecoder().decode(DeviceProfile.self, from: data)
    return validate ? try profile.validated() : profile
  }

  public static func decode(_ string: String, validate: Bool = true) throws -> DeviceProfile {
    try decode(Data(string.utf8), validate: validate)
  }
}

private func validateKeymap(
  _ keymap: KeymapProfile,
  macroIdentifiers: Set<String>,
  issues: inout [ProfileValidationIssue]
) {
  if keymap.assignments.count > 4_096 {
    issues.append(
      issue(
        "too-many-assignments",
        "keymap.assignments",
        "at most 4096 assignments are allowed"
      ))
  }

  var occupied: Set<String> = []
  for (index, assignment) in keymap.assignments.enumerated() {
    let path = "keymap.assignments[\(index)]"
    if !(0..<16).contains(assignment.layer) {
      issues.append(issue("invalid-layer", "\(path).layer", "layer must be between 0 and 15"))
    }
    if !(0..<1_024).contains(assignment.position) {
      issues.append(
        issue(
          "invalid-position",
          "\(path).position",
          "position must be between 0 and 1023"
        ))
    }

    let slot = "\(assignment.layer):\(assignment.position)"
    if !occupied.insert(slot).inserted {
      issues.append(issue("duplicate-assignment", path, "layer and position are duplicated"))
    }

    switch assignment.action {
    case .keyCode(let value), .consumerControl(let value):
      if value == 0 {
        issues.append(issue("invalid-action", "\(path).action", "action code must be non-zero"))
      }
    case .macro(let identifier):
      if normalized(identifier).isEmpty {
        issues.append(
          issue("invalid-macro-reference", "\(path).action", "macro identifier is empty"))
      } else if !macroIdentifiers.contains(identifier) {
        issues.append(issue("unknown-macro", "\(path).action", "referenced macro does not exist"))
      }
    case .disabled:
      break
    }
  }
}

private func validateLighting(
  _ lighting: LightingProfile,
  issues: inout [ProfileValidationIssue]
) {
  if normalized(lighting.effectIdentifier).isEmpty {
    issues.append(
      issue(
        "invalid-effect",
        "lighting.effectIdentifier",
        "effect identifier must not be empty"
      ))
  }
  validatePercentage(
    lighting.brightnessPercent,
    path: "lighting.brightnessPercent",
    issues: &issues
  )
  validatePercentage(
    lighting.speedPercent,
    path: "lighting.speedPercent",
    issues: &issues
  )

  var positions: Set<Int> = []
  for (index, item) in lighting.perKey.enumerated() {
    let path = "lighting.perKey[\(index)]"
    if !(0..<1_024).contains(item.position) {
      issues.append(
        issue(
          "invalid-position",
          "\(path).position",
          "position must be between 0 and 1023"
        ))
    }
    if !positions.insert(item.position).inserted {
      issues.append(issue("duplicate-lighting", path, "position is duplicated"))
    }
    validatePercentage(
      item.intensityPercent,
      path: "\(path).intensityPercent",
      issues: &issues
    )
  }
}

@discardableResult
private func validateMacros(
  _ macros: [MacroDefinition],
  issues: inout [ProfileValidationIssue]
) -> Set<String> {
  var identifiers: Set<String> = []

  for (macroIndex, macro) in macros.enumerated() {
    let path = "macros[\(macroIndex)]"
    validateIdentifier(macro.identifier, path: "\(path).identifier", issues: &issues)
    validateName(macro.name, path: "\(path).name", issues: &issues)
    if !identifiers.insert(macro.identifier).inserted {
      issues.append(
        issue("duplicate-macro", "\(path).identifier", "macro identifier is duplicated"))
    }
    if !(1...100).contains(macro.repeatCount) {
      issues.append(
        issue(
          "invalid-repeat-count",
          "\(path).repeatCount",
          "repeat count must be between 1 and 100"
        ))
    }
    if macro.events.count > 4_096 {
      issues.append(issue("too-many-events", "\(path).events", "at most 4096 events are allowed"))
    }

    var pressed: Set<UInt16> = []
    for (eventIndex, event) in macro.events.enumerated() {
      let eventPath = "\(path).events[\(eventIndex)]"
      switch event {
      case .keyDown(let keyCode):
        if keyCode == 0 {
          issues.append(issue("invalid-key-code", eventPath, "key code must be non-zero"))
        } else if !pressed.insert(keyCode).inserted {
          issues.append(issue("duplicate-key-down", eventPath, "key is already held"))
        }
      case .keyUp(let keyCode):
        if keyCode == 0 {
          issues.append(issue("invalid-key-code", eventPath, "key code must be non-zero"))
        } else if pressed.remove(keyCode) == nil {
          issues.append(issue("unmatched-key-up", eventPath, "key was not held"))
        }
      case .delay(let milliseconds):
        if !(1...60_000).contains(milliseconds) {
          issues.append(
            issue(
              "invalid-delay",
              eventPath,
              "delay must be between 1 and 60000 milliseconds"
            ))
        }
      }
    }
    if !pressed.isEmpty {
      issues.append(
        issue(
          "unreleased-keys",
          "\(path).events",
          "all pressed keys must be released"
        ))
    }
  }
  return identifiers
}

private func validateTFT(
  _ tft: TFTProfile,
  issues: inout [ProfileValidationIssue]
) {
  validateDimension(tft.canvasWidth, path: "tft.canvasWidth", issues: &issues)
  validateDimension(tft.canvasHeight, path: "tft.canvasHeight", issues: &issues)
  if !(1...240).contains(tft.frameRate) {
    issues.append(
      issue("invalid-frame-rate", "tft.frameRate", "frame rate must be between 1 and 240"))
  }
  if let themeIdentifier = tft.themeIdentifier {
    let clean = normalized(themeIdentifier)
    if clean.isEmpty || clean.count > 64 {
      issues.append(
        issue(
          "invalid-theme",
          "tft.themeIdentifier",
          "theme identifier must contain between 1 and 64 non-whitespace characters"
        ))
    }
  }
  if let message = tft.message, message.count > 128 {
    issues.append(
      issue(
        "message-too-long",
        "tft.message",
        "message must contain at most 128 characters"
      ))
  }

  var identifiers: Set<String> = []
  for (index, asset) in tft.assets.enumerated() {
    let path = "tft.assets[\(index)]"
    validateIdentifier(asset.identifier, path: "\(path).identifier", issues: &issues)
    if !identifiers.insert(asset.identifier).inserted {
      issues.append(
        issue("duplicate-asset", "\(path).identifier", "asset identifier is duplicated"))
    }
    if !isSafeResourceName(asset.resourceName) {
      issues.append(
        issue(
          "unsafe-resource-name",
          "\(path).resourceName",
          "resource name must be a relative name without parent traversal or a URL scheme"
        ))
    }
    validateDimension(asset.width, path: "\(path).width", issues: &issues)
    validateDimension(asset.height, path: "\(path).height", issues: &issues)
    if !(1...10_000).contains(asset.frameCount) {
      issues.append(
        issue(
          "invalid-frame-count",
          "\(path).frameCount",
          "frame count must be between 1 and 10000"
        ))
    }
  }

  for (index, identifier) in tft.playlist.enumerated() where !identifiers.contains(identifier) {
    issues.append(
      issue(
        "unknown-asset",
        "tft.playlist[\(index)]",
        "referenced asset does not exist"
      ))
  }
}

private func validateSettings(
  _ settings: DeviceSettings,
  issues: inout [ProfileValidationIssue]
) {
  if let timeout = settings.sleepTimeoutSeconds, !(0...86_400).contains(timeout) {
    issues.append(
      issue(
        "invalid-sleep-timeout",
        "settings.sleepTimeoutSeconds",
        "sleep timeout must be between 0 and 86400 seconds"
      ))
  }
  if !(0...1_000).contains(settings.debounceMilliseconds) {
    issues.append(
      issue(
        "invalid-debounce",
        "settings.debounceMilliseconds",
        "debounce must be between 0 and 1000 milliseconds"
      ))
  }
  if !(1...8_000).contains(settings.reportRateHz) {
    issues.append(
      issue(
        "invalid-report-rate",
        "settings.reportRateHz",
        "report rate must be between 1 and 8000 Hz"
      ))
  }
}

private func validateIdentifier(
  _ value: String,
  path: String,
  issues: inout [ProfileValidationIssue]
) {
  let clean = normalized(value)
  if clean.isEmpty || clean.count > 128 {
    issues.append(
      issue(
        "invalid-identifier",
        path,
        "identifier must contain between 1 and 128 non-whitespace characters"
      ))
  }
}

private func validateName(
  _ value: String,
  path: String,
  issues: inout [ProfileValidationIssue]
) {
  let clean = normalized(value)
  if clean.isEmpty || clean.count > 128 {
    issues.append(
      issue(
        "invalid-name",
        path,
        "name must contain between 1 and 128 non-whitespace characters"
      ))
  }
}

private func validatePercentage(
  _ value: Int,
  path: String,
  issues: inout [ProfileValidationIssue]
) {
  if !(0...100).contains(value) {
    issues.append(issue("invalid-percentage", path, "value must be between 0 and 100"))
  }
}

private func validateDimension(
  _ value: Int,
  path: String,
  issues: inout [ProfileValidationIssue]
) {
  if !(1...8_192).contains(value) {
    issues.append(issue("invalid-dimension", path, "dimension must be between 1 and 8192"))
  }
}

private func isSafeResourceName(_ value: String) -> Bool {
  let clean = normalized(value)
  guard !clean.isEmpty,
    !clean.hasPrefix("/"),
    !clean.hasPrefix("~"),
    URL(string: clean)?.scheme == nil
  else {
    return false
  }
  return
    !clean
    .replacingOccurrences(of: "\\", with: "/")
    .split(separator: "/", omittingEmptySubsequences: false)
    .contains("..")
}

private func normalized(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func issue(_ code: String, _ path: String, _ message: String) -> ProfileValidationIssue {
  ProfileValidationIssue(code: code, path: path, message: message)
}
