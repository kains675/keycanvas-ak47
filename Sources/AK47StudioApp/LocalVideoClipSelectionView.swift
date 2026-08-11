import AK47InspectorCore
@preconcurrency import AVFoundation
import AppKit
import SwiftUI

struct LocalVideoClipSelectionInput: Identifiable, Equatable {
  let id = UUID()
  let descriptor: LocalVideoImportDescriptor

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }
}

struct LocalVideoClipSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.studioLanguage) private var language
  @StateObject private var model: LocalVideoClipSelectionModel
  let onComplete: (LocalVideoImportResult) -> Void

  init(
    input: LocalVideoClipSelectionInput,
    onComplete: @escaping (LocalVideoImportResult) -> Void
  ) {
    _model = StateObject(
      wrappedValue: LocalVideoClipSelectionModel(descriptor: input.descriptor)
    )
    self.onComplete = onComplete
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("영상 구간 선택", "Choose video range", language: language))
            .font(.title3.bold())
          Text(model.descriptor.sourceURL.lastPathComponent)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
        Label(
          "\(model.descriptor.metadata.width)×\(model.descriptor.metadata.height)",
          systemImage: "rectangle.inset.filled"
        )
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
      }

      videoPreview

      VStack(alignment: .leading, spacing: 14) {
        LocalVideoRangeTimeline(
          durationMilliseconds: model.durationMilliseconds,
          startMilliseconds: model.startMilliseconds,
          endMilliseconds: model.endMilliseconds,
          playheadMilliseconds: model.playheadMilliseconds,
          isEnabled: !model.isExtracting,
          language: language,
          onStartChange: model.setStartMilliseconds,
          onEndChange: model.setEndMilliseconds,
          onPlayheadChange: model.setPlayheadMilliseconds,
          onStep: model.stepTimeline
        )

        HStack(alignment: .top) {
          timecodeLabel(
            studioText("시작", "Start", language: language),
            milliseconds: model.startMilliseconds,
            alignment: .leading
          )
          Spacer()
          timecodeLabel(
            studioText("재생 헤드", "Playhead", language: language),
            milliseconds: model.playheadMilliseconds,
            alignment: .center
          )
          Spacer()
          timecodeLabel(
            studioText("끝", "End", language: language),
            milliseconds: model.endMilliseconds,
            alignment: .trailing
          )
        }

        HStack {
          Text(studioText("초당 프레임", "Frames per second", language: language))
          Spacer()
          Stepper(
            "\(model.framesPerSecond) FPS",
            value: $model.framesPerSecond,
            in: AK47LCDVideoSelection
              .minimumFramesPerSecond...AK47LCDVideoSelection
              .maximumFramesPerSecond
          )
          .monospacedDigit()
          .fixedSize()
        }

        Label(
          studioText(
            "핸들 또는 재생 헤드에 초점을 두고 ←/→를 누르면 선택한 FPS의 출력 샘플 한 칸을 이동합니다. 가변 프레임률 영상의 실제 시각은 변환 때 가장 가까운 프레임으로 결정됩니다.",
            "Focus a handle or the playhead and press Left/Right Arrow to move one output-sample step at the selected FPS. For variable-frame-rate video, conversion resolves the nearest actual source frame.",
            language: language
          ),
          systemImage: "keyboard"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .disabled(model.isExtracting)

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          if let plan = model.plan {
            summaryRow(
              studioText("예상 프레임", "Expected frames", language: language),
              "\(plan.expectedFrameCount) / \(AK47LCDFormat.maximumFrameCount)"
            )
            summaryRow(
              studioText("편집 소스 크기", "Editor source size", language: language),
              "≤ \(plan.maximumExtractionWidth)×\(plan.maximumExtractionHeight)"
            )
            summaryRow(
              studioText("디코드 작업량", "Decoded work", language: language),
              ByteCountFormatter.string(
                fromByteCount: Int64(plan.estimatedDecodedPixelCount * 4),
                countStyle: .memory
              )
            )
          } else if let planningError = model.planningError {
            Label(planningError, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(StudioPalette.coral)
          }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(studioText("변환 미리 계산", "Conversion preflight", language: language))
      }

      if model.isExtracting {
        VStack(alignment: .leading, spacing: 7) {
          ProgressView(value: model.progressFraction)
          Text(
            studioText(
              "프레임 \(model.completedFrameCount) / \(model.totalFrameCount) 변환 중…",
              "Converting frame \(model.completedFrameCount) / \(model.totalFrameCount)…",
              language: language
            )
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
      }

      if let errorMessage = model.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      }

      Label(
        studioText(
          "가장 가까운 영상 프레임을 선택 간격의 절반 안에서 사용합니다. 원본 영상은 바꾸거나 보관함에 복사하지 않으며, 편집 결과는 GIF로 내보내야 보존됩니다.",
          "The nearest source frame within half a sample interval is used. The original video is neither changed nor copied into the library; export an edited GIF to preserve the result.",
          language: language
        ),
        systemImage: "lock.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Button(studioText("취소", "Cancel", language: language), role: .cancel) {
          model.cancel()
          dismiss()
        }
        Spacer()
        Button {
          model.extract { result in
            onComplete(result)
          }
        } label: {
          Label(
            studioText("편집기에서 열기", "Open in editor", language: language),
            systemImage: "slider.horizontal.3"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
        .disabled(model.plan == nil || model.isExtracting)
      }
    }
    .padding(22)
    .frame(width: 680)
    .interactiveDismissDisabled(model.isExtracting)
    .onChange(of: scenePhase) { phase in
      guard phase != .active else { return }
      model.pausePreviewForInactivity()
    }
    .onDisappear { model.cancel() }
  }

  private var videoPreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.black)
        if let player = model.previewPlayer {
          LocalVideoPlayerSurface(player: player)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
          Image(systemName: "film.stack")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(.secondary)
        }
      }
      .frame(height: 260)
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.white.opacity(0.14))
      }
      .accessibilityLabel(
        studioText("로컬 영상 미리보기", "Local video preview", language: language)
      )

      HStack(spacing: 12) {
        Button(action: model.togglePreviewPlayback) {
          Label(
            model.isPlaying
              ? studioText("일시 정지", "Pause", language: language)
              : studioText("재생", "Play", language: language),
            systemImage: model.isPlaying ? "pause.fill" : "play.fill"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(model.previewPlayer == nil || model.isExtracting)

        Text(LocalVideoTrimTimelineState.timecode(milliseconds: model.playheadMilliseconds))
          .font(.callout.monospacedDigit().weight(.semibold))
        Text("/")
          .foregroundStyle(.tertiary)
        Text(LocalVideoTrimTimelineState.timecode(milliseconds: model.durationMilliseconds))
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        Label(
          studioText("오디오 음소거", "Audio muted", language: language),
          systemImage: "speaker.slash.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let previewErrorMessage = model.previewErrorMessage {
        Label(previewErrorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(StudioPalette.coral)
      }
    }
  }

  private func timecodeLabel(
    _ title: String,
    milliseconds: Int,
    alignment: HorizontalAlignment
  ) -> some View {
    VStack(alignment: alignment, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(LocalVideoTrimTimelineState.timecode(milliseconds: milliseconds))
        .font(.caption.monospacedDigit().weight(.semibold))
    }
  }

  private func summaryRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
    }
  }

}

