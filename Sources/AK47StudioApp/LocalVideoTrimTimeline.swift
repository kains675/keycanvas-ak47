import AK47InspectorCore
import Foundation
import SwiftUI

enum LocalVideoTrimFocus: String, CaseIterable, Hashable, Sendable {
  case startHandle
  case playhead
  case endHandle
}

enum LocalVideoTrimStepDirection: Equatable, Sendable {
  case backward
  case forward
}

/// Millisecond-resolution state for the local preview trimmer. Keyboard steps
/// use the exact rational KeyCanvas output-sample grid
/// `floor(index * 1000 / fps)`, never repeated rounded additions. VFR source
/// presentation times are resolved later by the bounded extractor.
struct LocalVideoTrimTimelineState: Equatable, Sendable {
  let durationMilliseconds: Int
  private(set) var startMilliseconds: Int
  private(set) var endMilliseconds: Int
  private(set) var playheadMilliseconds: Int

  init(
    durationMilliseconds: Int,
    startMilliseconds: Int,
    endMilliseconds: Int,
    playheadMilliseconds: Int? = nil
  ) {
    let duration = max(1, durationMilliseconds)
    self.durationMilliseconds = duration
    let boundedStart = min(max(0, startMilliseconds), duration - 1)
    let boundedEnd = min(duration, max(boundedStart + 1, endMilliseconds))
    self.startMilliseconds = boundedStart
    self.endMilliseconds = boundedEnd
    self.playheadMilliseconds = min(
      boundedEnd,
      max(boundedStart, playheadMilliseconds ?? boundedStart)
    )
  }

  var selectionDurationMilliseconds: Int {
    endMilliseconds - startMilliseconds
  }

  mutating func setStartMilliseconds(_ value: Int) {
    startMilliseconds = min(max(0, value), endMilliseconds - 1)
    playheadMilliseconds = max(playheadMilliseconds, startMilliseconds)
  }

  mutating func setEndMilliseconds(_ value: Int) {
    endMilliseconds = min(durationMilliseconds, max(startMilliseconds + 1, value))
    playheadMilliseconds = min(playheadMilliseconds, endMilliseconds)
  }

  mutating func setPlayheadMilliseconds(_ value: Int) {
    playheadMilliseconds = min(endMilliseconds, max(startMilliseconds, value))
  }

  mutating func step(
    focus: LocalVideoTrimFocus,
    direction: LocalVideoTrimStepDirection,
    samplingFramesPerSecond: Int,
    multiplier: Int = 1
  ) {
    switch focus {
    case .startHandle:
      setStartMilliseconds(
        sampleGridStep(
          from: startMilliseconds,
          anchor: 0,
          direction: direction,
          framesPerSecond: samplingFramesPerSecond,
          multiplier: multiplier
        )
      )
      setPlayheadMilliseconds(startMilliseconds)
    case .playhead:
      setPlayheadMilliseconds(
        sampleGridStep(
          from: playheadMilliseconds,
          anchor: startMilliseconds,
          direction: direction,
          framesPerSecond: samplingFramesPerSecond,
          multiplier: multiplier
        )
      )
    case .endHandle:
      setEndMilliseconds(
        sampleGridStep(
          from: endMilliseconds,
          anchor: startMilliseconds,
          direction: direction,
          framesPerSecond: samplingFramesPerSecond,
          multiplier: multiplier
        )
      )
      setPlayheadMilliseconds(endMilliseconds)
    }
  }

  mutating func snapPlayheadToOutputGrid(framesPerSecond: Int) {
    let fps = Int64(
      min(
        AK47LCDVideoSelection.maximumFramesPerSecond,
        max(AK47LCDVideoSelection.minimumFramesPerSecond, framesPerSecond)
      )
    )
    let offset = Int64(max(0, playheadMilliseconds - startMilliseconds))
    let nearestIndex = ((offset * fps) + 500) / 1_000
    let candidate = Int64(startMilliseconds) + ((nearestIndex * 1_000) / fps)
    setPlayheadMilliseconds(Int(min(Int64(durationMilliseconds), candidate)))
  }

