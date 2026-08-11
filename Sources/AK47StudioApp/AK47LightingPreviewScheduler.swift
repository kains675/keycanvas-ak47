import Combine
import Foundation

/// Converts monotonic host elapsed time into project-calibrated logical ticks. The value is a
/// presentation choice because the firmware tick's wall-clock duration is not established.
struct AK47LightingPreviewScheduler: Sendable {
  static let presentationLogicalTicksPerSecond: UInt64 = 1_000
  static let presentationIntervalNanoseconds: UInt64 = 1_000_000_000 / 30
  static let demoIntervalTicks: UInt64 = 900
  static let maximumContinuousElapsedNanoseconds: UInt64 = 2_000_000_000

  private static let demoKeyIndices: [AK47LightingPreviewKeyIndex] = [
    "Space", "A", "Return", "J", "Esc", "Up",
  ].compactMap { keyID in
    AK47PhysicalLayout.keys.firstIndex { $0.id == keyID }
      .flatMap(AK47LightingPreviewKeyIndex.init(rawValue:))
  }

  private(set) var engine: AK47LightingPreviewEngine
  private(set) var isPaused = false
  var includesDeterministicDemoInput = false

  private var lastMonotonicNanoseconds: UInt64?
  private var scaledNanosecondRemainder: UInt64 = 0
  private var nextSequence: UInt64 = 0
  private var nextDemoTick: UInt64 = 0
  private var demoIndex = 0

  init(configuration: AK47LightingPreviewConfiguration) {
    engine = AK47LightingPreviewEngine(configuration: configuration)
  }

  var frame: AK47LightingPreviewFrame { engine.frame() }
  var logicalTick: UInt64 { engine.logicalTick }

  mutating func reconfigure(_ configuration: AK47LightingPreviewConfiguration) {
    let restartsDemo =
      engine.configuration.effect != configuration.effect
      || engine.configuration.isEnabled != configuration.isEnabled
    engine.reconfigure(configuration)
    if restartsDemo {
      nextDemoTick = 0
      demoIndex = 0
      nextSequence = 0
      scaledNanosecondRemainder = 0
      lastMonotonicNanoseconds = nil
    }
  }

  mutating func restart() {
    engine.restart()
    lastMonotonicNanoseconds = nil
    scaledNanosecondRemainder = 0
    nextSequence = 0
    nextDemoTick = 0
    demoIndex = 0
  }

  mutating func setPaused(_ paused: Bool) {
    guard paused != isPaused else { return }
    isPaused = paused
    lastMonotonicNanoseconds = nil
  }

  mutating func advance(monotonicNanoseconds now: UInt64) {
    guard !isPaused else {
      lastMonotonicNanoseconds = nil
      return
    }
    guard let previous = lastMonotonicNanoseconds else {
      lastMonotonicNanoseconds = now
      enqueueDueDemoInput(through: engine.logicalTick)
      engine.advance(to: engine.logicalTick)
      return
    }
    lastMonotonicNanoseconds = now
    guard now >= previous else { return }
    advance(elapsedNanoseconds: now - previous)
  }

  mutating func advance(elapsedNanoseconds: UInt64) {
    guard !isPaused else { return }
    guard elapsedNanoseconds <= Self.maximumContinuousElapsedNanoseconds else {
      // Treat sleep, debugger stops, and long UI stalls as a paused interval. This bounds work,
      // prevents multiplication overflow, and avoids presenting a large state jump on resume.
      scaledNanosecondRemainder = 0
      return
    }
    let scaled =
      elapsedNanoseconds * Self.presentationLogicalTicksPerSecond
      + scaledNanosecondRemainder
    let dueTicks = scaled / 1_000_000_000
    scaledNanosecondRemainder = scaled % 1_000_000_000
    guard dueTicks > 0 else { return }
    let target = engine.logicalTick &+ dueTicks
    enqueueDueDemoInput(through: target)
    engine.advance(to: target)
  }