@MainActor
final class LocalVideoClipSelectionModel: ObservableObject {
  let descriptor: LocalVideoImportDescriptor
  let previewPlayer: AVPlayer?
  @Published private(set) var previewErrorMessage: String?
  @Published private(set) var timeline: LocalVideoTrimTimelineState
  @Published var framesPerSecond: Int {
    didSet {
      guard framesPerSecond != oldValue else { return }
      stopPreviewPlayback(syncCurrentTime: false)
      var updated = timeline
      updated.snapPlayheadToOutputGrid(framesPerSecond: framesPerSecond)
      timeline = updated
      seekPreview(to: updated.playheadMilliseconds)
      errorMessage = nil
    }
  }
  @Published private(set) var isPlaying = false
  @Published private(set) var isExtracting = false
  @Published private(set) var completedFrameCount = 0
  @Published private(set) var totalFrameCount = 0
  @Published private(set) var errorMessage: String?
  private var extractionTask: Task<Void, Never>?
  private var extractionGeneration: UUID?
  private var previewTickTask: Task<Void, Never>?
  private var playbackController: LocalVideoPreviewPlaybackController?

  init(descriptor: LocalVideoImportDescriptor) {
    self.descriptor = descriptor
    let recommended = try? AK47LCDVideoSelection.recommended(for: descriptor.metadata)
    framesPerSecond =
      recommended?.framesPerSecond
      ?? AK47LCDVideoSelection.recommendedFramesPerSecond
    timeline = LocalVideoTrimTimelineState(
      durationMilliseconds: descriptor.metadata.durationMilliseconds,
      startMilliseconds: recommended?.startMilliseconds ?? 0,
      endMilliseconds: recommended?.endMilliseconds ?? descriptor.metadata.durationMilliseconds
    )
    do {
      let player = try LocalVideoImportService.makePreviewPlayer(descriptor: descriptor)
      previewPlayer = player
      previewErrorMessage = nil
      let controller = LocalVideoPreviewPlaybackController(
        backend: LocalVideoAVPlayerBackend(player: player)
      )
      playbackController = controller
      controller.onBoundaryReached = { [weak self] in
        self?.handlePreviewBoundaryReached()
      }
      controller.updateBoundary(endMilliseconds: timeline.endMilliseconds)
      controller.seek(
        toMilliseconds: timeline.startMilliseconds,
        toleranceMilliseconds: 0,
        playWhenReady: false
      )
    } catch {
      previewPlayer = nil
      previewErrorMessage = error.localizedDescription
    }
  }

