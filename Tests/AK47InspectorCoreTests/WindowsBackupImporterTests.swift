import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import XCTest

@testable import AK47InspectorCore
@testable import AK47StudioApp

final class WindowsBackupImporterTests: XCTestCase {
  func testImportsSyntheticProfilesAndPreservesLayerDelaysInGIF() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.execute(
      """
      INSERT INTO t_profile_data(profile, name, status) VALUES
        (1, 'Default', 0),
        (2, 'Gaming', 1);
      INSERT INTO t_config_data(profile, key, value) VALUES
        (2, 'sleep_time', '2'),
        (2, 'key_respondtime', '3'),
        (2, 'default_color1', '8331093');
      INSERT INTO t_light_data(
        profile, name, mode, brightness, speed, direction, colorful, colorindex,
        color_value, config_func, reserved, status
      ) VALUES (2, '529', 9, 5, 3, 0, 1, 0, 255, 51, 0, 1);
      INSERT INTO t_ledlayer_data(
        led_id, profile, type, name, frame_size, file_dir, first_file
      ) VALUES (5, 2, 0, 'synthetic-layer', 2, 'layer-1', '0.png');
      INSERT INTO t_ledframe_data(led_id, name, delay_time, frame_index, file_name) VALUES
        (5, '1.png', 130, 1, '1.png'),
        (5, '0.png', 70, 0, '0.png');
      """
    )
    try fixture.writePNG(directory: "layer-1", filename: "0.png", width: 240, height: 135)
    try fixture.writePNG(directory: "layer-1", filename: "1.png", width: 240, height: 135)
    let importedAt = Date(timeIntervalSince1970: 1_700_000_000)

    let result = try WindowsBackupImporter().importBackup(
      at: fixture.rootURL,
      importedAt: importedAt
    )

    XCTAssertEqual(result.profiles.map(\.name), ["Default", "Gaming"])
    XCTAssertEqual(result.activeProfileIdentifier, result.profiles[1].identifier)
    XCTAssertEqual(result.assets.count, 1)

    let gaming = result.profiles[1]
    XCTAssertEqual(gaming.importMetadata?.sourceKind, WindowsBackupImporter.sourceKind)
    XCTAssertEqual(gaming.importMetadata?.importedAt, importedAt)
    XCTAssertEqual(gaming.importMetadata?.sourceProfileWasActive, true)
    XCTAssertEqual(gaming.importMetadata?.rawConfiguration["sleep_time"], "2")
    XCTAssertEqual(gaming.importMetadata?.rawConfiguration["key_respondtime"], "3")
    XCTAssertEqual(gaming.importMetadata?.rawActiveLighting["brightness"], "5")
    XCTAssertEqual(gaming.lighting.effectIdentifier, "windows-raw-mode-9")
    XCTAssertEqual(gaming.lighting.brightnessPercent, 100)
    XCTAssertEqual(gaming.settings, DeviceSettings())

    let reference = try XCTUnwrap(gaming.tft.assets.first)
    XCTAssertEqual(gaming.tft.playlist, [reference.identifier])
    XCTAssertEqual(reference.width, 240)
    XCTAssertEqual(reference.height, 135)
    XCTAssertEqual(reference.frameCount, 2)
    XCTAssertEqual(reference.importMetadata?.sourceLayerIdentifier, 5)
    XCTAssertEqual(reference.importMetadata?.frameDelaysMilliseconds, [70, 130])
    XCTAssertTrue(reference.resourceName.hasPrefix("DisplayAssets/WindowsBackup/"))
    XCTAssertFalse(reference.resourceName.contains(fixture.rootURL.path))
    XCTAssertTrue(gaming.validationIssues().isEmpty)

