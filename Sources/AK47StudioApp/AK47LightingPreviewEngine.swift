import AK47InspectorCore
import Foundation

struct AK47LightingPreviewRGB: Equatable, Hashable, Sendable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8

  init(red: Double, green: Double, blue: Double) {
    self.init(
      redByte: Self.byte(red),
      greenByte: Self.byte(green),
      blueByte: Self.byte(blue)
    )
  }

  init(_ color: RGBColor) {
    self.init(redByte: color.red, greenByte: color.green, blueByte: color.blue)
  }

  init(redByte: UInt8, greenByte: UInt8, blueByte: UInt8) {
    red = redByte
    green = greenByte
    blue = blueByte
  }

  var normalizedRed: Double { Double(red) / 255 }
  var normalizedGreen: Double { Double(green) / 255 }
  var normalizedBlue: Double { Double(blue) / 255 }

  static func spectrum(phase: UInt8) -> Self {
    let sector = Int(phase) * 6
    let index = min(5, sector / 256)
    let fraction = UInt8(clamping: sector % 256)
    let descending = 255 &- fraction
    switch index {
    case 0: return .init(redByte: 255, greenByte: fraction, blueByte: 0)
    case 1: return .init(redByte: descending, greenByte: 255, blueByte: 0)
    case 2: return .init(redByte: 0, greenByte: 255, blueByte: fraction)
    case 3: return .init(redByte: 0, greenByte: descending, blueByte: 255)
    case 4: return .init(redByte: fraction, greenByte: 0, blueByte: 255)
    default: return .init(redByte: 255, greenByte: 0, blueByte: descending)
    }
  }

  private static func byte(_ component: Double) -> UInt8 {
    guard component.isFinite else { return 0 }
    return UInt8(clamping: Int((min(1, max(0, component)) * 255).rounded()))
  }
}

struct AK47LightingPreviewPixel: Equatable, Hashable, Sendable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8

  static let off = Self(red: 0, green: 0, blue: 0)

  var normalizedRed: Double { Double(red) / 255 }
  var normalizedGreen: Double { Double(green) / 255 }
  var normalizedBlue: Double { Double(blue) / 255 }
  var normalizedIntensity: Double { Double(max(red, max(green, blue))) / 255 }
}

struct AK47LightingPreviewKeyIndex: RawRepresentable, Equatable, Hashable, Sendable {
  let rawValue: Int

  init?(rawValue: Int) {
    guard AK47PhysicalLayout.keys.indices.contains(rawValue) else { return nil }
    self.rawValue = rawValue
  }
}

struct AK47LightingPreviewFrame: Equatable, Sendable {
  static let keyCount = 84

  let logicalTick: UInt64
  let pixelsByPhysicalKey: [AK47LightingPreviewPixel]

  init(logicalTick: UInt64, pixelsByPhysicalKey: [AK47LightingPreviewPixel]) {
    precondition(pixelsByPhysicalKey.count == Self.keyCount)
    self.logicalTick = logicalTick
    self.pixelsByPhysicalKey = pixelsByPhysicalKey
  }

  subscript(_ key: AK47LightingPreviewKeyIndex) -> AK47LightingPreviewPixel {
    pixelsByPhysicalKey[key.rawValue]
  }

  static let off = Self(
    logicalTick: 0,
    pixelsByPhysicalKey: Array(repeating: .off, count: keyCount)
  )
}

enum AK47LightingPreviewKeyEventKind: Equatable, Sendable {
  case down
  case up
}

struct AK47LightingPreviewKeyEvent: Equatable, Sendable {
  let logicalTick: UInt64
  let sequence: UInt64
  let key: AK47LightingPreviewKeyIndex
  let kind: AK47LightingPreviewKeyEventKind
}

struct AK47LightingPreviewConfiguration: Equatable, Sendable {
  let effect: AK47OnboardLightingEffect
  let isEnabled: Bool
  let speedLevel: UInt8
  let brightnessLevel: UInt8
  let direction: UInt8
  let colorful: Bool
  let baseColor: AK47LightingPreviewRGB

