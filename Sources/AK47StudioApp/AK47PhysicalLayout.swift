import CoreGraphics

struct AK47PhysicalKey: Identifiable, Equatable {
  let id: String
  let label: String
  let x: CGFloat
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat
  /// Firmware RGB slot. This is not the key's ordinal in `AK47PhysicalLayout.keys`.
  let lightIndex: Int

  var center: CGPoint {
    CGPoint(x: x + width / 2, y: y + height / 2)
  }
}

/// Physical switch positions independently redrawn from the AK47 non-PRO's
/// observable 84-key layout. Coordinates are normalized to the top-left key.
enum AK47PhysicalLayout {
  static let canvasSize = CGSize(width: 672, height: 226)
  static let lcdFrame = CGRect(x: 564, y: 0, width: 70, height: 32)
  static let knobFrame = CGRect(x: 640, y: 0, width: 32, height: 32)

  static let keys: [AK47PhysicalKey] = {
    precondition(keyGeometry.count == protocolLightIndicesByLayoutOrdinal.count)
    return zip(keyGeometry, protocolLightIndicesByLayoutOrdinal).map { key, lightIndex in
      AK47PhysicalKey(
        id: key.id,
        label: key.label,
        x: key.x,
        y: key.y,
        width: key.width,
        height: key.height,
        lightIndex: lightIndex
      )
    }
  }()

  static let keyIDs = keys.map(\.id)

  /// Stable positions used by the original local profile schema. The first
  /// prototype drew the navigation keys in a different order and included a
  /// non-existent Print Screen position. Keep every established position and
  /// assign that unused slot to the real Menu key so existing drafts do not
  /// silently move to another physical key.
  static let profileKeyIDs: [String] = {
    let ids = [
      "Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
      "Menu", "Delete", "Home",
      "Grave", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Minus", "Equal",
      "Backspace", "Page Up",
      "Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Left Bracket",
      "Right Bracket", "Backslash", "Page Down",
      "Caps Lock", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Semicolon", "Quote",
      "Return", "Insert",
      "Left Shift", "Z", "X", "C", "V", "B", "N", "M", "Comma", "Period", "Slash",
      "Right Shift", "Up", "End",
      "Left Control", "Left Option", "Left Command", "Space", "Right Option", "Fn",
      "Right Control", "Left", "Down", "Right",
    ]
    precondition(ids.count == keys.count && Set(ids) == Set(keyIDs))
    return ids
  }()

  static func profilePosition(for keyID: String) -> Int? {
    profileKeyIDs.firstIndex(of: keyID)
  }

  /// Mapping verified from the Windows layout data. Physical array order and
  /// firmware RGB slot order diverge around the navigation and wide keys.
  static let protocolLightIndicesByLayoutOrdinal: [Int] =
    Array(1...13)
    + Array(19...31)
    + [103]
    + Array(116...118)
    + Array(37...49)
    + [67]
    + Array(119...121)
    + Array(55...66)
    + [85]
    + Array(73...84)
    + [101]
    + Array(91...98)
    + [99, 100, 102]

  private struct KeyGeometry {
    let id: String
    let label: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    var height: CGFloat = 32
  }