  static func timecode(milliseconds: Int) -> String {
    let value = max(0, milliseconds)
    let hours = value / 3_600_000
    let minutes = (value / 60_000) % 60
    let seconds = (value / 1_000) % 60
    let remainder = value % 1_000
    return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, remainder)
  }

  private func sampleGridStep(
    from value: Int,
    anchor: Int,
    direction: LocalVideoTrimStepDirection,
    framesPerSecond: Int,
    multiplier: Int
  ) -> Int {
    let fps = Int64(
      min(
        AK47LCDVideoSelection.maximumFramesPerSecond,
        max(AK47LCDVideoSelection.minimumFramesPerSecond, framesPerSecond)
      )
    )
    let safeMultiplier = Int64(
      min(max(1, multiplier), durationMilliseconds + 1)
    )
    let offset = Int64(max(0, value - anchor))
    let scaledOffset = offset * fps
    let index: Int64
    switch direction {
    case .forward:
      let firstFollowingIndex = (((offset + 1) * fps) + 999) / 1_000
      index = firstFollowingIndex + (safeMultiplier - 1)
    case .backward:
      let ceilingIndex = (scaledOffset + 999) / 1_000
      index = max(0, ceilingIndex - safeMultiplier)
    }
    let candidate = Int64(anchor) + ((index * 1_000) / fps)
    return min(durationMilliseconds, max(0, Int(candidate)))
  }
}

enum LocalVideoTimelineGeometry {
  static func x(
    milliseconds: Int,
    width: Double,
    durationMilliseconds: Int,
    horizontalInset: Double
  ) -> Double {
    guard width.isFinite, horizontalInset.isFinite,
      width > horizontalInset * 2,
      horizontalInset >= 0,
      durationMilliseconds > 0
    else { return max(0, horizontalInset.isFinite ? horizontalInset : 0) }
    let usableWidth = width - (horizontalInset * 2)
    let boundedMilliseconds = min(durationMilliseconds, max(0, milliseconds))
    let fraction = Double(boundedMilliseconds) / Double(durationMilliseconds)
    let result = horizontalInset + (usableWidth * fraction)
    return result.isFinite ? result : horizontalInset
  }

  static func milliseconds(
    x: Double,
    width: Double,
    durationMilliseconds: Int,
    horizontalInset: Double
  ) -> Int {
    guard x.isFinite, width.isFinite, horizontalInset.isFinite,
      horizontalInset >= 0,
      width > horizontalInset * 2,
      durationMilliseconds > 0
    else { return 0 }
    let usableWidth = width - (horizontalInset * 2)
    let boundedX = min(width - horizontalInset, max(horizontalInset, x))
    let fraction = (boundedX - horizontalInset) / usableWidth
    let scaled = fraction * Double(durationMilliseconds)
    guard scaled.isFinite, scaled >= 0,
      scaled <= Double(durationMilliseconds)
    else { return 0 }
    return Int(scaled.rounded())
  }
}

struct LocalVideoRangeTimeline: View {
  private static let coordinateSpaceName = "LocalVideoRangeTimeline"

  let durationMilliseconds: Int
  let startMilliseconds: Int
  let endMilliseconds: Int
  let playheadMilliseconds: Int
  let isEnabled: Bool
  let language: AppLanguage
  let onStartChange: (Int) -> Void
  let onEndChange: (Int) -> Void
  let onPlayheadChange: (Int) -> Void
  let onStep: (LocalVideoTrimFocus, LocalVideoTrimStepDirection, Int) -> Void

  @StateObject private var keyboardRoute = LocalVideoTrimKeyboardRoute()