  init(
    effect: AK47OnboardLightingEffect,
    isEnabled: Bool = true,
    speedLevel: Int,
    brightnessLevel: Int,
    direction: Int = 0,
    colorful: Bool = false,
    baseColor: AK47LightingPreviewRGB
  ) {
    self.effect = effect
    self.isEnabled = isEnabled
    self.speedLevel = UInt8(clamping: min(5, max(1, speedLevel)))
    self.brightnessLevel = UInt8(clamping: min(5, max(0, brightnessLevel)))
    let supportsDirection = !effect.configurationCapabilities.intersection([
      .horizontalDirection, .verticalDirection,
    ]).isEmpty
    self.direction = supportsDirection && direction == 1 ? 1 : 0
    self.colorful = colorful && effect.configurationCapabilities.contains(.paletteToggle)
    self.baseColor = baseColor
  }
}

extension AK47OnboardLightingEffect {
  var isReactive: Bool {
    switch self {
    case .singleOn, .singleOff, .explode, .launch, .ripples:
      true
    default:
      false
    }
  }

  /// Project-authored pacing categories used only by the host preview.
  private var presentationPace: UInt64 {
    switch self {
    case .staticMode:
      120
    case .colourful, .spectrum, .scrolling, .rolling, .rotating:
      60
    case .singleOn, .singleOff, .glittering, .breath, .outward, .explode, .ripples,
      .flowing:
      100
    case .falling, .launch, .pulsating, .tilt, .shuttle:
      160
    }
  }

  func presentationStepPeriod(speedLevel: UInt8) -> UInt64 {
    let speed = min(5, max(1, UInt64(speedLevel)))
    return max(1, presentationPace * (6 - speed) / 3)
  }
}

/// An independently authored integer state machine. Movement topology and key-event behavior use
/// minimal interoperability facts. Pacing, intensity curves, palette, channel composition, and
/// physical optics are intentionally project-authored presentation choices.
struct AK47LightingPreviewEngine: Sendable {
  private struct KeyTopology: Sendable {
    let row: Int
    let column: Int
    let radialGroup: Int
    let angularGroup: Int
  }

  private struct Wave: Sendable {
    let row: Int
    let column: Int
    var age: Int
  }

  private struct RuntimeState: Sendable {
    var keyPhases = Array(repeating: UInt8(0), count: AK47LightingPreviewFrame.keyCount)
    var keyColorPhases = Array(repeating: UInt8(0), count: AK47LightingPreviewFrame.keyCount)
    var countdowns = Array(repeating: UInt8(1), count: AK47LightingPreviewFrame.keyCount)
    var columnMasks = Array(repeating: UInt8(0), count: 17)
    var lanePhases = Array(repeating: UInt8(0), count: 6)
    var columnPhases = Array(repeating: UInt8(0), count: 17)
    var accumulated = Array(repeating: false, count: AK47LightingPreviewFrame.keyCount)
    var waves: [Wave] = []
    var globalPhase = 0
    var cursor = 0
    var hueA: UInt8 = 0
    var hueB: UInt8 = 85
    var hueC: UInt8 = 170
    var isContracting = false
    var clearsAccumulatedBeforeNextStep = false
  }

  private struct PRNG: Sendable {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }

