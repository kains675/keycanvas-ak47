import XCTest

@testable import AK47StudioApp

@MainActor
final class LocalVideoTrimKeyboardRouteTests: XCTestCase {
  func testNoSelectionDoesNotRouteArrowCommands() {
    let route = LocalVideoTrimKeyboardRoute()
    var observed: [(LocalVideoTrimFocus, LocalVideoTrimStepDirection, Int)] = []
    route.configure(isEnabled: true) { observed.append(($0, $1, $2)) }

    XCTAssertFalse(route.route(.backward))
    XCTAssertFalse(route.route(.forward))
    XCTAssertTrue(observed.isEmpty)
  }

  func testSelectedControlRoutesLeftAndRightThenStopsAfterResign() {
    let route = LocalVideoTrimKeyboardRoute()
    let requester = FakeLocalVideoTrimFocusRequester()
    var observed: [(LocalVideoTrimFocus, LocalVideoTrimStepDirection, Int)] = []
    route.attach(requester)
    route.configure(isEnabled: true) { observed.append(($0, $1, $2)) }

    route.activate(.endHandle)
    XCTAssertEqual(route.activeControl, .endHandle)
    XCTAssertEqual(requester.focusRequestCount, 1)
    XCTAssertTrue(route.route(.backward))
    XCTAssertTrue(route.route(.forward))
    XCTAssertEqual(observed.map(\.0), [.endHandle, .endHandle])
    XCTAssertEqual(observed.map(\.1), [.backward, .forward])
    XCTAssertEqual(observed.map(\.2), [1, 1])

    route.responderDidResign(requester)
    XCTAssertNil(route.activeControl)
    XCTAssertFalse(route.route(.backward))
    XCTAssertEqual(observed.count, 2)
  }

  func testDisabledAndDetachedRoutesRemainInactive() {
    let route = LocalVideoTrimKeyboardRoute()
    let requester = FakeLocalVideoTrimFocusRequester()
    var stepCount = 0
    route.attach(requester)
    route.configure(isEnabled: false) { _, _, _ in stepCount += 1 }

    route.activate(.playhead)
    XCTAssertNil(route.activeControl)
    XCTAssertEqual(requester.focusRequestCount, 0)
    XCTAssertFalse(route.route(.forward))

    route.configure(isEnabled: true) { _, _, _ in stepCount += 1 }
    route.activate(.startHandle)
    route.detach(requester)
    XCTAssertNil(route.activeControl)
    XCTAssertFalse(route.route(.forward))
    XCTAssertEqual(requester.focusReleaseCount, 1)
    XCTAssertEqual(stepCount, 0)
  }

  func testOnlyLeftAndRightKeyCodesMapToTrimDirections() {
    XCTAssertEqual(LocalVideoTrimKeyResponderView.direction(forKeyCode: 123), .backward)
    XCTAssertEqual(LocalVideoTrimKeyResponderView.direction(forKeyCode: 124), .forward)
    XCTAssertNil(LocalVideoTrimKeyResponderView.direction(forKeyCode: 36))
    XCTAssertNil(LocalVideoTrimKeyResponderView.direction(forKeyCode: 125))
    for modifier: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
      XCTAssertNil(
        LocalVideoTrimKeyResponderView.direction(
          forKeyCode: 123,
          modifierFlags: modifier
        )
      )
      XCTAssertNil(
        LocalVideoTrimKeyResponderView.direction(
          forKeyCode: 124,
          modifierFlags: modifier
        )
      )
    }
  }

  func testDeactivateAndDisableReleaseOwnedWindowFirstResponder() {
    let route = LocalVideoTrimKeyboardRoute()
    let responder = LocalVideoTrimKeyResponderView(route: route)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = responder
    route.attach(responder)
    route.configure(isEnabled: true) { _, _, _ in }

    route.activate(.startHandle)
    XCTAssertTrue(window.firstResponder === responder)
    route.deactivate()
    XCTAssertFalse(window.firstResponder === responder)

    route.activate(.endHandle)
    XCTAssertTrue(window.firstResponder === responder)
    route.configure(isEnabled: false) { _, _, _ in }
    XCTAssertNil(route.activeControl)
    XCTAssertFalse(window.firstResponder === responder)

    responder.invalidate()
  }

  func testInvalidateDefersPublishedDetachUntilAfterDismantleTurn() async {
    let route = LocalVideoTrimKeyboardRoute()
    let responder = LocalVideoTrimKeyResponderView(route: route)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = responder
    route.attach(responder)
    route.configure(isEnabled: true) { _, _, _ in }
    route.activate(.endHandle)
    XCTAssertTrue(window.firstResponder === responder)

    responder.invalidate()

    XCTAssertEqual(route.activeControl, .endHandle)
    XCTAssertNil(responder.route)
    XCTAssertFalse(window.firstResponder === responder)

    await Task.yield()

    XCTAssertNil(route.activeControl)
    XCTAssertFalse(route.route(.forward))
  }
}

@MainActor
private final class FakeLocalVideoTrimFocusRequester: LocalVideoTrimFocusRequester {
  private(set) var focusRequestCount = 0
  private(set) var focusReleaseCount = 0

  func requestLocalVideoTrimKeyFocus() {
    focusRequestCount += 1
  }

  func releaseLocalVideoTrimKeyFocus() {
    focusReleaseCount += 1
  }
}