  mutating func enqueue(_ kind: AK47LightingPreviewKeyEventKind, key: AK47LightingPreviewKeyIndex) {
    engine.enqueue(
      AK47LightingPreviewKeyEvent(
        logicalTick: engine.logicalTick,
        sequence: takeSequence(),
        key: key,
        kind: kind
      )
    )
  }

  mutating func enqueueTap(key: AK47LightingPreviewKeyIndex) {
    let tick = engine.logicalTick
    engine.enqueue(
      AK47LightingPreviewKeyEvent(
        logicalTick: tick,
        sequence: takeSequence(),
        key: key,
        kind: .down
      )
    )
    engine.enqueue(
      AK47LightingPreviewKeyEvent(
        logicalTick: tick &+ 1,
        sequence: takeSequence(),
        key: key,
        kind: .up
      )
    )
  }

  private mutating func enqueueDueDemoInput(through targetTick: UInt64) {
    guard includesDeterministicDemoInput, engine.configuration.effect.isReactive,
      !Self.demoKeyIndices.isEmpty
    else { return }
    while nextDemoTick <= targetTick {
      let key = Self.demoKeyIndices[demoIndex % Self.demoKeyIndices.count]
      engine.enqueue(
        AK47LightingPreviewKeyEvent(
          logicalTick: nextDemoTick,
          sequence: takeSequence(),
          key: key,
          kind: .down
        )
      )
      engine.enqueue(
        AK47LightingPreviewKeyEvent(
          logicalTick: nextDemoTick &+ 1,
          sequence: takeSequence(),
          key: key,
          kind: .up
        )
      )
      demoIndex += 1
      nextDemoTick &+= Self.demoIntervalTicks
    }
  }

  private mutating func takeSequence() -> UInt64 {
    defer { nextSequence &+= 1 }
    return nextSequence
  }
}

@MainActor
final class AK47LightingPreviewSession: ObservableObject {
  @Published private(set) var frame = AK47LightingPreviewFrame.off
  private(set) var isAnimationRunning = false

  private var scheduler = AK47LightingPreviewScheduler(
    configuration: AK47LightingPreviewConfiguration(
      effect: .staticMode,
      isEnabled: false,
      speedLevel: 3,
      brightnessLevel: 4,
      baseColor: AK47LightingPreviewRGB(redByte: 0, greenByte: 0, blueByte: 0)
    )
  )
  private var animationTask: Task<Void, Never>?

  func configure(
    _ configuration: AK47LightingPreviewConfiguration,
    restart: Bool = false,
    includesDeterministicDemoInput: Bool
  ) {
    scheduler.reconfigure(configuration)
    scheduler.includesDeterministicDemoInput = includesDeterministicDemoInput
    if restart { scheduler.restart() }
    if !configuration.isEnabled {
      setPaused(true)
      return
    }
    publishFrame()
  }

  func setPaused(_ paused: Bool) {
    scheduler.setPaused(paused)
    if paused {
      stop()
    } else {
      start()
    }
    publishFrame()
  }

  func start() {
    guard animationTask == nil, !scheduler.isPaused else { return }
    pulse()
    isAnimationRunning = true
    animationTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(
            nanoseconds: AK47LightingPreviewScheduler.presentationIntervalNanoseconds
          )
        } catch {
          return
        }
        guard let self else { return }
        self.pulse()
      }
    }
  }

  func stop() {
    animationTask?.cancel()
    animationTask = nil
    isAnimationRunning = false
  }

  func restart() {
    scheduler.restart()
    publishFrame()
  }

  func enqueueTap(key: AK47LightingPreviewKeyIndex) {
    scheduler.advance(monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    scheduler.enqueueTap(key: key)
    publishFrame()
  }

  private func pulse() {
    scheduler.advance(monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    publishFrame()
  }

  private func publishFrame() {
    frame = scheduler.frame
  }
}
