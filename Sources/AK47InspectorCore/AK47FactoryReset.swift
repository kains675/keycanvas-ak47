import Foundation

/// Bounded groups that a user may expect a keyboard factory-default operation
/// to cover. Availability is intentionally explicit: a category is never
/// silently omitted from a requested plan.
public enum AK47FactoryResetCategory: String, CaseIterable, Hashable, Sendable {
  case functionSettings
  case perKeyRGB
  case onboardLighting
  case baseKeymap
  case functionKeymap
  case macros
  case display
}

public enum AK47FactoryResetBlockReason: String, Equatable, Sendable {
  /// The complete model-specific default table is not independently proven.
  case exactDefaultTableUnavailable
  /// The persisted format is not complete enough to construct a safe default.
  case exactEncoderUnavailable
  /// A complete backup, partition bound, or tested recovery path is unavailable.
  case recoveryBoundaryUnavailable
}

public enum AK47FactoryResetCategoryAvailability: Equatable, Sendable {
  case modeledOffline
  case blocked(AK47FactoryResetBlockReason)
}

public struct AK47FactoryResetCategoryStatus: Equatable, Sendable {
  public let category: AK47FactoryResetCategory
  public let availability: AK47FactoryResetCategoryAvailability

  public init(
    category: AK47FactoryResetCategory,
    availability: AK47FactoryResetCategoryAvailability
  ) {
    self.category = category
    self.availability = availability
  }
}

public struct AK47FactoryResetSelection: Equatable, Sendable {
  public let categories: Set<AK47FactoryResetCategory>

  public init(categories: Set<AK47FactoryResetCategory>) {
    self.categories = categories
  }

  /// The only categories whose fixed host-side shapes are complete enough for
  /// offline modeling. This does not enable a live device operation.
  public static let verifiedSubset = Self(
    categories: [.functionSettings, .perKeyRGB, .onboardLighting]
  )

  /// Useful for a dry-run audit. Unmodeled categories remain visible instead of
  /// being silently skipped.
  public static let allCategories = Self(categories: Set(AK47FactoryResetCategory.allCases))
}

public struct AK47FactoryResetBlockedCategory: Equatable, Sendable {
  public let category: AK47FactoryResetCategory
  public let reason: AK47FactoryResetBlockReason
}

public struct AK47FactoryResetPlanItem: Equatable, Sendable {
  public let category: AK47FactoryResetCategory
  public let featureSetCount: Int
  public let requiredAcknowledgementCount: Int
  /// Known internal-flash erase/program transactions initiated by this category.
  public let internalFlashEraseTransactionCount: Int
}

/// A precomputed, immutable dry-run plan. Report payloads remain
/// package-internal and no public adapter submits this plan to a device.
public struct AK47FactoryResetPlan: Equatable, Sendable {
  public let target: AK47WiredDeviceTarget
  public let requestedCategories: [AK47FactoryResetCategory]
  public let items: [AK47FactoryResetPlanItem]
  public let blockedCategories: [AK47FactoryResetBlockedCategory]

  public var modeledCategories: [AK47FactoryResetCategory] {
    items.map(\.category)
  }

  public var featureSetCount: Int {
    items.reduce(0) { $0 + $1.featureSetCount }
  }

  public var requiredAcknowledgementCount: Int {
    items.reduce(0) { $0 + $1.requiredAcknowledgementCount }
  }

  public var internalFlashEraseTransactionCount: Int {
    items.reduce(0) { $0 + $1.internalFlashEraseTransactionCount }
  }

  /// Distinct known internal-flash pages touched by this exact category set.
  public var distinctInternalFlashPageCount: Int {
    var pages: Set<AK47FactoryResetInternalPage> = []
    for item in items {
      switch item.category {
      case .functionSettings:
        pages.insert(.functionSettings)
      case .perKeyRGB:
        pages.formUnion([.globalPersistence, .onboardLighting, .perKeyRGB])
      case .onboardLighting:
        pages.formUnion([.globalPersistence, .onboardLighting])
      case .baseKeymap, .functionKeymap, .macros, .display:
        break
      }
    }
    return pages.count
  }

  /// True only when every requested category has a complete offline model.
  /// This does not authorize or imply a live HID execution path.
  public var hasCompleteDryRunShape: Bool {
    !items.isEmpty && blockedCategories.isEmpty
  }
}

public enum AK47FactoryResetError: Error, Equatable, LocalizedError, Sendable {
  case emptySelection
  case invalidPlan

  public var errorDescription: String? {
    switch self {
    case .emptySelection:
      "factory-default reset requires at least one category"
    case .invalidPlan:
      "factory-default reset plan failed its integrity preflight"
    }
  }
}

