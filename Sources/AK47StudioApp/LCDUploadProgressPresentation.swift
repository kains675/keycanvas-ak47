struct LCDUploadProgressPresentation {
  static func percentage(
    completedAcknowledgements: Int,
    totalAcknowledgements: Int
  ) -> Int {
    guard totalAcknowledgements > 0 else { return 0 }
    let completed = min(max(completedAcknowledgements, 0), totalAcknowledgements)
    let percent = (Double(completed) / Double(totalAcknowledgements) * 100).rounded(.down)
    return min(max(Int(percent), 0), 100)
  }

  static func text(
    completedAcknowledgements: Int,
    totalAcknowledgements: Int,
    language: AppLanguage
  ) -> String {
    let percent = percentage(
      completedAcknowledgements: completedAcknowledgements,
      totalAcknowledgements: totalAcknowledgements
    )
    return studioText(
      "이미지 \(percent)% 전송 완료. 앱을 닫거나 슬립모드 전환, 혹은 케이블 분리를 하지 마세요.",
      "Image transfer is \(percent)% complete. Do not quit the app, put the Mac to sleep, or disconnect the cable.",
      language: language
    )
  }
}