    let gifSource = try XCTUnwrap(
      CGImageSourceCreateWithData(result.assets[0].data as CFData, nil)
    )
    XCTAssertEqual(CGImageSourceGetType(gifSource) as String?, UTType.gif.identifier)
    XCTAssertEqual(CGImageSourceGetCount(gifSource), 2)
    XCTAssertEqual(try gifDelay(at: 0, source: gifSource), 0.07, accuracy: 0.001)
    XCTAssertEqual(try gifDelay(at: 1, source: gifSource), 0.13, accuracy: 0.001)
  }

  func testRejectsParentTraversalFromLayerMetadata() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.addProfileAndLayer(
      directory: "../outside",
      width: 240,
      height: 135,
      writePNG: false
    )

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .unsafePath)
    }
  }

  func testRejectsSymlinkedLayerDirectory() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.addProfileAndLayer(
      directory: "layer-link", width: 240, height: 135, writePNG: false)
    let externalDirectory = fixture.containerURL.appendingPathComponent(
      "external", isDirectory: true)
    try FileManager.default.createDirectory(
      at: externalDirectory,
      withIntermediateDirectories: false
    )
    try fixture.writePNG(
      at: externalDirectory.appendingPathComponent("0.png"),
      width: 240,
      height: 135
    )
    let modelDirectory = fixture.modelDirectory
    try FileManager.default.createDirectory(
      at: modelDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: modelDirectory.appendingPathComponent("layer-link"),
      withDestinationURL: externalDirectory
    )

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .unsafePath)
    }
  }

  func testRejectsSymlinkedSelectedRoot() throws {
    let fixture = try SyntheticWindowsBackup()
    let aliasContainer = fixture.containerURL.appendingPathComponent("alias", isDirectory: true)
    try FileManager.default.createDirectory(at: aliasContainer, withIntermediateDirectories: false)
    let alias = aliasContainer.appendingPathComponent(
      "Archon AK47 Driver Files",
      isDirectory: true
    )
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.rootURL)

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: alias)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .unsafePath)
    }
  }

  func testRejectsSymlinkedDatabase() throws {
    let fixture = try SyntheticWindowsBackup()
    fixture.closeDatabase()
    let externalDatabase = fixture.containerURL.appendingPathComponent("external.db")
    try FileManager.default.moveItem(at: fixture.databaseURL, to: externalDatabase)
    try FileManager.default.createSymbolicLink(
      at: fixture.databaseURL,
      withDestinationURL: externalDatabase
    )

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .unsafePath)
    }
  }

  func testRejectsSymlinkedFrame() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.addProfileAndLayer(
      directory: "layer-1",
      width: 240,
      height: 135,
      writePNG: false
    )
    try FileManager.default.createDirectory(
      at: fixture.modelDirectory.appendingPathComponent("layer-1", isDirectory: true),
      withIntermediateDirectories: true
    )
    let externalFrame = fixture.containerURL.appendingPathComponent("external.png")
    try fixture.writePNG(at: externalFrame, width: 240, height: 135)
    try FileManager.default.createSymbolicLink(
      at: fixture.modelDirectory
        .appendingPathComponent("layer-1", isDirectory: true)
        .appendingPathComponent("0.png"),
      withDestinationURL: externalFrame
    )

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .unsafePath)
    }
  }

  func testRejectsFrameWithUnexpectedDimensions() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.addProfileAndLayer(directory: "layer-1", width: 2_049, height: 135)

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .invalidFrame)
    }
  }

  func testRejectsMoreThanBoundedProfileCount() throws {
    let fixture = try SyntheticWindowsBackup()
    for profile in 1...33 {
      try fixture.execute(
        "INSERT INTO t_profile_data(profile, name, status) VALUES "
          + "(\(profile), 'Profile \(profile)', 0);"
      )
    }

    XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .importLimitExceeded)
    }
  }

  func testRejectsSQLiteSidecarsBeforeImmutableRead() throws {
    let fixture = try SyntheticWindowsBackup()
    fixture.closeDatabase()

    for suffix in ["-wal", "-journal", "-shm"] {
      let sidecarURL = URL(fileURLWithPath: fixture.databaseURL.path + suffix)
      try Data("synthetic-sidecar".utf8).write(to: sidecarURL)
      XCTAssertThrowsError(try WindowsBackupImporter().importBackup(at: fixture.rootURL)) {
        error in
        XCTAssertEqual(error as? WindowsBackupImportError, .databaseSidecarPresent)
        XCTAssertTrue(error.localizedDescription.contains("Windows Archon AK47"))
      }
      try FileManager.default.removeItem(at: sidecarURL)
    }
  }

  func testPNGDecodeFailureReportsInvalidFrameInsteadOfPixelLimit() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.addProfileAndLayer(directory: "layer-1", width: 240, height: 135)
    let importer = WindowsBackupImporter(imageDecoder: { _ in nil })

    XCTAssertThrowsError(try importer.importBackup(at: fixture.rootURL)) { error in
      XCTAssertEqual(error as? WindowsBackupImportError, .invalidFrame)
    }
  }

  @MainActor
  func testJSONImportAlwaysRekeysTraversalIdentifierAndSavesInsideStore() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("keycanvas-profile-import-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let storageDirectory =
      temporaryDirectory
      .appendingPathComponent("nested", isDirectory: true)
      .appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    let sourceURL = temporaryDirectory.appendingPathComponent("external.keycanvas.json")
    let sourceProfile = DeviceProfile(identifier: "../../outside", name: "Imported")
    try ProfileJSONCodec.encode(sourceProfile).write(to: sourceURL)
    let escapedURL =
      storageDirectory
      .appendingPathComponent("../../outside.json")
      .standardizedFileURL
    let store = LocalProfileStore(storageDirectory: storageDirectory)

    store.importProfile(from: sourceURL)

    XCTAssertNotEqual(store.selectedID, sourceProfile.identifier)
    XCTAssertEqual(UUID(uuidString: store.selectedID)?.uuidString.lowercased(), store.selectedID)
    store.saveSelected()
    guard case .saved = store.status else {
      return XCTFail("expected the rekeyed profile to save")
    }
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: storageDirectory.appendingPathComponent("\(store.selectedID).json").path
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: escapedURL.path))
  }

  @MainActor
  func testSaveSelectedRejectsNonUUIDIdentifierLoadedFromLocalJSON() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("keycanvas-profile-save-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let storageDirectory = temporaryDirectory.appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    let unsafeProfile = DeviceProfile(identifier: "../escaped", name: "Unsafe local profile")
    try ProfileJSONCodec.encode(unsafeProfile).write(
      to: storageDirectory.appendingPathComponent("seed.json")
    )
    let escapedURL = storageDirectory.appendingPathComponent("../escaped.json").standardizedFileURL
    let store = LocalProfileStore(storageDirectory: storageDirectory)

    store.saveSelected()

    guard case .failed = store.status else {
      return XCTFail("expected a non-UUID identifier to be rejected")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: escapedURL.path))
  }

  @MainActor
  func testLocalStoreRollsBackAssetsWhenProfilePersistenceFails() throws {
    let fixture = try SyntheticWindowsBackup()
    try fixture.addProfileAndLayer(directory: "layer-1", width: 240, height: 135)
    let storageDirectory = fixture.containerURL.appendingPathComponent(
      "LocalStore",
      isDirectory: true
    )
    let assetDirectory =
      storageDirectory
      .appendingPathComponent("DisplayAssets", isDirectory: true)
      .appendingPathComponent("WindowsBackup", isDirectory: true)
    try FileManager.default.createDirectory(
      at: assetDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500],
      ofItemAtPath: storageDirectory.path
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: storageDirectory.path
      )
    }
    let store = LocalProfileStore(
      fileManager: .default,
      storageDirectory: storageDirectory
    )

    store.importWindowsBackup(from: fixture.rootURL)

    guard case .failed = store.status else {
      return XCTFail("expected a persistence failure")
    }
    XCTAssertEqual(store.profiles.count, 1)
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: assetDirectory.path).isEmpty
    )
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: storageDirectory.path)
        .filter { $0.hasSuffix(".json") }
        .isEmpty
    )
  }

  func testOptionalLocalBackupDryRunLeavesSourceInventoryUnchanged() throws {
    guard
      let path = ProcessInfo.processInfo.environment["KEYCANVAS_TEST_WINDOWS_BACKUP"],
      !path.isEmpty
    else {
      throw XCTSkip("Set KEYCANVAS_TEST_WINDOWS_BACKUP to run the private local-backup dry run.")
    }
    let rootURL = URL(fileURLWithPath: path, isDirectory: true)
    let before = try sourceInventory(at: rootURL)

    let result = try WindowsBackupImporter().importBackup(at: rootURL)

    XCTAssertEqual(result.profiles.count, 3)
    XCTAssertEqual(result.assets.count, 4)
    XCTAssertEqual(result.assets.reduce(0) { $0 + $1.reference.frameCount }, 95)
    XCTAssertEqual(result.activeProfileIdentifier, result.profiles[0].identifier)
    XCTAssertEqual(result.profiles[0].importMetadata?.sourceProfileWasActive, true)
    XCTAssertTrue(result.profiles.allSatisfy { $0.validationIssues().isEmpty })
    XCTAssertEqual(try sourceInventory(at: rootURL), before)
  }

  private func gifDelay(at index: Int, source: CGImageSource) throws -> Double {
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    )
    let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
    return try XCTUnwrap(
      (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
    )
  }

  private func sourceInventory(at rootURL: URL) throws -> [String: SourceFileSnapshot] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [
          .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ],
        options: [.skipsHiddenFiles]
      )
    else {
      throw FixtureError.inventory
    }

    var inventory: [String: SourceFileSnapshot] = [:]
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [
        .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
      ])
      if values.isRegularFile == true || values.isSymbolicLink == true {
        let relativePath = String(url.path.dropFirst(rootURL.path.count + 1))
        inventory[relativePath] = SourceFileSnapshot(
          byteCount: values.fileSize,
          modificationDate: values.contentModificationDate,
          isSymbolicLink: values.isSymbolicLink == true
        )
      }
    }
    return inventory
  }
}

