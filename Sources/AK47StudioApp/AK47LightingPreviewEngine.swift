import AK47InspectorCore
import CoreGraphics
import Foundation

struct AK47LightingPreviewRGB: Equatable {
  let red: Double
  let green: Double
  let blue: Double

  init(red: Double, green: Double, blue: Double) {
    self.red = min(1, max(0, red))
    self.green = min(1, max(0, green))
    self.blue = min(1, max(0, blue))
  }

  init(_ color: RGBColor) {
    self.init(
      red: Double(color.red) / 255,
      green: Double(color.green) / 255,
      blue: Double(color.blue) / 255
    )
  }

  static func mix(_ first: Self, _ second: Self, amount: Double) -> Self {
    let amount = min(1, max(0, amount))
    return Self(
      red: first.red + (second.red - first.red) * amount,
      green: first.green + (second.green - first.green) * amount,
      blue: first.blue + (second.blue - first.blue) * amount
    )
  }

  static func spectrum(hue: Double) -> Self {
    let hue = positiveRemainder(hue, modulus: 1)
    let sector = hue * 6
    let fraction = sector - floor(sector)
    let descending = 1 - fraction
    switch Int(sector) % 6 {
    case 0: return Self(red: 1, green: fraction, blue: 0)
    case 1: return Self(red: descending, green: 1, blue: 0)
    case 2: return Self(red: 0, green: 1, blue: fraction)
    case 3: return Self(red: 0, green: descending, blue: 1)
    case 4: return Self(red: fraction, green: 0, blue: 1)
    default: return Self(red: 1, green: 0, blue: descending)
    }
  }
}

struct AK47LightingPreviewSample: Equatable {
  let color: AK47LightingPreviewRGB
  let intensity: Double

  init(color: AK47LightingPreviewRGB, intensity: Double) {
    self.color = color
    self.intensity = min(1, max(0, intensity))
  }

  static let off = Self(color: .init(red: 0, green: 0, blue: 0), intensity: 0)
}

struct AK47LightingPreviewPress: Equatable {
  let keyID: String
  let origin: CGPoint
  let timestamp: TimeInterval
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
}

/// A deterministic KeyCanvas-authored approximation of the named onboard effects.
/// It intentionally does not claim to reproduce the keyboard firmware's frame math.
enum AK47LightingPreviewEngine {
  static func press(for key: AK47PhysicalKey, at time: TimeInterval) -> AK47LightingPreviewPress {
    AK47LightingPreviewPress(keyID: key.id, origin: key.center, timestamp: max(0, time))
  }

  static func frame(
    effect: AK47OnboardLightingEffect,
    keys: [AK47PhysicalKey] = AK47PhysicalLayout.keys,
    time: TimeInterval,
    speedLevel: Double,
    brightnessLevel: Double,
    direction: Int = 0,
    baseColor: AK47LightingPreviewRGB,
    accentColor: AK47LightingPreviewRGB,
    manualPresses: [AK47LightingPreviewPress] = [],
    includesSimulatedInput: Bool = true
  ) -> [String: AK47LightingPreviewSample] {
    let time = max(0, time)
    let speed = min(5, max(1, speedLevel))
    let brightness = min(5, max(0, brightnessLevel)) / 5
    let supportsDirection = !effect.configurationCapabilities.intersection([
      .horizontalDirection, .verticalDirection,
    ]).isEmpty
    let directionSign = supportsDirection && direction != 0 ? -1.0 : 1.0
    let presses = activePresses(
      effect: effect,
      keys: keys,
      time: time,
      speed: speed,
      manualPresses: manualPresses,
      includesSimulatedInput: includesSimulatedInput
    )

    var result: [String: AK47LightingPreviewSample] = [:]
    result.reserveCapacity(keys.count)
    for (ordinal, key) in keys.enumerated() {
      var sample =
        if effect.isReactive {
          reactiveSample(
            effect: effect,
            key: key,
            time: time,
            speed: speed,
            baseColor: baseColor,
            accentColor: accentColor,
            presses: presses
          )
        } else {
          periodicSample(
            effect: effect,
            key: key,
            ordinal: ordinal,
            keyCount: keys.count,
            time: time,
            speed: speed,
            directionSign: directionSign,
            baseColor: baseColor,
            accentColor: accentColor
          )
        }
      sample = AK47LightingPreviewSample(
        color: sample.color,
        intensity: sample.intensity * brightness
      )
      result[key.id] = sample
    }
    return result
  }

