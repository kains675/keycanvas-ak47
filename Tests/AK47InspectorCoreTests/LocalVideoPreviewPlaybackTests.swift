import Foundation
import XCTest

@testable import AK47StudioApp

@MainActor
final class LocalVideoPreviewPlaybackTests: XCTestCase {
  func testOnlyCurrentSeekCompletionMayStartPlayback() {
    let backend = FakeLocalVideoPlaybackBackend()
    let controller = LocalVideoPreviewPlaybackController(backend: backend)
    let completions = MainActorCounter()

    controller.seek(
      toMilliseconds: 100,
      toleranceMilliseconds: 0,
      playWhenReady: true
    ) {
      completions.value += 1
    }
    let staleRequest = backend.lastSeekIdentifier

    controller.seek(
      toMilliseconds: 200,
      toleranceMilliseconds: 25,
      playWhenReady: false
    ) {
      completions.value += 1
    }
    let currentRequest = backend.lastSeekIdentifier

    backend.completeSeek(identifier: staleRequest, finished: true)
    XCTAssertEqual(backend.playCount, 0)
    XCTAssertEqual(completions.value, 0)

    backend.completeSeek(identifier: currentRequest, finished: true)
    XCTAssertEqual(backend.playCount, 0)
    XCTAssertEqual(completions.value, 1)
    XCTAssertEqual(backend.seekRequests.last?.targetMilliseconds, 200)
    XCTAssertEqual(backend.seekRequests.last?.toleranceMilliseconds, 25)

    controller.seek(
      toMilliseconds: 300,
      toleranceMilliseconds: 0,
      playWhenReady: true
    )
    backend.completeSeek(identifier: backend.lastSeekIdentifier, finished: true)
    XCTAssertEqual(backend.playCount, 1)
    XCTAssertEqual(backend.cancelPendingSeeksCount, 3)
  }

  func testRemovedBoundaryCallbackIsIgnoredAfterEndChanges() throws {
    let backend = FakeLocalVideoPlaybackBackend()
    let controller = LocalVideoPreviewPlaybackController(backend: backend)
    let boundaryCallbacks = MainActorCounter()
    controller.onBoundaryReached = {
      boundaryCallbacks.value += 1
      backend.events.append("client-boundary")
    }

    controller.updateBoundary(endMilliseconds: 900)
    let oldToken = try XCTUnwrap(backend.lastBoundaryIdentifier)
    controller.updateBoundary(endMilliseconds: 800)
    let currentToken = try XCTUnwrap(backend.lastBoundaryIdentifier)

    XCTAssertEqual(controller.boundaryInstallCount, 2)
    XCTAssertEqual(controller.boundaryRemovalCount, 1)
    XCTAssertEqual(backend.removedBoundaryIdentifiers, [oldToken])
    XCTAssertEqual(backend.forwardPlaybackEnds, [900, 800])

    backend.fireBoundary(identifier: oldToken)
    XCTAssertEqual(boundaryCallbacks.value, 0)
    XCTAssertEqual(backend.pauseCount, 0)

    backend.fireBoundary(identifier: currentToken)
    XCTAssertEqual(boundaryCallbacks.value, 1)
    XCTAssertEqual(Array(backend.events.suffix(3)), ["pause", "cancel-seeks", "client-boundary"])
  }

