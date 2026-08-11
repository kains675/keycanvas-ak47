struct LCDExperimentalApplyAcknowledgement: Equatable {
  static let koreanText =
    "현재 프로그램은 실험적 기능임에 따라 장치 이상, 고장이 발생 할 수 있음을 인지하고 있습니다."
  static let englishText =
    "I understand that this program is experimental and may cause device malfunction or failure."

  var isAcknowledged = false
  private(set) var wasConsumed = false

  var canApply: Bool {
    isAcknowledged && !wasConsumed
  }

  mutating func consume() -> Bool {
    guard canApply else { return false }
    wasConsumed = true
    return true
  }
}