  var body: some View {
    GeometryReader { geometry in
      let metrics = Metrics(width: geometry.size.width, duration: durationMilliseconds)
      ZStack(alignment: .topLeading) {
        LocalVideoTrimKeyResponder(
          route: keyboardRoute,
          isEnabled: isEnabled,
          onStep: onStep
        )
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)

        Capsule()
          .fill(Color.secondary.opacity(0.22))
          .frame(height: 8)
          .position(x: geometry.size.width / 2, y: Metrics.trackY)

        Capsule()
          .fill(StudioPalette.blue.opacity(0.55))
          .frame(
            width: max(
              1,
              metrics.x(for: endMilliseconds) - metrics.x(for: startMilliseconds)
            ),
            height: 10
          )
          .position(
            x: (metrics.x(for: startMilliseconds) + metrics.x(for: endMilliseconds)) / 2,
            y: Metrics.trackY
          )

        Rectangle()
          .fill(StudioPalette.mint)
          .frame(width: 2, height: 30)
          .position(x: metrics.x(for: playheadMilliseconds), y: Metrics.trackY)

        markerButton(
          focus: .startHandle,
          color: StudioPalette.blue,
          systemImage: "chevron.right",
          value: startMilliseconds,
          metrics: metrics,
          onChange: onStartChange
        )
        .zIndex(keyboardRoute.activeControl == .startHandle ? 3 : 1)

        markerButton(
          focus: .endHandle,
          color: StudioPalette.coral,
          systemImage: "chevron.left",
          value: endMilliseconds,
          metrics: metrics,
          onChange: onEndChange
        )
        .zIndex(keyboardRoute.activeControl == .endHandle ? 3 : 1)

        markerButton(
          focus: .playhead,
          color: StudioPalette.mint,
          systemImage: "play.fill",
          value: playheadMilliseconds,
          metrics: metrics,
          onChange: onPlayheadChange
        )
        .offset(y: -24)
        .zIndex(keyboardRoute.activeControl == .playhead ? 4 : 2)
      }
      .coordinateSpace(name: Self.coordinateSpaceName)
    }
    .frame(height: 72)
    .disabled(!isEnabled)
    .onChange(of: isEnabled) { enabled in
      if !enabled {
        keyboardRoute.deactivate()
      }
    }
    .onDisappear {
      keyboardRoute.deactivate()
    }
  }

  private func markerButton(
    focus: LocalVideoTrimFocus,
    color: Color,
    systemImage: String,
    value: Int,
    metrics: Metrics,
    onChange: @escaping (Int) -> Void
  ) -> some View {
    Button {
      keyboardRoute.activate(focus)
      onChange(value)
    } label: {
      Circle()
        .fill(color)
        .frame(
          width: focus == .playhead ? Metrics.playheadMarkerSize : Metrics.markerSize,
          height: focus == .playhead ? Metrics.playheadMarkerSize : Metrics.markerSize
        )
        .overlay {
          Image(systemName: systemImage)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(Color.black.opacity(0.75))
        }
        .overlay {
          Circle()
            .strokeBorder(
              keyboardRoute.activeControl == focus ? Color.white : Color.clear,
              lineWidth: 2
            )
        }
        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
        .frame(width: Metrics.hitTargetSize, height: Metrics.hitTargetSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .position(x: metrics.x(for: value), y: Metrics.trackY)
    .simultaneousGesture(
      DragGesture(
        minimumDistance: 0,
        coordinateSpace: .named(Self.coordinateSpaceName)
      )
      .onChanged { gesture in
        keyboardRoute.activate(focus)
        onChange(metrics.milliseconds(for: gesture.location.x))
      }
    )
    .onMoveCommand { direction in
      switch direction {
      case .left:
        keyboardRoute.activate(focus)
        onStep(focus, .backward, 1)
      case .right:
        keyboardRoute.activate(focus)
        onStep(focus, .forward, 1)
      default:
        break
      }
    }
    .accessibilityLabel(accessibilityLabel(for: focus))
    .accessibilityValue(LocalVideoTrimTimelineState.timecode(milliseconds: value))
    .accessibilityHint(
      studioText(
        "초점을 둔 뒤 왼쪽·오른쪽 화살표로 출력 샘플 한 칸 이동",
        "Focus, then use Left or Right Arrow for one output-sample step",
        language: language
      )
    )
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        keyboardRoute.activate(focus)
        onStep(focus, .forward, 1)
      case .decrement:
        keyboardRoute.activate(focus)
        onStep(focus, .backward, 1)
      @unknown default:
        break
      }
    }
  }

  private func accessibilityLabel(for focus: LocalVideoTrimFocus) -> String {
    switch focus {
    case .startHandle:
      studioText("영상 시작 핸들", "Video start handle", language: language)
    case .playhead:
      studioText("영상 재생 헤드", "Video playhead", language: language)
    case .endHandle:
      studioText("영상 끝 핸들", "Video end handle", language: language)
    }
  }

  private struct Metrics {
    static let horizontalInset = 22.0
    static let markerSize = 24.0
    static let playheadMarkerSize = 19.0
    static let hitTargetSize = 44.0
    static let trackY = 43.0

    let width: Double
    let duration: Int

    func x(for milliseconds: Int) -> Double {
      LocalVideoTimelineGeometry.x(
        milliseconds: milliseconds,
        width: width,
        durationMilliseconds: duration,
        horizontalInset: Self.horizontalInset
      )
    }

    func milliseconds(for x: Double) -> Int {
      LocalVideoTimelineGeometry.milliseconds(
        x: x,
        width: width,
        durationMilliseconds: duration,
        horizontalInset: Self.horizontalInset
      )
    }
  }
}