  var durationMilliseconds: Int { descriptor.metadata.durationMilliseconds }
  var startMilliseconds: Int { timeline.startMilliseconds }
  var endMilliseconds: Int { timeline.endMilliseconds }
  var playheadMilliseconds: Int { timeline.playheadMilliseconds }

  var selection: AK47LCDVideoSelection? {
    try? AK47LCDVideoSelection(
      startMilliseconds: startMilliseconds,
      endMilliseconds: endMilliseconds,
      framesPerSecond: framesPerSecond
    )
  }

  var plan: AK47LCDVideoImportPlan? {
    guard let selection else { return nil }
    return try? AK47LCDVideoImportPlan(metadata: descriptor.metadata, selection: selection)
  }

  var planningError: String? {
    do {
      let selection = try AK47LCDVideoSelection(
        startMilliseconds: startMilliseconds,
        endMilliseconds: endMilliseconds,
        framesPerSecond: framesPerSecond
      )
      _ = try AK47LCDVideoImportPlan(metadata: descriptor.metadata, selection: selection)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  var progressFraction: Double {
    guard totalFrameCount > 0 else { return 0 }
    return Double(completedFrameCount) / Double(totalFrameCount)
  }

  func setStartMilliseconds(_ value: Int) {
    stopPreviewPlayback(syncCurrentTime: false)
    var updated = timeline
    updated.setStartMilliseconds(value)
    updated.setPlayheadMilliseconds(updated.startMilliseconds)
    timeline = updated
    seekPreview(to: updated.playheadMilliseconds)
    errorMessage = nil
  }

  func setEndMilliseconds(_ value: Int) {
    stopPreviewPlayback(syncCurrentTime: false)
    var updated = timeline
    updated.setEndMilliseconds(value)
    updated.setPlayheadMilliseconds(updated.endMilliseconds)
    timeline = updated
    playbackController?.updateBoundary(endMilliseconds: updated.endMilliseconds)
    seekPreview(to: updated.playheadMilliseconds)
    errorMessage = nil
  }

  func setPlayheadMilliseconds(_ value: Int) {
    stopPreviewPlayback(syncCurrentTime: false)
    var updated = timeline
    updated.setPlayheadMilliseconds(value)
    timeline = updated
    seekPreview(to: updated.playheadMilliseconds)
  }

  func stepTimeline(
    focus: LocalVideoTrimFocus,
    direction: LocalVideoTrimStepDirection,
    multiplier: Int
  ) {
    stopPreviewPlayback(syncCurrentTime: false)
    var updated = timeline
    updated.step(
      focus: focus,
      direction: direction,
      samplingFramesPerSecond: framesPerSecond,
      multiplier: multiplier
    )
    timeline = updated
    if focus == .endHandle {
      playbackController?.updateBoundary(endMilliseconds: updated.endMilliseconds)
    }
    seekPreview(to: updated.playheadMilliseconds)
    errorMessage = nil
  }

  func togglePreviewPlayback() {
    guard let previewPlayer, let playbackController, !isExtracting else { return }
    if previewPlayer.currentItem?.status == .failed {
      previewErrorMessage =
        previewPlayer.currentItem?.error?.localizedDescription
        ?? "The local video preview could not be played."
      return
    }
    if isPlaying {
      stopPreviewPlayback(syncCurrentTime: true)
      return
    }

    let target: Int
    if playheadMilliseconds >= endMilliseconds {
      var updated = timeline
      updated.setPlayheadMilliseconds(startMilliseconds)
      timeline = updated
      target = updated.playheadMilliseconds
    } else {
      target = playheadMilliseconds
    }
    isPlaying = false
    playbackController.seek(
      toMilliseconds: target,
      // Playback must begin inside the selected half-open range. Approximate
      // sample tolerance is reserved for paused drag previews.
      toleranceMilliseconds: 0,
      playWhenReady: true
    ) { [weak self] in
      guard let self, !self.isExtracting else { return }
      self.isPlaying = true
      self.startPreviewTicking()
    }
  }

  private func startPreviewTicking() {
    previewTickTask?.cancel()
    previewTickTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 16_666_667)
        } catch {
          return
        }
        guard let self, self.isPlaying else { return }
        self.synchronizePreviewPlayhead()
      }
    }
  }

  func extract(
    onComplete: @escaping @MainActor @Sendable (LocalVideoImportResult) -> Void
  ) {
    guard !isExtracting, let selection, let plan else { return }
    stopPreviewPlayback(syncCurrentTime: false)
    isExtracting = true
    completedFrameCount = 0
    totalFrameCount = plan.expectedFrameCount
    errorMessage = nil
    let generation = UUID()
    extractionGeneration = generation
    let descriptor = descriptor
    // Capture one stable MainActor reference for the @Sendable progress sink.
    // Capturing the outer task's mutable weak-self storage would be a Swift 6
    // data-race error.
    let progressModel = self
    extractionTask = Task { [weak self] in
      do {
        let result = try await LocalVideoImportService.extract(
          descriptor: descriptor,
          selection: selection
        ) { progress in
          Task { @MainActor in
            guard progressModel.extractionGeneration == generation,
              progressModel.isExtracting
            else { return }
            progressModel.completedFrameCount = progress.completedFrameCount
            progressModel.totalFrameCount = progress.totalFrameCount
          }
        }
        guard !Task.isCancelled, self?.extractionGeneration == generation else { return }
        self?.isExtracting = false
        self?.extractionTask = nil
        self?.extractionGeneration = nil
        onComplete(result)
      } catch is CancellationError {
        guard self?.extractionGeneration == generation else { return }
        self?.isExtracting = false
        self?.extractionTask = nil
        self?.extractionGeneration = nil
      } catch {
        guard self?.extractionGeneration == generation else { return }
        self?.isExtracting = false
        self?.extractionTask = nil
        self?.extractionGeneration = nil
        self?.errorMessage = error.localizedDescription
      }
    }
  }

  func cancel() {
    stopPreviewPlayback(syncCurrentTime: false)
    extractionTask?.cancel()
    extractionTask = nil
    extractionGeneration = nil
    isExtracting = false
    playbackController?.teardown()
    playbackController = nil
    previewPlayer?.replaceCurrentItem(with: nil)
  }

  func pausePreviewForInactivity() {
    stopPreviewPlayback(syncCurrentTime: true)
  }

  private func seekPreview(to milliseconds: Int) {
    guard let playbackController else { return }
    let halfSampleMilliseconds = max(1, 500 / max(1, framesPerSecond))
    playbackController.seek(
      toMilliseconds: milliseconds,
      toleranceMilliseconds: halfSampleMilliseconds,
      playWhenReady: false
    )
  }

  private func stopPreviewPlayback(syncCurrentTime: Bool) {
    playbackController?.pauseAndInvalidatePendingSeek()
    if syncCurrentTime {
      synchronizePreviewPlayhead()
    }
    isPlaying = false
    previewTickTask?.cancel()
    previewTickTask = nil
  }

  private func synchronizePreviewPlayhead() {
    guard let previewPlayer else { return }
    if previewPlayer.currentItem?.status == .failed {
      stopPreviewPlayback(syncCurrentTime: false)
      previewErrorMessage =
        previewPlayer.currentItem?.error?.localizedDescription
        ?? "The local video preview could not be played."
      return
    }
    let seconds = CMTimeGetSeconds(previewPlayer.currentTime())
    let rawMilliseconds = seconds * 1_000
    guard rawMilliseconds.isFinite, rawMilliseconds >= 0 else { return }
    let boundedMilliseconds = min(
      Double(durationMilliseconds),
      rawMilliseconds.rounded()
    )
    let milliseconds = Int(boundedMilliseconds)

    if milliseconds >= endMilliseconds {
      stopPreviewPlayback(syncCurrentTime: false)
      var updated = timeline
      updated.setPlayheadMilliseconds(endMilliseconds)
      timeline = updated
      return
    }
    if milliseconds < startMilliseconds {
      var updated = timeline
      updated.setPlayheadMilliseconds(startMilliseconds)
      timeline = updated
      seekPreview(to: updated.playheadMilliseconds)
      return
    }
    var updated = timeline
    updated.setPlayheadMilliseconds(milliseconds)
    timeline = updated
  }

  private func handlePreviewBoundaryReached() {
    isPlaying = false
    previewTickTask?.cancel()
    previewTickTask = nil
    var updated = timeline
    updated.setPlayheadMilliseconds(endMilliseconds)
    timeline = updated
  }
}

private struct LocalVideoPlayerSurface: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> LocalVideoPlayerSurfaceView {
    let view = LocalVideoPlayerSurfaceView()
    view.playerLayer.player = player
    return view
  }

  func updateNSView(_ nsView: LocalVideoPlayerSurfaceView, context: Context) {
    nsView.playerLayer.player = player
  }

  static func dismantleNSView(_ nsView: LocalVideoPlayerSurfaceView, coordinator: ()) {
    nsView.playerLayer.player = nil
  }
}

private final class LocalVideoPlayerSurfaceView: NSView {
  let playerLayer = AVPlayerLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    playerLayer.videoGravity = .resizeAspect
    layer?.addSublayer(playerLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    playerLayer.frame = bounds
  }
}
