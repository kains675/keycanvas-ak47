import Foundation
import XCTest

@testable import AK47InspectorCore

final class AK47FactoryResetTests: XCTestCase {
  private let exactTarget = AK47WiredDeviceTarget(
    product: "Archon AK47",
    locationID: 0x1234,
    versionNumber: 0x0115
  )

  func testVerifiedSubsetBuildsOnlyThreeFixedCategoriesInSafeOrder() throws {
    let plan = try AK47FactoryResetPreflight.plan(target: exactTarget)

    XCTAssertTrue(plan.hasCompleteDryRunShape)
    XCTAssertEqual(
      plan.requestedCategories,
      [.functionSettings, .perKeyRGB, .onboardLighting]
    )
    XCTAssertEqual(plan.modeledCategories, plan.requestedCategories)
    XCTAssertTrue(plan.blockedCategories.isEmpty)
    XCTAssertEqual(plan.featureSetCount, 27)
    XCTAssertEqual(plan.requiredAcknowledgementCount, 13)
    XCTAssertEqual(plan.internalFlashEraseTransactionCount, 7)
    XCTAssertEqual(plan.distinctInternalFlashPageCount, 4)
  }

  func testFunctionSettingsDryRunHasFixedCountsAndPageRisk() throws {
    let plan = try AK47FactoryResetPreflight.plan(
      target: exactTarget,
      selection: AK47FactoryResetSelection(categories: [.functionSettings])
    )

    XCTAssertEqual(plan.modeledCategories, [.functionSettings])
    XCTAssertEqual(plan.featureSetCount, 4)
    XCTAssertEqual(plan.requiredAcknowledgementCount, 3)
    XCTAssertEqual(plan.internalFlashEraseTransactionCount, 1)
    XCTAssertEqual(plan.distinctInternalFlashPageCount, 1)
  }

  func testPerKeyDryRunReportsBoundedCountsWithoutPayloadBytes() throws {
    let plan = try AK47FactoryResetPreflight.plan(
      target: exactTarget,
      selection: AK47FactoryResetSelection(categories: [.perKeyRGB])
    )

    XCTAssertEqual(plan.modeledCategories, [.perKeyRGB])
    XCTAssertEqual(plan.featureSetCount, 18)
    XCTAssertEqual(plan.requiredAcknowledgementCount, 7)
    XCTAssertEqual(plan.internalFlashEraseTransactionCount, 4)
    XCTAssertEqual(plan.distinctInternalFlashPageCount, 3)
  }

  func testOnboardDryRunReportsFixedCountsAndPageRisk() throws {
    let plan = try AK47FactoryResetPreflight.plan(
      target: exactTarget,
      selection: AK47FactoryResetSelection(categories: [.onboardLighting])
    )

    XCTAssertEqual(plan.modeledCategories, [.onboardLighting])
    XCTAssertEqual(plan.featureSetCount, 5)
    XCTAssertEqual(plan.requiredAcknowledgementCount, 3)
    XCTAssertEqual(plan.internalFlashEraseTransactionCount, 2)
    XCTAssertEqual(plan.distinctInternalFlashPageCount, 2)
  }

  func testFullAuditPlanNamesEveryCategoryWithoutACompleteDryRunShape() throws {
    let plan = try AK47FactoryResetPreflight.plan(
      target: exactTarget,
      selection: .allCategories
    )

    XCTAssertFalse(plan.hasCompleteDryRunShape)
    XCTAssertEqual(
      plan.blockedCategories,
      [
        AK47FactoryResetBlockedCategory(
          category: .baseKeymap,
          reason: .exactDefaultTableUnavailable
        ),
        AK47FactoryResetBlockedCategory(
          category: .functionKeymap,
          reason: .exactDefaultTableUnavailable
        ),
        AK47FactoryResetBlockedCategory(category: .macros, reason: .exactEncoderUnavailable),
        AK47FactoryResetBlockedCategory(category: .display, reason: .recoveryBoundaryUnavailable),
      ]
    )
  }

  func testEmptySelectionAndNonExactTargetFailClosed() {
    XCTAssertThrowsError(
      try AK47FactoryResetPreflight.plan(
        target: exactTarget,
        selection: AK47FactoryResetSelection(categories: [])
      )
    ) {
      XCTAssertEqual($0 as? AK47FactoryResetError, .emptySelection)
    }

    XCTAssertThrowsError(
      try AK47FactoryResetPreflight.plan(
        target: AK47WiredDeviceTarget(locationID: 1, versionNumber: 0x0116)
      )
    ) {
      XCTAssertEqual(
        $0 as? AK47DeviceWriteError,
        .invalidTarget("only the verified USB revision 0x0115 is enabled")
      )
    }
  }

}
