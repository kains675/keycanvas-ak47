import Foundation
import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class LocalProfileStoreTests: XCTestCase {
  @MainActor
  func testDisplayAssetStorageWritesTheExactInspectedSnapshot() throws {
    let storageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("keycanvas-asset-snapshot-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: storageDirectory) }
    let store = LocalProfileStore(storageDirectory: storageDirectory)
    let inspectedSnapshot = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])

    let reference = try store.storeDisplayAsset(
      snapshotData: inspectedSnapshot,
      originalFilename: "chosen.gif",
      preferredFilenameExtension: "gif",
      pixelWidth: 4,
      pixelHeight: 4,
      frameCount: 1
    )

    let storedURL = try XCTUnwrap(store.displayAssetURL(for: reference))
    XCTAssertEqual(try Data(contentsOf: storedURL), inspectedSnapshot)
    XCTAssertEqual(store.selectedProfile.tft.assets.last, reference)
  }

  @MainActor
  func testSavingSelectedProfileDoesNotClearAnotherProfilesUnsavedStatus() throws {
    let storageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("keycanvas-profile-status-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: storageDirectory) }

    let store = LocalProfileStore(storageDirectory: storageDirectory)
    let firstIdentifier = store.selectedID
    store.renameSelected(to: "Unsaved A")
    XCTAssertEqual(store.status, .unsaved)

    store.newProfile()
    let secondIdentifier = store.selectedID
    store.renameSelected(to: "Saved B")
    store.saveSelected()

    guard case .saved = store.status else {
      return XCTFail("expected the selected second profile to be saved")
    }
    let secondURL = storageDirectory.appendingPathComponent("\(secondIdentifier).json")
    let savedSecondProfile = try ProfileJSONCodec.decode(Data(contentsOf: secondURL))
    XCTAssertEqual(savedSecondProfile.identifier, secondIdentifier)
    XCTAssertEqual(savedSecondProfile.name, "Saved B")
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: storageDirectory.appendingPathComponent("\(firstIdentifier).json").path
      )
    )

    store.selectedID = firstIdentifier
    XCTAssertEqual(store.selectedProfile.name, "Unsaved A")
    XCTAssertEqual(store.status, .unsaved)

    store.selectedID = secondIdentifier
    guard case .saved = store.status else {
      return XCTFail("expected the second profile to retain its saved status")
    }
  }
}
