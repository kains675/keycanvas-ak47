import AppKit
import SwiftUI

@MainActor
protocol LocalVideoTrimFocusRequester: AnyObject {
  func requestLocalVideoTrimKeyFocus()
  func releaseLocalVideoTrimKeyFocus()
}

/// Owns the timeline's scoped keyboard target. It routes nothing until a
/// marker is explicitly selected and clears that selection as soon as its
/// private responder loses first-responder status.
@MainActor
final class LocalVideoTrimKeyboardRoute: ObservableObject {
  typealias StepHandler = (LocalVideoTrimFocus, LocalVideoTrimStepDirection, Int) -> Void

  @Published private(set) var activeControl: LocalVideoTrimFocus?
  private weak var focusRequester: LocalVideoTrimFocusRequester?
  private var isEnabled = true
  private var stepHandler: StepHandler?

  func configure(isEnabled: Bool, stepHandler: @escaping StepHandler) {
    self.isEnabled = isEnabled
    self.stepHandler = stepHandler
    if !isEnabled, activeControl != nil {
      activeControl = nil
      focusRequester?.releaseLocalVideoTrimKeyFocus()
    }
  }

  func attach(_ requester: LocalVideoTrimFocusRequester) {
    focusRequester = requester
  }

  func detach(_ requester: LocalVideoTrimFocusRequester) {
    guard focusRequester === requester else { return }
    requester.releaseLocalVideoTrimKeyFocus()
    focusRequester = nil
    if activeControl != nil {
      activeControl = nil
    }
    stepHandler = nil
  }

  func activate(_ control: LocalVideoTrimFocus) {
    guard isEnabled else { return }
    activeControl = control
    focusRequester?.requestLocalVideoTrimKeyFocus()
  }

  func deactivate() {
    if activeControl != nil {
      activeControl = nil
    }
    focusRequester?.releaseLocalVideoTrimKeyFocus()
  }

  @discardableResult
  func route(_ direction: LocalVideoTrimStepDirection) -> Bool {
    guard isEnabled, let activeControl, let stepHandler else { return false }
    stepHandler(activeControl, direction, 1)
    return true
  }

  func responderDidResign(_ requester: LocalVideoTrimFocusRequester) {
    guard focusRequester === requester else { return }
    if activeControl != nil {
      activeControl = nil
    }
  }
}

struct LocalVideoTrimKeyResponder: NSViewRepresentable {
  let route: LocalVideoTrimKeyboardRoute
  let isEnabled: Bool
  let onStep: LocalVideoTrimKeyboardRoute.StepHandler

  func makeNSView(context _: Context) -> LocalVideoTrimKeyResponderView {
    let view = LocalVideoTrimKeyResponderView(route: route)
    view.isRoutingEnabled = isEnabled
    route.configure(isEnabled: isEnabled, stepHandler: onStep)
    route.attach(view)
    return view
  }

  func updateNSView(_ nsView: LocalVideoTrimKeyResponderView, context _: Context) {
    nsView.isRoutingEnabled = isEnabled
    route.configure(isEnabled: isEnabled, stepHandler: onStep)
  }

  static func dismantleNSView(_ nsView: LocalVideoTrimKeyResponderView, coordinator _: ()) {
    nsView.invalidate()
  }
}

@MainActor
final class LocalVideoTrimKeyResponderView: NSView, LocalVideoTrimFocusRequester {
  weak var route: LocalVideoTrimKeyboardRoute?
  var isRoutingEnabled = true
  private var focusRequestGeneration: UInt64 = 0
  private var pendingFocusRequestGeneration: UInt64?

  init(route: LocalVideoTrimKeyboardRoute) {
    self.route = route
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    isRoutingEnabled && route?.activeControl != nil
  }

  override func keyDown(with event: NSEvent) {
    guard isRoutingEnabled,
      let direction = Self.direction(
        forKeyCode: event.keyCode,
        modifierFlags: event.modifierFlags
      ),
      route?.route(direction) == true
    else {
      super.keyDown(with: event)
      return
    }
  }

  override func resignFirstResponder() -> Bool {
    let didResign = super.resignFirstResponder()
    if didResign, pendingFocusRequestGeneration == nil {
      route?.responderDidResign(self)
    }
    return didResign
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil, route?.activeControl != nil else { return }
    requestLocalVideoTrimKeyFocus()
  }

  func requestLocalVideoTrimKeyFocus() {
    guard isRoutingEnabled, route?.activeControl != nil else { return }
    focusRequestGeneration &+= 1
    let generation = focusRequestGeneration
    pendingFocusRequestGeneration = generation
    _ = window?.makeFirstResponder(self)

    // Mouse-up can finish after the SwiftUI click action. Reassert once on the
    // next main-loop turn, but only while this same route remains active.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      defer {
        if self.pendingFocusRequestGeneration == generation {
          self.pendingFocusRequestGeneration = nil
        }
      }
      guard self.pendingFocusRequestGeneration == generation,
        self.isRoutingEnabled,
        self.route?.activeControl != nil
      else { return }
      _ = self.window?.makeFirstResponder(self)
    }
  }

  func releaseLocalVideoTrimKeyFocus() {
    focusRequestGeneration &+= 1
    pendingFocusRequestGeneration = nil
    if window?.firstResponder === self {
      _ = window?.makeFirstResponder(nil)
    }
  }

  func invalidate() {
    guard let attachedRoute = route else { return }
    route = nil
    isRoutingEnabled = false
    releaseLocalVideoTrimKeyFocus()
    let requester = self

    // SwiftUI dismantles representable views while its AttributeGraph is in
    // an exclusive mutation. Publishing `activeControl` from that callback
    // traps in Swift's exclusivity runtime, so detach on the next MainActor
    // turn after graph teardown has completed.
    Task { @MainActor [weak attachedRoute, requester] in
      attachedRoute?.detach(requester)
    }
  }

  static func direction(
    forKeyCode keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags = []
  ) -> LocalVideoTrimStepDirection? {
    guard modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
      return nil
    }
    switch keyCode {
    case 123:
      return .backward
    case 124:
      return .forward
    default:
      return nil
    }
  }
}