    mutating func byte(upperBound: UInt8) -> UInt8 {
      UInt8(next() % UInt64(max(1, upperBound)))
    }
  }

  private static let topology: [KeyTopology] = {
    let rowOrigins: [Double] = [0, 46, 82, 118, 157, 194]
    let centerX = Double(AK47PhysicalLayout.canvasSize.width) / 2
    let centerY = Double(AK47PhysicalLayout.canvasSize.height) / 2
    let raw = AK47PhysicalLayout.keys.map { key -> (Int, Int, Double, Int) in
      let row =
        rowOrigins.enumerated().min { first, second in
          abs(Double(key.y) - first.element) < abs(Double(key.y) - second.element)
        }?.offset ?? 0
      let column = min(
        16,
        max(0, Int((Double(key.center.x) / Double(AK47PhysicalLayout.canvasSize.width) * 17)))
      )
      let deltaX = Double(key.center.x) - centerX
      let deltaY = Double(key.center.y) - centerY
      let radialDistance = hypot(deltaX / centerX, deltaY / centerY)
      let angle = atan2(deltaY, deltaX)
      let angular = Int(((angle + .pi) / (.pi * 2) * 16).rounded(.down)) % 16
      return (row, column, radialDistance, angular)
    }
    let maximumRadius = raw.map(\.2).max() ?? 1
    return raw.map { row, column, radialDistance, angular in
      KeyTopology(
        row: row,
        column: column,
        radialGroup: min(16, Int((radialDistance / maximumRadius * 16).rounded())),
        angularGroup: angular
      )
    }
  }()
  private static let outwardPhaseGroups: [Int] = (0..<17).map { phase in
    topology.map(\.radialGroup).min { first, second in
      abs(first - phase) < abs(second - phase)
    } ?? 0
  }
  private static let rotatingGroups: [[Int]] = (0..<16).map { group in
    Array(
      topology.indices.sorted { first, second in
        let firstDirect = abs(topology[first].angularGroup - group)
        let secondDirect = abs(topology[second].angularGroup - group)
        let firstAngleDistance = min(firstDirect, 16 - firstDirect)
        let secondAngleDistance = min(secondDirect, 16 - secondDirect)
        if firstAngleDistance != secondAngleDistance {
          return firstAngleDistance < secondAngleDistance
        }
        if topology[first].radialGroup != topology[second].radialGroup {
          return topology[first].radialGroup < topology[second].radialGroup
        }
        return first < second
      }.prefix(3)
    )
  }

  private(set) var configuration: AK47LightingPreviewConfiguration
  private(set) var logicalTick: UInt64 = 0
  private(set) var completedStepCount: UInt64 = 0
  private var ticksUntilStep: UInt64
  private var state: RuntimeState
  private var keyDown = Array(repeating: false, count: AK47LightingPreviewFrame.keyCount)
  private var pendingEvents: [AK47LightingPreviewKeyEvent] = []
  private var prng: PRNG
  private var restartSeed: UInt64

  init(configuration: AK47LightingPreviewConfiguration, seed: UInt64 = 0x4B45_5943_414E_5641) {
    self.configuration = configuration
    ticksUntilStep = configuration.effect.presentationStepPeriod(
      speedLevel: configuration.speedLevel
    )
    state = RuntimeState()
    prng = PRNG(state: seed)
    restartSeed = seed
    initializeModeState()
  }

  mutating func restart(seed: UInt64? = nil) {
    if let seed { restartSeed = seed }
    logicalTick = 0
    completedStepCount = 0
    ticksUntilStep = configuration.effect.presentationStepPeriod(
      speedLevel: configuration.speedLevel
    )
    keyDown = Array(repeating: false, count: AK47LightingPreviewFrame.keyCount)
    pendingEvents = []
    state = RuntimeState()
    prng = PRNG(state: restartSeed)
    initializeModeState()
  }

  mutating func reconfigure(_ newConfiguration: AK47LightingPreviewConfiguration) {
    let changesMode =
      configuration.effect != newConfiguration.effect
      || configuration.isEnabled != newConfiguration.isEnabled
    let changesSpeed = configuration.speedLevel != newConfiguration.speedLevel
    configuration = newConfiguration
    if changesMode {
      restart()
    } else if changesSpeed {
      // A new speed applies from this point forward; elapsed ticks are never reinterpreted.
      ticksUntilStep = newConfiguration.effect.presentationStepPeriod(
        speedLevel: newConfiguration.speedLevel
      )
    }
  }

  mutating func enqueue(_ event: AK47LightingPreviewKeyEvent) {
    pendingEvents.append(event)
    pendingEvents.sort {
      ($0.logicalTick, $0.sequence) < ($1.logicalTick, $1.sequence)
    }
    processPendingEvents(through: logicalTick)
  }

  mutating func advance(to targetTick: UInt64) {
    guard targetTick >= logicalTick else { return }
    processPendingEvents(through: logicalTick)
    while logicalTick < targetTick {
      logicalTick &+= 1
      processPendingEvents(through: logicalTick)
      guard configuration.isEnabled, configuration.effect != .staticMode else { continue }
      if ticksUntilStep > 1 {
        ticksUntilStep -= 1
      } else {
        step()
        completedStepCount &+= 1
        ticksUntilStep = configuration.effect.presentationStepPeriod(
          speedLevel: configuration.speedLevel
        )
      }
    }
  }

  func frame() -> AK47LightingPreviewFrame {
    guard configuration.isEnabled else {
      return AK47LightingPreviewFrame(
        logicalTick: logicalTick,
        pixelsByPhysicalKey: Array(repeating: .off, count: AK47LightingPreviewFrame.keyCount)
      )
    }
    let logicalLEDs = Self.topology.indices.map { index in logicalLED(at: index) }
    let brightnessScale = configuration.brightnessLevel &* 51
    return AK47LightingPreviewFrame(
      logicalTick: logicalTick,
      pixelsByPhysicalKey: logicalLEDs.map { color, intensity in
        Self.compose(color: color, intensity: intensity, brightnessScale: brightnessScale)
      }
    )
  }

  private mutating func initializeModeState() {
    for index in state.keyColorPhases.indices {
      state.keyColorPhases[index] = UInt8((index * 192) / AK47LightingPreviewFrame.keyCount)
      state.countdowns[index] = 1 &+ prng.byte(upperBound: 126)
    }
    if configuration.effect == .singleOff {
      state.keyPhases = Array(repeating: 63, count: AK47LightingPreviewFrame.keyCount)
    }
    if configuration.effect == .tilt {
      for column in state.columnMasks.indices {
        state.columnMasks[column] = UInt8(1 << (column % 6))
      }
    }
    if configuration.effect == .scrolling {
      for row in state.lanePhases.indices {
        state.lanePhases[row] = UInt8(row * 2)
      }
    }
    if configuration.effect == .rolling {
      for column in state.columnPhases.indices {
        state.columnPhases[column] = UInt8(column)
      }
    }
    if configuration.effect == .flowing, effectiveReverse {
      state.cursor = state.accumulated.count - 1
    }
  }

  private mutating func processPendingEvents(through tick: UInt64) {
    while let first = pendingEvents.first, first.logicalTick <= tick {
      pendingEvents.removeFirst()
      let index = first.key.rawValue
      switch first.kind {
      case .down:
        guard !keyDown[index] else { continue }
        keyDown[index] = true
        handleDown(at: index)
      case .up:
        guard keyDown[index] else { continue }
        keyDown[index] = false
        handleUp(at: index)
      }
    }
  }

  private mutating func handleDown(at index: Int) {
    switch configuration.effect {
    case .singleOn:
      state.keyPhases[index] = 63
    case .singleOff:
      state.keyPhases[index] = 0
    case .explode, .launch, .ripples:
      let key = Self.topology[index]
      state.waves.append(Wave(row: key.row, column: key.column, age: 0))
    default:
      break
    }
  }

  private mutating func handleUp(at index: Int) {
    switch configuration.effect {
    case .singleOn:
      state.keyPhases[index] = 62
    case .singleOff:
      state.keyPhases[index] = 1
    default:
      break
    }
  }

  private mutating func step() {
    let reverse = effectiveReverse
    switch configuration.effect {
    case .staticMode:
      break
    case .singleOn:
      for index in state.keyPhases.indices where state.keyPhases[index] > 0 {
        state.keyPhases[index] -= 1
      }
    case .singleOff:
      for index in state.keyPhases.indices where state.keyPhases[index] < 63 {
        state.keyPhases[index] += 1
      }
    case .glittering:
      for index in state.countdowns.indices {
        if state.countdowns[index] > 1 {
          state.countdowns[index] -= 1
        } else {
          state.countdowns[index] = 1 &+ prng.byte(upperBound: 126)
          state.keyColorPhases[index] = prng.byte(upperBound: 255)
        }
      }
    case .falling:
      for column in state.columnMasks.indices {
        let seed = prng.next()
        let enters = ((seed >> UInt64(column % 19)) & 0x07) == 0
        state.columnMasks[column] = (state.columnMasks[column] << 1) & 0x3F
        if enters { state.columnMasks[column] |= 0x01 }
      }
    case .colourful:
      state.globalPhase = (state.globalPhase + 1) % 192
    case .breath:
      state.globalPhase = (state.globalPhase + 1) % 126
    case .spectrum:
      state.hueA &+= 1
      state.hueB &+= 2
      state.hueC &+= 3
    case .outward:
      state.globalPhase = wrappedStep(state.globalPhase, limit: 17, reverse: reverse)
    case .rotating:
      state.globalPhase = wrappedStep(state.globalPhase, limit: 16, reverse: reverse)
    case .pulsating:
      if state.isContracting {
        state.globalPhase -= 1
        if state.globalPhase == 0 { state.isContracting = false }
      } else {
        state.globalPhase += 1
        if state.globalPhase == 8 { state.isContracting = true }
      }
    case .scrolling:
      for lane in state.lanePhases.indices {
        state.lanePhases[lane] = UInt8(
          wrappedStep(Int(state.lanePhases[lane]), limit: 24, reverse: !reverse)
        )
      }
    case .rolling:
      for column in state.columnPhases.indices {
        state.columnPhases[column] = UInt8(
          wrappedStep(Int(state.columnPhases[column]), limit: 34, reverse: !reverse)
        )
      }
    case .explode, .launch, .ripples:
      for index in state.waves.indices { state.waves[index].age += 1 }
      state.waves.removeAll { $0.age > 20 }
    case .flowing:
      if state.clearsAccumulatedBeforeNextStep {
        state.accumulated = Array(repeating: false, count: state.accumulated.count)
        state.clearsAccumulatedBeforeNextStep = false
      }
      state.accumulated[state.cursor] = true
      let reachedTerminal = state.cursor == (reverse ? 0 : state.accumulated.count - 1)
      if reachedTerminal {
        state.clearsAccumulatedBeforeNextStep = true
        state.cursor = reverse ? state.accumulated.count - 1 : 0
      } else {
        state.cursor += reverse ? -1 : 1
      }
    case .tilt:
      let oldMasks = state.columnMasks
      for column in state.columnMasks.indices {
        let source =
          reverse
          ? (column + 1) % state.columnMasks.count
          : (column + state.columnMasks.count - 1) % state.columnMasks.count
        let mask = oldMasks[source]
        state.columnMasks[column] = ((mask << 1) | (mask >> 5)) & 0x3F
      }
    case .shuttle:
      let nextCursor = wrappedStep(state.cursor, limit: 17, reverse: reverse)
      if nextCursor == (reverse ? 16 : 0) {
        state.accumulated = Array(repeating: false, count: state.accumulated.count)
      }
      state.cursor = nextCursor
      for index in state.accumulated.indices {
        let column = Self.topology[index].column
        if column == state.cursor || column == 16 - state.cursor {
          state.accumulated[index] = true
        }
      }
    }
  }

  private func logicalLED(at index: Int) -> (AK47LightingPreviewRGB, UInt8) {
    let key = Self.topology[index]
    let intensity: UInt8
    switch configuration.effect {
    case .staticMode:
      intensity = 255
    case .singleOn, .singleOff:
      intensity = UInt8(clamping: Int(state.keyPhases[index]) * 4)
    case .glittering:
      let phase = Int(state.countdowns[index])
      let distance = abs(63 - phase)
      intensity = UInt8(clamping: max(12, (63 - min(63, distance)) * 4))
    case .falling, .tilt:
      let mask = state.columnMasks[key.column]
      intensity = mask & UInt8(1 << key.row) == 0 ? 12 : 255
    case .colourful, .spectrum:
      intensity = 255
    case .breath:
      let phase = state.globalPhase <= 63 ? state.globalPhase : 126 - state.globalPhase
      intensity = UInt8(clamping: 8 + phase * 247 / 63)
    case .outward:
      let visibleGroup = Self.outwardPhaseGroups[state.globalPhase]
      intensity = wrappedDistance(key.radialGroup, visibleGroup, modulus: 17) <= 1 ? 255 : 10
    case .scrolling:
      intensity = cyclicIntensity(
        phase: Int(state.lanePhases[key.row]),
        period: 24,
        falloff: 20
      )
    case .rolling:
      intensity = cyclicIntensity(
        phase: Int(state.columnPhases[key.column]),
        period: 34,
        falloff: 14
      )
    case .rotating:
      if configuration.colorful {
        // Direct hardware observation: the Colorful variant keeps the full field lit while
        // the angular palette rotates. The single-color presentation retains its narrow ribbon.
        intensity = 255
      } else {
        let target = state.globalPhase % 16
        intensity = Self.rotatingGroups[target].contains(index) ? 255 : 10
      }
    case .explode:
      intensity = waveIntensity(for: key) { wave, key in
        key.row == wave.row && abs(key.column - wave.column) == wave.age
      }
    case .launch:
      intensity = waveIntensity(for: key) { wave, key in
        abs(key.column - wave.column) == wave.age
      }
    case .ripples:
      intensity = waveIntensity(for: key) { wave, key in
        abs(key.column - wave.column) + abs(key.row - wave.row) == wave.age
      }
    case .flowing, .shuttle:
      intensity = state.accumulated[index] ? 255 : 8
    case .pulsating:
      intensity = abs(key.column - 8) == state.globalPhase ? 255 : 10
    }
    return (color(at: index), intensity)
  }

  private func color(at index: Int) -> AK47LightingPreviewRGB {
    switch configuration.effect {
    case .colourful:
      let phase = (Int(state.keyColorPhases[index]) + state.globalPhase) % 192
      return .spectrum(phase: UInt8(clamping: phase * 255 / 191))
    case .spectrum:
      let mixed = UInt8((UInt16(state.hueA) + UInt16(state.hueB) + UInt16(state.hueC)) / 3)
      return .spectrum(phase: mixed)
    case .rotating where configuration.colorful:
      let angularPhase =
        (Self.topology[index].angularGroup - state.globalPhase + 16) % 16
      return .spectrum(phase: UInt8(angularPhase * 16))
    default:
      guard configuration.colorful else { return configuration.baseColor }
      let offset = Int(state.keyColorPhases[index]) * 255 / 191
      let motion = (state.globalPhase * 3 + Int(state.keyColorPhases[index])) & 0xFF
      return .spectrum(phase: UInt8(clamping: (offset + motion) & 0xFF))
    }
  }

  private var effectiveReverse: Bool {
    guard configuration.direction == 1 else { return false }
    switch configuration.effect {
    case .scrolling, .rolling, .rotating, .flowing, .tilt:
      return true
    default:
      return false
    }
  }

  private func waveIntensity(
    for key: KeyTopology,
    matches: (Wave, KeyTopology) -> Bool
  ) -> UInt8 {
    state.waves.contains { matches($0, key) } ? 255 : 0
  }

  private func wrappedStep(_ value: Int, limit: Int, reverse: Bool) -> Int {
    let next = value + (reverse ? -1 : 1)
    return (next % limit + limit) % limit
  }

  private func wrappedDistance(_ first: Int, _ second: Int, modulus: Int) -> Int {
    let direct = abs(first - second)
    return min(direct, modulus - direct)
  }

  private func cyclicIntensity(phase: Int, period: Int, falloff: Int) -> UInt8 {
    let normalized = (phase % period + period) % period
    let distance = min(normalized, period - normalized)
    return UInt8(clamping: max(8, 255 - distance * falloff))
  }

  private static func compose(
    color: AK47LightingPreviewRGB,
    intensity: UInt8,
    brightnessScale: UInt8
  ) -> AK47LightingPreviewPixel {
    func channel(_ value: UInt8) -> UInt8 {
      UInt8(
        clamping: (Int(value) * Int(intensity) * Int(brightnessScale)) / (255 * 255)
      )
    }
    return AK47LightingPreviewPixel(
      red: channel(color.red),
      green: channel(color.green),
      blue: channel(color.blue)
    )
  }
}
