import Foundation

public struct KeyAssignment: Codable, Equatable, Sendable {
  public let layer: Int
  public let position: Int
  public let action: KeyAction

  public init(layer: Int, position: Int, action: KeyAction) {
    self.layer = layer
    self.position = position
    self.action = action
  }
}

public enum KeyAction: Equatable, Sendable {
  case keyCode(UInt16)
  case consumerControl(UInt16)
  case macro(identifier: String)
  case disabled
}

extension KeyAction: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case value
  }

  private enum Kind: String, Codable {
    case keyCode = "key-code"
    case consumerControl = "consumer-control"
    case macro
    case disabled
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .keyCode:
      self = .keyCode(try container.decode(UInt16.self, forKey: .value))
    case .consumerControl:
      self = .consumerControl(try container.decode(UInt16.self, forKey: .value))
    case .macro:
      self = .macro(identifier: try container.decode(String.self, forKey: .value))
    case .disabled:
      self = .disabled
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .keyCode(let value):
      try container.encode(Kind.keyCode, forKey: .type)
      try container.encode(value, forKey: .value)
    case .consumerControl(let value):
      try container.encode(Kind.consumerControl, forKey: .type)
      try container.encode(value, forKey: .value)
    case .macro(let identifier):
      try container.encode(Kind.macro, forKey: .type)
      try container.encode(identifier, forKey: .value)
    case .disabled:
      try container.encode(Kind.disabled, forKey: .type)
    }
  }
}

public struct KeymapProfile: Codable, Equatable, Sendable {
  public var assignments: [KeyAssignment]

  public init(assignments: [KeyAssignment] = []) {
    self.assignments = assignments
  }
}

public struct RGBColor: Codable, Equatable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public struct PerKeyLighting: Codable, Equatable, Sendable {
  public let position: Int
  public let color: RGBColor
  public let intensityPercent: Int

  public init(position: Int, color: RGBColor, intensityPercent: Int = 100) {
    self.position = position
    self.color = color
    self.intensityPercent = intensityPercent
  }
}

public struct LightingProfile: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var effectIdentifier: String
  public var brightnessPercent: Int
  public var speedPercent: Int
  public var baseColor: RGBColor
  public var accentColor: RGBColor?
  public var perKey: [PerKeyLighting]

  public init(
    enabled: Bool = true,
    effectIdentifier: String = "static",
    brightnessPercent: Int = 100,
    speedPercent: Int = 50,
    baseColor: RGBColor = RGBColor(red: 255, green: 255, blue: 255),
    accentColor: RGBColor? = nil,
    perKey: [PerKeyLighting] = []
  ) {
    self.enabled = enabled
    self.effectIdentifier = effectIdentifier
    self.brightnessPercent = brightnessPercent
    self.speedPercent = speedPercent
    self.baseColor = baseColor
    self.accentColor = accentColor
    self.perKey = perKey
  }
}

public enum MacroEvent: Equatable, Sendable {
  case keyDown(UInt16)
  case keyUp(UInt16)
  case delay(milliseconds: Int)
}

extension MacroEvent: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case value
  }

  private enum Kind: String, Codable {
    case keyDown = "key-down"
    case keyUp = "key-up"
    case delay
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .keyDown:
      self = .keyDown(try container.decode(UInt16.self, forKey: .value))
    case .keyUp:
      self = .keyUp(try container.decode(UInt16.self, forKey: .value))
    case .delay:
      self = .delay(milliseconds: try container.decode(Int.self, forKey: .value))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .keyDown(let value):
      try container.encode(Kind.keyDown, forKey: .type)
      try container.encode(value, forKey: .value)
    case .keyUp(let value):
      try container.encode(Kind.keyUp, forKey: .type)
      try container.encode(value, forKey: .value)
    case .delay(let milliseconds):
      try container.encode(Kind.delay, forKey: .type)
      try container.encode(milliseconds, forKey: .value)
    }
  }
}

public struct MacroDefinition: Codable, Equatable, Sendable {
  public var identifier: String
  public var name: String
  public var repeatCount: Int
  public var events: [MacroEvent]

  public init(
    identifier: String,
    name: String,
    repeatCount: Int = 1,
    events: [MacroEvent] = []
  ) {
    self.identifier = identifier
    self.name = name
    self.repeatCount = repeatCount
    self.events = events
  }
}

public struct DisplayAssetReference: Codable, Equatable, Sendable {
  public var identifier: String
  public var resourceName: String
  public var width: Int
  public var height: Int
  public var frameCount: Int

  public init(
    identifier: String,
    resourceName: String,
    width: Int,
    height: Int,
    frameCount: Int = 1
  ) {
    self.identifier = identifier
    self.resourceName = resourceName
    self.width = width
    self.height = height
    self.frameCount = frameCount
  }
}

public struct TFTProfile: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var canvasWidth: Int
  public var canvasHeight: Int
  public var frameRate: Int
  public var assets: [DisplayAssetReference]
  public var playlist: [String]
  public var themeIdentifier: String?
  public var message: String?
  public var accentColor: RGBColor?
  public var showsClock: Bool?
  public var showsBattery: Bool?

  public init(
    enabled: Bool = false,
    canvasWidth: Int = 1,
    canvasHeight: Int = 1,
    frameRate: Int = 30,
    assets: [DisplayAssetReference] = [],
    playlist: [String] = [],
    themeIdentifier: String? = nil,
    message: String? = nil,
    accentColor: RGBColor? = nil,
    showsClock: Bool? = nil,
    showsBattery: Bool? = nil
  ) {
    self.enabled = enabled
    self.canvasWidth = canvasWidth
    self.canvasHeight = canvasHeight
    self.frameRate = frameRate
    self.assets = assets
    self.playlist = playlist
    self.themeIdentifier = themeIdentifier
    self.message = message
    self.accentColor = accentColor
    self.showsClock = showsClock
    self.showsBattery = showsBattery
  }
}

public struct DeviceSettings: Codable, Equatable, Sendable {
  public var sleepTimeoutSeconds: Int?
  public var debounceMilliseconds: Int
  public var reportRateHz: Int
  public var functionLayerEnabled: Bool

  public init(
    sleepTimeoutSeconds: Int? = nil,
    debounceMilliseconds: Int = 5,
    reportRateHz: Int = 1_000,
    functionLayerEnabled: Bool = true
  ) {
    self.sleepTimeoutSeconds = sleepTimeoutSeconds
    self.debounceMilliseconds = debounceMilliseconds
    self.reportRateHz = reportRateHz
    self.functionLayerEnabled = functionLayerEnabled
  }
}

public struct DeviceProfile: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var identifier: String
  public var name: String
  public var keymap: KeymapProfile
  public var lighting: LightingProfile
  public var macros: [MacroDefinition]
  public var tft: TFTProfile
  public var settings: DeviceSettings

  public init(
    schemaVersion: Int = DeviceProfile.currentSchemaVersion,
    identifier: String,
    name: String,
    keymap: KeymapProfile = KeymapProfile(),
    lighting: LightingProfile = LightingProfile(),
    macros: [MacroDefinition] = [],
    tft: TFTProfile = TFTProfile(),
    settings: DeviceSettings = DeviceSettings()
  ) {
    self.schemaVersion = schemaVersion
    self.identifier = identifier
    self.name = name
    self.keymap = keymap
    self.lighting = lighting
    self.macros = macros
    self.tft = tft
    self.settings = settings
  }
}
