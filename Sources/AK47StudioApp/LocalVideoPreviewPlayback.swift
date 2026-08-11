@preconcurrency import AVFoundation
import Foundation

@MainActor
protocol LocalVideoPreviewPlaybackBackend: AnyObject {
  func play()
  func pause()
  func cancelPendingSeeks()
  func setForwardPlaybackEnd(milliseconds: Int?)
  func seek(
    toMilliseconds: Int,
    toleranceMilliseconds: Int,
    completion: @escaping @MainActor @Sendable (Bool) -> Void
  )
  func installBoundaryObserver(
    atMilliseconds: Int,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> Any
  func removeBoundaryObserver(_ token: Any)
}

@MainActor
final class LocalVideoAVPlayerBackend: LocalVideoPreviewPlaybackBackend {
  let player: AVPlayer

  init(player: AVPlayer) {
    self.player = player
  }

  func play() {
    player.play()
  }

  func pause() {
    player.pause()
  }

  func cancelPendingSeeks() {
    player.currentItem?.cancelPendingSeeks()
  }

  func setForwardPlaybackEnd(milliseconds: Int?) {
    player.currentItem?.forwardPlaybackEndTime =
      milliseconds.map {
        CMTime(value: CMTimeValue(max(0, $0)), timescale: 1_000)
      } ?? .invalid
  }

  func seek(
    toMilliseconds: Int,
    toleranceMilliseconds: Int,
    completion: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    let target = CMTime(value: CMTimeValue(toMilliseconds), timescale: 1_000)
    let tolerance = CMTime(
      value: CMTimeValue(max(0, toleranceMilliseconds)),
      timescale: 1_000
    )
    player.seek(
      to: target,
      toleranceBefore: tolerance,
      toleranceAfter: tolerance
    ) { finished in
      Task { @MainActor in
        completion(finished)
      }
    }
  }

  func installBoundaryObserver(
    atMilliseconds: Int,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> Any {
    player.addBoundaryTimeObserver(
      forTimes: [
        NSValue(
          time: CMTime(value: CMTimeValue(max(0, atMilliseconds)), timescale: 1_000)
        )
      ],
      queue: .main
    ) {
      MainActor.assumeIsolated {
        handler()
      }
    }
  }

  func removeBoundaryObserver(_ token: Any) {
    player.removeTimeObserver(token)
  }
}

/// Serializes preview seeks and selected-range boundary observation. A seek
/// completion may play only if its generation is still current; every drag,
/// FPS change, cancellation and teardown invalidates older completions.
@MainActor
final class LocalVideoPreviewPlaybackController {
  private let backend: LocalVideoPreviewPlaybackBackend
  private var seekGeneration: UInt64 = 0
  private var boundaryGeneration: UInt64 = 0
  private var boundaryToken: Any?
  private(set) var boundaryInstallCount = 0
  private(set) var boundaryRemovalCount = 0
  private(set) var isTornDown = false

  var onBoundaryReached: (@MainActor @Sendable () -> Void)?

  init(backend: LocalVideoPreviewPlaybackBackend) {
    self.backend = backend
  }

  func updateBoundary(endMilliseconds: Int) {
    guard !isTornDown else { return }
    boundaryGeneration &+= 1
    let generation = boundaryGeneration
    removeBoundaryIfNeeded()
    backend.setForwardPlaybackEnd(milliseconds: endMilliseconds)
    boundaryToken = backend.installBoundaryObserver(
      atMilliseconds: max(0, endMilliseconds)
    ) { [weak self] in
      guard let self, !self.isTornDown,
        self.boundaryGeneration == generation
      else { return }
      self.pauseAndInvalidatePendingSeek()
      self.onBoundaryReached?()
    }
    boundaryInstallCount += 1
  }

  func seek(
    toMilliseconds: Int,
    toleranceMilliseconds: Int,
    playWhenReady: Bool,
    completion: (@MainActor @Sendable () -> Void)? = nil
  ) {
    guard !isTornDown else { return }
    seekGeneration &+= 1
    let generation = seekGeneration
    backend.pause()
    backend.cancelPendingSeeks()
    backend.seek(
      toMilliseconds: max(0, toMilliseconds),
      toleranceMilliseconds: max(0, toleranceMilliseconds)
    ) { [weak self] finished in
      guard let self, !self.isTornDown,
        finished,
        self.seekGeneration == generation
      else { return }
      if playWhenReady {
        self.backend.play()
      }
      completion?()
    }
  }

  func pauseAndInvalidatePendingSeek() {
    guard !isTornDown else { return }
    seekGeneration &+= 1
    backend.pause()
    backend.cancelPendingSeeks()
  }

  func teardown() {
    guard !isTornDown else { return }
    pauseAndInvalidatePendingSeek()
    boundaryGeneration &+= 1
    removeBoundaryIfNeeded()
    backend.setForwardPlaybackEnd(milliseconds: nil)
    onBoundaryReached = nil
    isTornDown = true
  }

  private func removeBoundaryIfNeeded() {
    guard let boundaryToken else { return }
    self.boundaryToken = nil
    backend.removeBoundaryObserver(boundaryToken)
    boundaryRemovalCount += 1
  }
}