  private static func activePresses(
    effect: AK47OnboardLightingEffect,
    keys: [AK47PhysicalKey],
    time: TimeInterval,
    speed: Double,
    manualPresses: [AK47LightingPreviewPress],
    includesSimulatedInput: Bool
  ) -> [AK47LightingPreviewPress] {
    guard effect.isReactive else { return [] }
    let duration = reactiveDuration(for: effect)
    var presses = manualPresses.filter {
      let age = time - $0.timestamp
      return age >= 0 && age <= duration
    }
    guard includesSimulatedInput, !keys.isEmpty else { return presses }

    let interval = 1.65 / (0.72 + speed * 0.13)
    let cycle = max(0, Int(floor(time / interval)))
    let timestamp = Double(cycle) * interval
    let preferredIDs = ["Space", "A", "Return", "J", "Esc", "Up"]
    let preferredID = preferredIDs[cycle % preferredIDs.count]
    let key = keys.first(where: { $0.id == preferredID }) ?? keys[(cycle * 17) % keys.count]
    presses.append(press(for: key, at: timestamp))
    return presses
  }

  private static func periodicSample(
    effect: AK47OnboardLightingEffect,
    key: AK47PhysicalKey,
    ordinal: Int,
    keyCount: Int,
    time: TimeInterval,
    speed: Double,
    directionSign: Double,
    baseColor: AK47LightingPreviewRGB,
    accentColor: AK47LightingPreviewRGB
  ) -> AK47LightingPreviewSample {
    let x = key.center.x / AK47PhysicalLayout.canvasSize.width
    let y = key.center.y / AK47PhysicalLayout.canvasSize.height
    let dx =
      (key.center.x - AK47PhysicalLayout.canvasSize.width / 2)
      / AK47PhysicalLayout.canvasSize.height
    let dy =
      (key.center.y - AK47PhysicalLayout.canvasSize.height / 2)
      / AK47PhysicalLayout.canvasSize.height
    let distance = hypot(dx, dy)
    let phase = time * (0.22 + speed * 0.13) * directionSign

    switch effect {
    case .staticMode:
      return .init(color: baseColor, intensity: 1)
    case .glittering:
      let seed = deterministicNoise(ordinal * 71 + key.lightIndex * 13)
      let sparkle = pow(max(0, sin((phase * (2.4 + seed) + seed) * .pi * 2)), 18)
      return .init(
        color: .mix(baseColor, accentColor, amount: sparkle),
        intensity: 0.12 + sparkle * 0.88
      )
    case .falling:
      let seed = deterministicNoise(ordinal * 37 + 11)
      let particleY = positiveRemainder(phase * (0.28 + seed * 0.16) + seed, modulus: 1.25) - 0.12
      let vertical = gaussian(y - particleY, width: 0.075)
      let column = 0.18 + 0.82 * pow(max(0, cos((x * 7 + seed) * .pi)), 8)
      let energy = min(1, vertical * column)
      return .init(
        color: .mix(baseColor, accentColor, amount: energy),
        intensity: 0.08 + energy * 0.92
      )
    case .colourful:
      let hue = positiveRemainder(phase * 0.18 + x * 0.72 + y * 0.22, modulus: 1)
      return .init(color: .spectrum(hue: hue), intensity: 0.96)
    case .breath:
      let breath = 0.5 + 0.5 * sin(phase * .pi * 2 - .pi / 2)
      return .init(color: baseColor, intensity: 0.08 + breath * 0.92)
    case .spectrum:
      return .init(color: .spectrum(hue: phase * 0.19), intensity: 0.95)
    case .outward:
      let ring = repeatingBand(distance - phase * 0.32, period: 0.46, width: 0.075)
      return .init(
        color: .mix(baseColor, accentColor, amount: ring),
        intensity: 0.08 + ring * 0.92
      )
    case .scrolling:
      let band = repeatingBand(y - phase * 0.35, period: 0.58, width: 0.13)
      return .init(
        color: .mix(baseColor, accentColor, amount: band),
        intensity: 0.1 + band * 0.9
      )
    case .rolling:
      let wave = 0.5 + 0.5 * sin((x * 2.7 - phase * 0.72) * .pi * 2)
      return .init(
        color: .mix(baseColor, accentColor, amount: wave),
        intensity: 0.14 + wave * 0.86
      )
    case .rotating:
      let angle = atan2(dy, dx)
      let ribbon = pow(0.5 + 0.5 * cos(angle - phase * 1.9), 5)
      return .init(
        color: .mix(baseColor, accentColor, amount: ribbon),
        intensity: 0.09 + ribbon * 0.91
      )
    case .flowing:
      let count = max(1, keyCount)
      let head = positiveRemainder(phase * Double(count) * 0.38, modulus: Double(count))
      let trail = positiveRemainder(head - Double(ordinal), modulus: Double(count))
      let energy = exp(-trail / max(4, Double(count) * 0.13))
      return .init(
        color: .mix(baseColor, accentColor, amount: energy),
        intensity: 0.06 + energy * 0.94
      )
    case .pulsating:
      let mountain = 0.54 - 0.32 * abs(sin((x - phase * 0.16) * .pi * 2))
      let ridge = gaussian(y - mountain, width: 0.105)
      return .init(
        color: .mix(baseColor, accentColor, amount: ridge),
        intensity: 0.1 + ridge * 0.9
      )
    case .tilt:
      let diagonal = repeatingBand(x + y * 1.8 - phase * 0.5, period: 0.48, width: 0.075)
      return .init(
        color: .mix(baseColor, accentColor, amount: diagonal),
        intensity: 0.06 + diagonal * 0.94
      )
    case .shuttle:
      let travel = triangleWave(phase * 0.34)
      let beam = gaussian(x - travel, width: 0.075)
      return .init(
        color: .mix(baseColor, accentColor, amount: beam),
        intensity: 0.08 + beam * 0.92
      )
    case .singleOn, .singleOff, .explode, .launch, .ripples:
      return .off
    }
  }

