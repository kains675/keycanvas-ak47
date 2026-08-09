import Foundation

/// Prevents two diagnostic operations from consuming the same HID response.
/// Access is fail-fast: a second operation is rejected instead of queued.
enum HIDDeviceOperationGate {
  private static let lock = NSLock()
  private static var inUse = false
  private static var poisoned = false

  static func acquire() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !inUse, !poisoned else { return false }
    inUse = true
    return true
  }

  static func release() {
    lock.lock()
    inUse = false
    lock.unlock()
  }

  static func poison() {
    lock.lock()
    poisoned = true
    inUse = false
    lock.unlock()
  }

  static var isPoisoned: Bool {
    lock.lock()
    defer { lock.unlock() }
    return poisoned
  }
}