public enum AK47FactoryResetPreflight {
  public static let categoryCatalog: [AK47FactoryResetCategoryStatus] = [
    AK47FactoryResetCategoryStatus(category: .functionSettings, availability: .modeledOffline),
    AK47FactoryResetCategoryStatus(category: .perKeyRGB, availability: .modeledOffline),
    AK47FactoryResetCategoryStatus(category: .onboardLighting, availability: .modeledOffline),
    AK47FactoryResetCategoryStatus(
      category: .baseKeymap,
      availability: .blocked(.exactDefaultTableUnavailable)
    ),
    AK47FactoryResetCategoryStatus(
      category: .functionKeymap,
      availability: .blocked(.exactDefaultTableUnavailable)
    ),
    AK47FactoryResetCategoryStatus(
      category: .macros,
      availability: .blocked(.exactEncoderUnavailable)
    ),
    AK47FactoryResetCategoryStatus(
      category: .display,
      availability: .blocked(.recoveryBoundaryUnavailable)
    ),
  ]

  /// Creates a pure dry-run plan. This performs no HID discovery or I/O.
  public static func plan(
    target: AK47WiredDeviceTarget,
    selection: AK47FactoryResetSelection = .verifiedSubset
  ) throws -> AK47FactoryResetPlan {
    try target.validate()
    guard !selection.categories.isEmpty else {
      throw AK47FactoryResetError.emptySelection
    }

    let requested = selection.categories.sorted(by: categoryOrder)
    var items: [AK47FactoryResetPlanItem] = []
    var blocked: [AK47FactoryResetBlockedCategory] = []

    for category in requested {
      switch availability(for: category) {
      case .blocked(let reason):
        blocked.append(AK47FactoryResetBlockedCategory(category: category, reason: reason))
      case .modeledOffline:
        let counts = modeledCounts(for: category)
        items.append(
          AK47FactoryResetPlanItem(
            category: category,
            featureSetCount: counts.featureSets,
            requiredAcknowledgementCount: counts.acknowledgements,
            internalFlashEraseTransactionCount: eraseTransactionCount(for: category)
          )
        )
      }
    }

    let plan = AK47FactoryResetPlan(
      target: target,
      requestedCategories: requested,
      items: items,
      blockedCategories: blocked
    )
    try validateFixedShape(plan)
    return plan
  }

  public static func availability(
    for category: AK47FactoryResetCategory
  ) -> AK47FactoryResetCategoryAvailability {
    categoryCatalog.first(where: { $0.category == category })?.availability
      ?? .blocked(.exactEncoderUnavailable)
  }

  private static func modeledCounts(
    for category: AK47FactoryResetCategory
  ) -> (featureSets: Int, acknowledgements: Int) {
    switch category {
    case .functionSettings: (4, 3)
    case .perKeyRGB: (18, 7)
    case .onboardLighting: (5, 3)
    case .baseKeymap, .functionKeymap, .macros, .display:
      (0, 0)
    }
  }

  /// Keeps the offline report deterministic and mirrors the observed host-side
  /// category order without exposing payload bytes.
  private static func categoryOrder(
    _ lhs: AK47FactoryResetCategory,
    _ rhs: AK47FactoryResetCategory
  ) -> Bool {
    orderIndex(lhs) < orderIndex(rhs)
  }

  private static func orderIndex(_ category: AK47FactoryResetCategory) -> Int {
    switch category {
    case .functionSettings: 0
    case .perKeyRGB: 1
    case .onboardLighting: 2
    case .baseKeymap: 3
    case .functionKeymap: 4
    case .macros: 5
    case .display: 6
    }
  }

  private static func validateFixedShape(_ plan: AK47FactoryResetPlan) throws {
    let expectedSetCounts: [AK47FactoryResetCategory: Int] = [
      .functionSettings: 4,
      .perKeyRGB: 18,
      .onboardLighting: 5,
    ]
    let expectedAcknowledgements: [AK47FactoryResetCategory: Int] = [
      .functionSettings: 3,
      .perKeyRGB: 7,
      .onboardLighting: 3,
    ]
    let expectedEraseTransactions: [AK47FactoryResetCategory: Int] = [
      .functionSettings: 1,
      .perKeyRGB: 4,
      .onboardLighting: 2,
    ]

    for item in plan.items {
      guard item.featureSetCount == expectedSetCounts[item.category],
        item.requiredAcknowledgementCount == expectedAcknowledgements[item.category],
        item.internalFlashEraseTransactionCount == expectedEraseTransactions[item.category]
      else {
        throw AK47FactoryResetError.invalidPlan
      }
    }
  }

  private static func eraseTransactionCount(
    for category: AK47FactoryResetCategory
  ) -> Int {
    switch category {
    case .functionSettings: 1
    case .perKeyRGB: 4
    case .onboardLighting: 2
    case .baseKeymap, .functionKeymap, .macros, .display: 0
    }
  }
}

private enum AK47FactoryResetInternalPage: Hashable {
  case globalPersistence
  case functionSettings
  case onboardLighting
  case perKeyRGB
}