  private static func reactiveSample(
    effect: AK47OnboardLightingEffect,
    key: AK47PhysicalKey,
    time: TimeInterval,
    speed: Double,
    baseColor: AK47LightingPreviewRGB,
    accentColor: AK47LightingPreviewRGB,
    presses: [AK47LightingPreviewPress]
  ) -> AK47LightingPreviewSample {
    var energy = 0.0
    var accent = 0.0
    for press in presses {
      let age = time - press.timestamp
      guard age >= 0 else { continue }
      let dx = (key.center.x - press.origin.x) / AK47PhysicalLayout.canvasSize.height
      let dy = (key.center.y - press.origin.y) / AK47PhysicalLayout.canvasSize.height
      let distance = hypot(dx, dy)
      let decay = exp(-age * (0.9 + speed * 0.09))
      let contribution: Double

      switch effect {
      case .singleOn:
        let point = gaussian(distance, width: 0.055 + age * 0.035)
        let trail = gaussian(distance - age * 0.17, width: 0.055)
        contribution = max(point * decay, trail * decay * 0.52)
      case .singleOff:
        contribution = gaussian(distance, width: 0.06 + age * 0.025) * decay
      case .explode:
        let travel = age * (0.33 + speed * 0.025)
        let horizontal = gaussian(abs(dx) - travel, width: 0.075)
        let row = gaussian(dy, width: 0.07 + age * 0.015)
        contribution = horizontal * row * decay
      case .launch:
        let travel = age * (0.3 + speed * 0.025)
        let outward = gaussian(abs(dx) - travel, width: 0.12)
        let branch = gaussian(abs(dy) - abs(dx) * 0.2, width: 0.1)
        let surroundingWave = gaussian(distance - travel, width: 0.1) * 0.58
        contribution = max(outward * branch, surroundingWave) * decay
      case .ripples:
        let travel = age * (0.3 + speed * 0.025)
        contribution = gaussian(distance - travel, width: 0.065) * decay
      default:
        contribution = 0
      }
      energy = max(energy, contribution)
      accent = max(accent, contribution * (0.75 + 0.25 * decay))
    }

    if effect == .singleOff {
      return .init(
        color: .mix(baseColor, accentColor, amount: 0.18 + accent * 0.52),
        intensity: 1 - min(0.94, energy)
      )
    }
    return .init(
      color: .mix(baseColor, accentColor, amount: min(1, 0.25 + accent * 0.75)),
      intensity: min(1, energy)
    )
  }

  private static func reactiveDuration(for effect: AK47OnboardLightingEffect) -> TimeInterval {
    switch effect {
    case .singleOn, .singleOff: 1.35
    case .explode, .launch: 1.7
    case .ripples: 1.9
    default: 0
    }
  }

  private static func deterministicNoise(_ seed: Int) -> Double {
    positiveRemainder(sin(Double(seed) * 12.9898) * 43_758.5453, modulus: 1)
  }

  private static func gaussian(_ distance: Double, width: Double) -> Double {
    exp(-pow(distance / max(0.000_1, width), 2))
  }

  private static func repeatingBand(_ value: Double, period: Double, width: Double) -> Double {
    let wrapped = positiveRemainder(value + period / 2, modulus: period) - period / 2
    return gaussian(wrapped, width: width)
  }

  private static func triangleWave(_ value: Double) -> Double {
    let phase = positiveRemainder(value, modulus: 2)
    return phase <= 1 ? phase : 2 - phase
  }
}

private func positiveRemainder(_ value: Double, modulus: Double) -> Double {
  let remainder = value.truncatingRemainder(dividingBy: modulus)
  return remainder >= 0 ? remainder : remainder + modulus
}