private struct SourceFileSnapshot: Equatable {
  let byteCount: Int?
  let modificationDate: Date?
  let isSymbolicLink: Bool
}

private final class SyntheticWindowsBackup {
  let containerURL: URL
  let rootURL: URL
  let modelDirectory: URL
  let databaseURL: URL
  private var database: OpaquePointer?

  init() throws {
    containerURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "keycanvas-windows-import-tests-\(UUID().uuidString)", isDirectory: true)
    rootURL = containerURL.appendingPathComponent("Archon AK47 Driver Files", isDirectory: true)
    modelDirectory =
      rootURL
      .appendingPathComponent("led", isDirectory: true)
      .appendingPathComponent("Archon AK47", isDirectory: true)
    let databaseDirectory = rootURL.appendingPathComponent("db", isDirectory: true)
    try FileManager.default.createDirectory(
      at: databaseDirectory,
      withIntermediateDirectories: true
    )
    databaseURL = databaseDirectory.appendingPathComponent("Archon AK47_datav1.db")
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
      throw FixtureError.database
    }
    try execute(
      """
      CREATE TABLE t_profile_data(
        profile INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, status INTEGER, app TEXT, type INTEGER
      );
      CREATE TABLE t_config_data(
        config_id INTEGER PRIMARY KEY AUTOINCREMENT, profile INTEGER, key TEXT, value TEXT
      );
      CREATE TABLE t_light_data(
        light_id INTEGER PRIMARY KEY AUTOINCREMENT, profile INTEGER, name TEXT, mode INTEGER,
        brightness INTEGER, speed INTEGER, direction INTEGER, colorful INTEGER,
        colorindex INTEGER, color_value INTEGER, config_func INTEGER, reserved INTEGER,
        status INTEGER
      );
      CREATE TABLE t_ledlayer_data(
        led_id INTEGER PRIMARY KEY AUTOINCREMENT, profile INTEGER, type INTEGER, name TEXT,
        frame_size INTEGER, file_dir TEXT, first_file TEXT
      );
      CREATE TABLE t_ledframe_data(
        frame_id INTEGER PRIMARY KEY AUTOINCREMENT, led_id INTEGER, name TEXT,
        delay_time INTEGER, frame_index INTEGER, file_name TEXT
      );
      """
    )
  }

  deinit {
    closeDatabase()
    try? FileManager.default.removeItem(at: containerURL)
  }

  func closeDatabase() {
    if let database {
      sqlite3_close_v2(database)
      self.database = nil
    }
  }

  func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw FixtureError.database
    }
  }

  func addProfileAndLayer(
    directory: String,
    width: Int,
    height: Int,
    writePNG: Bool = true
  ) throws {
    try execute(
      """
      INSERT INTO t_profile_data(profile, name, status) VALUES (1, 'Synthetic', 1);
      INSERT INTO t_ledlayer_data(
        led_id, profile, type, name, frame_size, file_dir, first_file
      ) VALUES (1, 1, 0, 'synthetic-layer', 1, '\(directory)', '0.png');
      INSERT INTO t_ledframe_data(led_id, name, delay_time, frame_index, file_name)
        VALUES (1, '0.png', 100, 0, '0.png');
      """
    )
    if writePNG {
      try self.writePNG(directory: directory, filename: "0.png", width: width, height: height)
    }
  }

  func writePNG(
    directory: String,
    filename: String,
    width: Int,
    height: Int
  ) throws {
    let directoryURL = modelDirectory.appendingPathComponent(directory, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try writePNG(at: directoryURL.appendingPathComponent(filename), width: width, height: height)
  }

  func writePNG(at url: URL, width: Int, height: Int) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw FixtureError.image
    }
    context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw FixtureError.image
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FixtureError.image
    }
  }
}

private enum FixtureError: Error {
  case database
  case image
  case inventory
}