  func testTeardownBalancesObserverRemovalAndInvalidatesQueuedWork() throws {
    let backend = FakeLocalVideoPlaybackBackend()
    let controller = LocalVideoPreviewPlaybackController(backend: backend)
    let boundaryCallbacks = MainActorCounter()
    controller.onBoundaryReached = { boundaryCallbacks.value += 1 }

    controller.updateBoundary(endMilliseconds: 900)
    let token = try XCTUnwrap(backend.lastBoundaryIdentifier)
    controller.seek(
      toMilliseconds: 100,
      toleranceMilliseconds: 0,
      playWhenReady: true
    )
    let pendingSeek = backend.lastSeekIdentifier

    controller.teardown()
    controller.teardown()

    XCTAssertTrue(controller.isTornDown)
    XCTAssertEqual(controller.boundaryInstallCount, 1)
    XCTAssertEqual(controller.boundaryRemovalCount, 1)
    XCTAssertEqual(backend.removedBoundaryIdentifiers, [token])
    XCTAssertEqual(backend.forwardPlaybackEnds, [900, nil])

    backend.completeSeek(identifier: pendingSeek, finished: true)
    backend.fireBoundary(identifier: token)
    XCTAssertEqual(backend.playCount, 0)
    XCTAssertEqual(boundaryCallbacks.value, 0)

    controller.updateBoundary(endMilliseconds: 700)
    controller.seek(
      toMilliseconds: 200,
      toleranceMilliseconds: 0,
      playWhenReady: true
    )
    XCTAssertEqual(controller.boundaryInstallCount, 1)
    XCTAssertEqual(backend.seekRequests.count, 1)
  }
}

@MainActor
private final class MainActorCounter {
  var value = 0
}

@MainActor
private final class FakeLocalVideoPlaybackBackend: LocalVideoPreviewPlaybackBackend {
  struct SeekRequest {
    let identifier: Int
    let targetMilliseconds: Int
    let toleranceMilliseconds: Int
  }

  private final class BoundaryToken {
    let identifier: Int

    init(identifier: Int) {
      self.identifier = identifier
    }
  }

  private var nextSeekIdentifier = 0
  private var seekCompletions: [Int: @MainActor @Sendable (Bool) -> Void] = [:]
  private var nextBoundaryIdentifier = 0
  private var boundaryHandlers: [Int: @MainActor @Sendable () -> Void] = [:]

  private(set) var playCount = 0
  private(set) var pauseCount = 0
  private(set) var cancelPendingSeeksCount = 0
  private(set) var seekRequests: [SeekRequest] = []
  private(set) var lastBoundaryIdentifier: Int?
  private(set) var removedBoundaryIdentifiers: [Int] = []
  private(set) var forwardPlaybackEnds: [Int?] = []
  var events: [String] = []

  var lastSeekIdentifier: Int {
    seekRequests.last?.identifier ?? -1
  }

  func play() {
    playCount += 1
    events.append("play")
  }

  func pause() {
    pauseCount += 1
    events.append("pause")
  }

  func cancelPendingSeeks() {
    cancelPendingSeeksCount += 1
    events.append("cancel-seeks")
  }

  func setForwardPlaybackEnd(milliseconds: Int?) {
    forwardPlaybackEnds.append(milliseconds)
  }

  func seek(
    toMilliseconds: Int,
    toleranceMilliseconds: Int,
    completion: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    let identifier = nextSeekIdentifier
    nextSeekIdentifier += 1
    seekRequests.append(
      SeekRequest(
        identifier: identifier,
        targetMilliseconds: toMilliseconds,
        toleranceMilliseconds: toleranceMilliseconds
      )
    )
    seekCompletions[identifier] = completion
  }

  func installBoundaryObserver(
    atMilliseconds _: Int,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> Any {
    let identifier = nextBoundaryIdentifier
    nextBoundaryIdentifier += 1
    let token = BoundaryToken(identifier: identifier)
    boundaryHandlers[identifier] = handler
    lastBoundaryIdentifier = identifier
    return token
  }

  func removeBoundaryObserver(_ token: Any) {
    guard let token = token as? BoundaryToken else {
      XCTFail("Unexpected boundary token")
      return
    }
    removedBoundaryIdentifiers.append(token.identifier)
    // Keep the handler to emulate an already-enqueued callback from a token
    // that AVPlayer has just removed.
  }

  func completeSeek(identifier: Int, finished: Bool) {
    let completion = seekCompletions.removeValue(forKey: identifier)
    completion?(finished)
  }

  func fireBoundary(identifier: Int) {
    boundaryHandlers[identifier]?()
  }
}
