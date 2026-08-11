import AK47InspectorCore
import AppKit

/// Prevents a normal app termination from silently abandoning the narrow LCD
/// experiment and latches power/sleep transitions as transaction failures.
/// A forced process kill or power loss remains covered only by the durable
/// write-ahead quarantine marker in AK47InspectorCore.
final class KeyCanvasApplicationDelegate: NSObject, NSApplicationDelegate {
  private var workspaceObservers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    let center = NSWorkspace.shared.notificationCenter
    workspaceObservers = [
      center.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { _ in
        AK47LCDUploadLifecycleInterlock.recordLifecycleHazard()
      },
      center.addObserver(
        forName: NSWorkspace.willPowerOffNotification,
        object: nil,
        queue: .main
      ) { _ in
        AK47LCDUploadLifecycleInterlock.recordLifecycleHazard()
      },
    ]
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard AK47LCDUploadLifecycleInterlock.isTransferActive else { return .terminateNow }
    AK47LCDUploadLifecycleInterlock.recordLifecycleHazard()
    NSSound.beep()
    return .terminateCancel
  }

  func applicationWillTerminate(_ notification: Notification) {
    AK47LCDUploadLifecycleInterlock.recordLifecycleHazard()
  }

  deinit {
    let center = NSWorkspace.shared.notificationCenter
    for observer in workspaceObservers { center.removeObserver(observer) }
  }
}
