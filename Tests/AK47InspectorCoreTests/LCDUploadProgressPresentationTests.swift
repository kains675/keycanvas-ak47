import XCTest

@testable import AK47StudioApp

final class LCDUploadProgressPresentationTests: XCTestCase {
  func testPercentageUsesAcknowledgementsAndClampsToZeroThroughOneHundred() {
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: -1,
        totalAcknowledgements: 16
      ),
      0
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 1,
        totalAcknowledgements: 16
      ),
      6
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 1_107,
        totalAcknowledgements: 2_215
      ),
      49
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 1_108,
        totalAcknowledgements: 2_215
      ),
      50
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 16,
        totalAcknowledgements: 16
      ),
      100
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 17,
        totalAcknowledgements: 16
      ),
      100
    )
  }

  func testPercentageIsSafeWhenTotalIsZeroOrNegative() {
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 0,
        totalAcknowledgements: 0
      ),
      0
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 10,
        totalAcknowledgements: 0
      ),
      0
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: 10,
        totalAcknowledgements: -1
      ),
      0
    )
  }

  func testLocalizedProgressCopyUsesTheRequestedKoreanText() {
    XCTAssertEqual(
      LCDUploadProgressPresentation.text(
        completedAcknowledgements: 8,
        totalAcknowledgements: 16,
        language: .korean
      ),
      "이미지 50% 전송 완료. 앱을 닫거나 슬립모드 전환, 혹은 케이블 분리를 하지 마세요."
    )
    XCTAssertEqual(
      LCDUploadProgressPresentation.text(
        completedAcknowledgements: 8,
        totalAcknowledgements: 16,
        language: .english
      ),
      "Image transfer is 50% complete. Do not quit the app, put the Mac to sleep, or disconnect the cable."
    )
  }
}