  private static let keyGeometry: [KeyGeometry] = [
    // Function row. The space on the right belongs to the LCD and knob.
    KeyGeometry(id: "Esc", label: "esc", x: 0, y: 0, width: 32),
    KeyGeometry(id: "F1", label: "F1", x: 75, y: 0, width: 32),
    KeyGeometry(id: "F2", label: "F2", x: 112, y: 0, width: 32),
    KeyGeometry(id: "F3", label: "F3", x: 148, y: 0, width: 32),
    KeyGeometry(id: "F4", label: "F4", x: 186, y: 0, width: 32),
    KeyGeometry(id: "F5", label: "F5", x: 242, y: 0, width: 32),
    KeyGeometry(id: "F6", label: "F6", x: 279, y: 0, width: 32),
    KeyGeometry(id: "F7", label: "F7", x: 316, y: 0, width: 32),
    KeyGeometry(id: "F8", label: "F8", x: 353, y: 0, width: 32),
    KeyGeometry(id: "F9", label: "F9", x: 408, y: 0, width: 32),
    KeyGeometry(id: "F10", label: "F10", x: 445, y: 0, width: 32),
    KeyGeometry(id: "F11", label: "F11", x: 482, y: 0, width: 32),
    KeyGeometry(id: "F12", label: "F12", x: 520, y: 0, width: 32),

    // Number row and the first navigation row.
    KeyGeometry(id: "Grave", label: "`", x: 0, y: 46, width: 32),
    KeyGeometry(id: "1", label: "1", x: 37, y: 46, width: 32),
    KeyGeometry(id: "2", label: "2", x: 75, y: 46, width: 32),
    KeyGeometry(id: "3", label: "3", x: 112, y: 46, width: 32),
    KeyGeometry(id: "4", label: "4", x: 148, y: 46, width: 32),
    KeyGeometry(id: "5", label: "5", x: 186, y: 46, width: 32),
    KeyGeometry(id: "6", label: "6", x: 223, y: 46, width: 32),
    KeyGeometry(id: "7", label: "7", x: 260, y: 46, width: 32),
    KeyGeometry(id: "8", label: "8", x: 297, y: 46, width: 32),
    KeyGeometry(id: "9", label: "9", x: 334, y: 46, width: 32),
    KeyGeometry(id: "0", label: "0", x: 371, y: 46, width: 32),
    KeyGeometry(id: "Minus", label: "−", x: 408, y: 46, width: 32),
    KeyGeometry(id: "Equal", label: "=", x: 445, y: 46, width: 32),
    KeyGeometry(id: "Backspace", label: "backspace", x: 482, y: 46, width: 70),
    KeyGeometry(id: "Insert", label: "ins", x: 564, y: 46, width: 32),
    KeyGeometry(id: "Home", label: "home", x: 602, y: 46, width: 32),
    KeyGeometry(id: "Page Up", label: "pg↑", x: 640, y: 46, width: 32),

    // Q row and the second navigation row.
    KeyGeometry(id: "Tab", label: "tab", x: 0, y: 82, width: 52),
    KeyGeometry(id: "Q", label: "Q", x: 56, y: 82, width: 32),
    KeyGeometry(id: "W", label: "W", x: 94, y: 82, width: 32),
    KeyGeometry(id: "E", label: "E", x: 131, y: 82, width: 32),
    KeyGeometry(id: "R", label: "R", x: 167, y: 82, width: 32),
    KeyGeometry(id: "T", label: "T", x: 205, y: 82, width: 32),
    KeyGeometry(id: "Y", label: "Y", x: 242, y: 82, width: 32),
    KeyGeometry(id: "U", label: "U", x: 279, y: 82, width: 32),
    KeyGeometry(id: "I", label: "I", x: 316, y: 82, width: 32),
    KeyGeometry(id: "O", label: "O", x: 353, y: 82, width: 32),
    KeyGeometry(id: "P", label: "P", x: 390, y: 82, width: 32),
    KeyGeometry(id: "Left Bracket", label: "[", x: 427, y: 82, width: 32),
    KeyGeometry(id: "Right Bracket", label: "]", x: 464, y: 82, width: 32),
    KeyGeometry(id: "Backslash", label: "\\", x: 500, y: 82, width: 52),
    KeyGeometry(id: "Delete", label: "del", x: 564, y: 82, width: 32),
    KeyGeometry(id: "End", label: "end", x: 602, y: 82, width: 32),
    KeyGeometry(id: "Page Down", label: "pg↓", x: 640, y: 82, width: 32),

    // Home row.
    KeyGeometry(id: "Caps Lock", label: "caps", x: 0, y: 118, width: 60),
    KeyGeometry(id: "A", label: "A", x: 66, y: 118, width: 32),
    KeyGeometry(id: "S", label: "S", x: 103, y: 118, width: 32),
    KeyGeometry(id: "D", label: "D", x: 140, y: 118, width: 32),
    KeyGeometry(id: "F", label: "F", x: 177, y: 118, width: 32),
    KeyGeometry(id: "G", label: "G", x: 214, y: 118, width: 32),
    KeyGeometry(id: "H", label: "H", x: 251, y: 118, width: 32),
    KeyGeometry(id: "J", label: "J", x: 288, y: 118, width: 32),
    KeyGeometry(id: "K", label: "K", x: 325, y: 118, width: 32),
    KeyGeometry(id: "L", label: "L", x: 362, y: 118, width: 32),
    KeyGeometry(id: "Semicolon", label: ";", x: 399, y: 118, width: 32),
    KeyGeometry(id: "Quote", label: "'", x: 436, y: 118, width: 32),
    KeyGeometry(id: "Return", label: "enter", x: 474, y: 118, width: 78),

    // Shift row and the separated up-arrow key.
    KeyGeometry(id: "Left Shift", label: "shift", x: 0, y: 157, width: 79),
    KeyGeometry(id: "Z", label: "Z", x: 84, y: 157, width: 32),
    KeyGeometry(id: "X", label: "X", x: 122, y: 157, width: 32),
    KeyGeometry(id: "C", label: "C", x: 159, y: 157, width: 32),
    KeyGeometry(id: "V", label: "V", x: 196, y: 157, width: 32),
    KeyGeometry(id: "B", label: "B", x: 233, y: 157, width: 32),
    KeyGeometry(id: "N", label: "N", x: 270, y: 157, width: 32),
    KeyGeometry(id: "M", label: "M", x: 307, y: 157, width: 32),
    KeyGeometry(id: "Comma", label: ",", x: 344, y: 157, width: 32),
    KeyGeometry(id: "Period", label: ".", x: 381, y: 157, width: 32),
    KeyGeometry(id: "Slash", label: "/", x: 418, y: 157, width: 32),
    KeyGeometry(id: "Right Shift", label: "shift", x: 454, y: 157, width: 98),
    KeyGeometry(id: "Up", label: "↑", x: 602, y: 157, width: 32),

    // Bottom row and the separated inverted-T arrow cluster.
    KeyGeometry(id: "Left Control", label: "ctrl", x: 0, y: 194, width: 42),
    KeyGeometry(id: "Left Command", label: "win", x: 46, y: 194, width: 42),
    KeyGeometry(id: "Left Option", label: "alt", x: 92, y: 194, width: 42),
    KeyGeometry(id: "Space", label: "space", x: 140, y: 194, width: 226),
    KeyGeometry(id: "Right Option", label: "alt", x: 372, y: 194, width: 42),
    KeyGeometry(id: "Fn", label: "fn", x: 418, y: 194, width: 42),
    KeyGeometry(id: "Menu", label: "super", x: 464, y: 194, width: 42),
    KeyGeometry(id: "Right Control", label: "ctrl", x: 510, y: 194, width: 42),
    KeyGeometry(id: "Left", label: "←", x: 564, y: 194, width: 32),
    KeyGeometry(id: "Down", label: "↓", x: 602, y: 194, width: 32),
    KeyGeometry(id: "Right", label: "→", x: 640, y: 194, width: 32),
  ]
}
