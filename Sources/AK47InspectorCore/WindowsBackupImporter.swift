import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers

public struct WindowsBackupImportedAsset: Equatable, Sendable {
  public let reference: DisplayAssetReference
  public let data: Data

  public init(reference: DisplayAssetReference, data: Data) {
    self.reference = reference
    self.data = data
  }
}

public struct WindowsBackupImportResult: Equatable, Sendable {
  public let profiles: [DeviceProfile]
  public let activeProfileIdentifier: String?
  public let assets: [WindowsBackupImportedAsset]

  public init(
    profiles: [DeviceProfile],
    activeProfileIdentifier: String?,
    assets: [WindowsBackupImportedAsset]
  ) {
    self.profiles = profiles
    self.activeProfileIdentifier = activeProfileIdentifier
    self.assets = assets
  }
}

public enum WindowsBackupImportError: Error, Equatable, LocalizedError, Sendable {
  case invalidFolder
  case missingDatabase
  case unsafePath
  case databaseTooLarge
  case databaseSidecarPresent
  case invalidDatabase
  case unsupportedSchema(String)
  case invalidRecord(String)
  case importLimitExceeded
  case invalidFrame
  case imageEncodingFailed

  public var errorDescription: String? {
    switch self {
    case .invalidFolder:
      "Select the folder named ‘Archon AK47 Driver Files’."
    case .missingDatabase:
      "The selected folder does not contain db/Archon AK47_datav1.db."
    case .unsafePath:
      "The backup contains a symbolic link or an unsafe relative path."
    case .databaseTooLarge:
      "The Windows backup database exceeds the import size limit."
    case .databaseSidecarPresent:
      "Windows 백업 DB가 아직 사용 중입니다. Windows Archon AK47 프로그램을 닫고 잠시 기다린 뒤 다시 가져오세요. / The Windows backup database is still in use. Close the Windows Archon AK47 app, wait for its SQLite sidecar files to disappear, and import again."
    case .invalidDatabase:
      "The Windows backup database is not a readable SQLite database."
    case .unsupportedSchema(let table):
      "The Windows backup has an unsupported \(table) schema."
    case .invalidRecord(let table):
      "The Windows backup contains an invalid \(table) record."
    case .importLimitExceeded:
      "The Windows backup exceeds the safe profile, layer, frame, or byte limit."
    case .invalidFrame:
      "A referenced screen frame is missing or is not a supported bounded PNG."
    case .imageEncodingFailed:
      "A Windows screen layer could not be preserved as an animated GIF."
    }
  }
}

public struct WindowsBackupImporter {
  public static let sourceKind = "archon-ak47-windows-backup"

  private enum Limits {
    static let databaseBytes = 4 * 1_024 * 1_024
    static let profileCount = 32
    static let configurationRowsPerProfile = 64
    static let lightingRowsPerProfile = 2
    static let layerCountPerProfile = 32
    static let totalLayerCount = 64
    static let framesPerLayer = 140
    static let totalFrameCount = 1_024
    static let frameBytes = 2 * 1_024 * 1_024
    static let totalFrameBytes = 64 * 1_024 * 1_024
    static let frameDimension = 2_048
    static let framePixels = 2_000_000
    static let totalDecodedPixels = 32_000_000
    static let encodedAssetBytes = 25 * 1_024 * 1_024
  }

  private static let configurationKeys = [
    "version",
    "keyboard_layout",
    "fn_layer",
    "fn_switch",
    "lightmode",
    "sleep_time",
    "key_respondtime",
    "sleep_light",
    "userlight",
    "customlight",
    "customlight_run",
    "gamemode",
    "disable_alttab",
    "disable_altf4",
    "disable_win",
    "default_color1",
    "default_color2",
    "default_color3",
    "default_color4",
    "default_color5",
    "default_color6",
    "default_color7",
    "default_color8",
  ]

  private static let requiredColumns: [String: Set<String>] = [
    "t_profile_data": ["profile", "name", "status"],
    "t_config_data": ["config_id", "profile", "key", "value"],
    "t_light_data": [
      "light_id", "profile", "name", "mode", "brightness", "speed", "direction",
      "colorful", "colorindex", "color_value", "config_func", "reserved", "status",
    ],
    "t_ledlayer_data": [
      "led_id", "profile", "type", "name", "frame_size", "file_dir", "first_file",
    ],
    "t_ledframe_data": [
      "frame_id", "led_id", "name", "delay_time", "frame_index", "file_name",
    ],
  ]

  private let fileManager: FileManager
  private let imageDecoder: (CGImageSource) -> CGImage?

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.imageDecoder = { source in
      CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
  }

  init(
    fileManager: FileManager = .default,
    imageDecoder: @escaping (CGImageSource) -> CGImage?
  ) {
    self.fileManager = fileManager
    self.imageDecoder = imageDecoder
  }

  public func importBackup(
    at selectedFolderURL: URL,
    importedAt: Date = Date()
  ) throws -> WindowsBackupImportResult {
    let rootURL = try validatedRoot(selectedFolderURL)
    let databaseURL = try validatedDatabaseURL(inside: rootURL)
    try rejectDatabaseSidecars(for: databaseURL)
    let database = try ReadOnlySQLiteDatabase(url: databaseURL)
    try validateSchema(database)

    let sourceProfiles = try readProfiles(database)
    var profiles: [DeviceProfile] = []
    var assets: [WindowsBackupImportedAsset] = []
    var activeProfileIdentifier: String?
    var totalLayerCount = 0
    var totalFrameCount = 0
    var totalFrameBytes = 0
    var totalDecodedPixels = 0

    for sourceProfile in sourceProfiles {
      let identifier = UUID().uuidString.lowercased()
      let configuration = try readConfiguration(
        database,
        profileIdentifier: sourceProfile.identifier
      )
      let activeLighting = try readActiveLighting(
        database,
        profileIdentifier: sourceProfile.identifier
      )
      let sourceLayers = try readLayers(
        database,
        profileIdentifier: sourceProfile.identifier
      )

      totalLayerCount += sourceLayers.count
      guard totalLayerCount <= Limits.totalLayerCount else {
        throw WindowsBackupImportError.importLimitExceeded
      }

      var references: [DisplayAssetReference] = []
      for (layerIndex, layer) in sourceLayers.enumerated() {
        let frames = try readFrames(database, layer: layer)
        totalFrameCount += frames.count
        guard totalFrameCount <= Limits.totalFrameCount else {
          throw WindowsBackupImportError.importLimitExceeded
        }

        let frameImages = try readFrameImages(
          frames,
          for: layer,
          rootURL: rootURL,
          totalFrameBytes: &totalFrameBytes,
          totalDecodedPixels: &totalDecodedPixels
        )
        let gifData = try encodeGIF(frameImages)
        guard gifData.count <= Limits.encodedAssetBytes else {
          throw WindowsBackupImportError.importLimitExceeded
        }

        let assetIdentifier = UUID().uuidString.lowercased()
        let resourceName =
          "DisplayAssets/WindowsBackup/\(identifier.prefix(12))-layer-\(layerIndex + 1)-"
          + "\(assetIdentifier.prefix(8)).gif"
        let reference = DisplayAssetReference(
          identifier: assetIdentifier,
          resourceName: resourceName,
          width: frameImages[0].width,
          height: frameImages[0].height,
          frameCount: frames.count,
          importMetadata: DisplayAssetImportMetadata(
            sourceKind: Self.sourceKind,
            sourceLayerIdentifier: layer.identifier,
            rawLayerType: layer.rawType,
            frameDelaysMilliseconds: frames.map(\.delayMilliseconds)
          )
        )
        references.append(reference)
        assets.append(WindowsBackupImportedAsset(reference: reference, data: gifData))
      }

      let profile = DeviceProfile(
        identifier: identifier,
        name: sourceProfile.name,
        lighting: convertedLighting(activeLighting),
        tft: TFTProfile(
          enabled: !references.isEmpty,
          canvasWidth: 240,
          canvasHeight: 135,
          frameRate: 30,
          assets: references,
          playlist: references.map(\.identifier)
        ),
        settings: DeviceSettings(),
        importMetadata: ProfileImportMetadata(
          sourceKind: Self.sourceKind,
          importedAt: importedAt,
          sourceProfileWasActive: sourceProfile.isActive,
          rawConfiguration: configuration,
          rawActiveLighting: activeLighting?.rawValues ?? [:]
        )
      )
      _ = try profile.validated()
      profiles.append(profile)
      if sourceProfile.isActive {
        guard activeProfileIdentifier == nil else {
          throw WindowsBackupImportError.invalidRecord("t_profile_data")
        }
        activeProfileIdentifier = identifier
      }
    }

    return WindowsBackupImportResult(
      profiles: profiles,
      activeProfileIdentifier: activeProfileIdentifier,
      assets: assets
    )
  }

  private func validatedRoot(_ selectedFolderURL: URL) throws -> URL {
    let url = selectedFolderURL.standardizedFileURL
    guard url.lastPathComponent == "Archon AK47 Driver Files" else {
      throw WindowsBackupImportError.invalidFolder
    }
    let values = try resourceValues(for: url)
    guard values.isSymbolicLink != true else {
      throw WindowsBackupImportError.unsafePath
    }
    guard values.isDirectory == true else {
      throw WindowsBackupImportError.invalidFolder
    }
    return try canonicalURL(url)
  }

  private func validatedDatabaseURL(inside rootURL: URL) throws -> URL {
    let databaseDirectory = rootURL.appendingPathComponent("db", isDirectory: true)
    guard fileManager.fileExists(atPath: databaseDirectory.path) else {
      throw WindowsBackupImportError.missingDatabase
    }
    _ = try validatedDirectory(databaseDirectory, inside: rootURL)

    let databaseURL = databaseDirectory.appendingPathComponent("Archon AK47_datav1.db")
    guard fileManager.fileExists(atPath: databaseURL.path) else {
      throw WindowsBackupImportError.missingDatabase
    }
    let values = try resourceValues(for: databaseURL)
    guard values.isSymbolicLink != true else {
      throw WindowsBackupImportError.unsafePath
    }
    guard values.isRegularFile == true else {
      throw WindowsBackupImportError.missingDatabase
    }
    guard let byteCount = values.fileSize, byteCount <= Limits.databaseBytes else {
      throw WindowsBackupImportError.databaseTooLarge
    }
    try requireInsideRoot(databaseURL, rootURL: rootURL)
    return databaseURL
  }

  private func rejectDatabaseSidecars(for databaseURL: URL) throws {
    for suffix in ["-wal", "-journal", "-shm"] {
      let sidecarPath = databaseURL.path + suffix
      var fileStatus = stat()
      if lstat(sidecarPath, &fileStatus) == 0 {
        throw WindowsBackupImportError.databaseSidecarPresent
      }
      guard errno == ENOENT else {
        throw WindowsBackupImportError.invalidDatabase
      }
    }
  }

  private func validateSchema(_ database: ReadOnlySQLiteDatabase) throws {
    for table in Self.requiredColumns.keys.sorted() {
      let typeRows = try database.query(
        "SELECT type FROM sqlite_schema WHERE name = ? COLLATE BINARY LIMIT 2",
        bindings: [.text(table)]
      )
      guard typeRows.count == 1, try typeRows[0].requiredText(at: 0) == "table" else {
        throw WindowsBackupImportError.unsupportedSchema(table)
      }

      let columnRows = try database.query(
        "SELECT name FROM pragma_table_info(?) LIMIT 65",
        bindings: [.text(table)]
      )
      guard columnRows.count <= 64 else {
        throw WindowsBackupImportError.unsupportedSchema(table)
      }
      let columns = try Set(columnRows.map { try $0.requiredText(at: 0) })
      guard let required = Self.requiredColumns[table], required.isSubset(of: columns) else {
        throw WindowsBackupImportError.unsupportedSchema(table)
      }
    }
  }

  private func readProfiles(_ database: ReadOnlySQLiteDatabase) throws -> [SourceProfile] {
    let rows = try database.query(
      """
      SELECT profile, name, status
      FROM t_profile_data
      ORDER BY profile
      LIMIT \(Limits.profileCount + 1)
      """
    )
    guard !rows.isEmpty, rows.count <= Limits.profileCount else {
      throw WindowsBackupImportError.importLimitExceeded
    }

    var identifiers: Set<Int> = []
    var activeCount = 0
    return try rows.map { row in
      let identifier = try boundedInteger(row, at: 0, range: 1...1_000_000)
      guard identifiers.insert(identifier).inserted else {
        throw WindowsBackupImportError.invalidRecord("t_profile_data")
      }
      let name = try row.requiredText(at: 1).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, name.count <= 128 else {
        throw WindowsBackupImportError.invalidRecord("t_profile_data")
      }
      let status = try boundedInteger(row, at: 2, range: 0...1)
      if status == 1 {
        activeCount += 1
        guard activeCount <= 1 else {
          throw WindowsBackupImportError.invalidRecord("t_profile_data")
        }
      }
      return SourceProfile(identifier: identifier, name: name, isActive: status == 1)
    }
  }

  private func readConfiguration(
    _ database: ReadOnlySQLiteDatabase,
    profileIdentifier: Int
  ) throws -> [String: String] {
    let placeholders = Self.configurationKeys.map { _ in "?" }.joined(separator: ", ")
    var bindings: [SQLiteBinding] = [.integer(Int64(profileIdentifier))]
    bindings.append(contentsOf: Self.configurationKeys.map(SQLiteBinding.text))
    let rows = try database.query(
      """
      SELECT key, value
      FROM t_config_data
      WHERE profile = ? AND key IN (\(placeholders))
      ORDER BY config_id
      LIMIT \(Limits.configurationRowsPerProfile + 1)
      """,
      bindings: bindings
    )
    guard rows.count <= Limits.configurationRowsPerProfile else {
      throw WindowsBackupImportError.importLimitExceeded
    }

    let allowed = Set(Self.configurationKeys)
    var result: [String: String] = [:]
    for row in rows {
      let key = try row.requiredText(at: 0)
      let value = try row.requiredText(at: 1)
      guard allowed.contains(key), key.count <= 64, value.count <= 256, result[key] == nil else {
        throw WindowsBackupImportError.invalidRecord("t_config_data")
      }
      result[key] = value
    }
    return result
  }

  private func readActiveLighting(
    _ database: ReadOnlySQLiteDatabase,
    profileIdentifier: Int
  ) throws -> SourceLighting? {
    let rows = try database.query(
      """
      SELECT name, mode, brightness, speed, direction, colorful, colorindex,
             color_value, config_func, reserved, status
      FROM t_light_data
      WHERE profile = ? AND status = 1
      ORDER BY light_id
      LIMIT \(Limits.lightingRowsPerProfile)
      """,
      bindings: [.integer(Int64(profileIdentifier))]
    )
    guard rows.count <= 1 else {
      throw WindowsBackupImportError.invalidRecord("t_light_data")
    }
    guard let row = rows.first else { return nil }

    let name = try row.requiredText(at: 0)
    guard name.count <= 128 else {
      throw WindowsBackupImportError.invalidRecord("t_light_data")
    }
    let fields = [
      "mode", "brightness", "speed", "direction", "colorful", "colorindex", "color_value",
      "config_func", "reserved", "status",
    ]
    var rawValues = ["name": name]
    for (column, field) in fields.enumerated() {
      let value = try boundedInteger(
        row,
        at: Int32(column + 1),
        range: -16_777_216...16_777_216
      )
      rawValues[field] = String(value)
    }
    guard let modeValue = rawValues["mode"], let mode = Int(modeValue) else {
      throw WindowsBackupImportError.invalidRecord("t_light_data")
    }
    return SourceLighting(mode: mode, rawValues: rawValues)
  }

  private func readLayers(
    _ database: ReadOnlySQLiteDatabase,
    profileIdentifier: Int
  ) throws -> [SourceLayer] {
    let rows = try database.query(
      """
      SELECT led_id, type, name, frame_size, file_dir, first_file
      FROM t_ledlayer_data
      WHERE profile = ?
      ORDER BY led_id
      LIMIT \(Limits.layerCountPerProfile + 1)
      """,
      bindings: [.integer(Int64(profileIdentifier))]
    )
    guard rows.count <= Limits.layerCountPerProfile else {
      throw WindowsBackupImportError.importLimitExceeded
    }

    var identifiers: Set<Int> = []
    return try rows.map { row in
      let identifier = try boundedInteger(row, at: 0, range: 1...1_000_000)
      guard identifiers.insert(identifier).inserted else {
        throw WindowsBackupImportError.invalidRecord("t_ledlayer_data")
      }
      let rawType = try boundedInteger(row, at: 1, range: -1_000_000...1_000_000)
      let name = try row.requiredText(at: 2)
      let frameCount = try boundedInteger(row, at: 3, range: 1...Limits.framesPerLayer)
      let directoryName = try row.requiredText(at: 4)
      let firstFilename = try row.requiredText(at: 5)
      guard name.count <= 128,
        isSafePathComponent(directoryName),
        isSafePathComponent(firstFilename)
      else {
        throw WindowsBackupImportError.unsafePath
      }
      return SourceLayer(
        identifier: identifier,
        rawType: rawType,
        frameCount: frameCount,
        directoryName: directoryName,
        firstFilename: firstFilename
      )
    }
  }

  private func readFrames(
    _ database: ReadOnlySQLiteDatabase,
    layer: SourceLayer
  ) throws -> [SourceFrame] {
    let rows = try database.query(
      """
      SELECT name, delay_time, frame_index, file_name
      FROM t_ledframe_data
      WHERE led_id = ?
      ORDER BY frame_index, frame_id
      LIMIT \(Limits.framesPerLayer + 1)
      """,
      bindings: [.integer(Int64(layer.identifier))]
    )
    guard rows.count == layer.frameCount, rows.count <= Limits.framesPerLayer else {
      throw WindowsBackupImportError.invalidRecord("t_ledframe_data")
    }

    var filenames: Set<String> = []
    let frames = try rows.enumerated().map { expectedIndex, row in
      let name = try row.requiredText(at: 0)
      let delay = try boundedInteger(row, at: 1, range: 1...60_000)
      let frameIndex = try boundedInteger(row, at: 2, range: 0..<Limits.framesPerLayer)
      let filename = try row.requiredText(at: 3)
      guard frameIndex == expectedIndex,
        name == filename,
        isSafePathComponent(name),
        isSafePathComponent(filename),
        filenames.insert(filename).inserted
      else {
        throw WindowsBackupImportError.invalidRecord("t_ledframe_data")
      }
      return SourceFrame(filename: filename, delayMilliseconds: delay)
    }
    guard frames.first?.filename == layer.firstFilename else {
      throw WindowsBackupImportError.invalidRecord("t_ledlayer_data")
    }
    return frames
  }

  private func readFrameImages(
    _ frames: [SourceFrame],
    for layer: SourceLayer,
    rootURL: URL,
    totalFrameBytes: inout Int,
    totalDecodedPixels: inout Int
  ) throws -> [FrameImage] {
    let ledRoot = rootURL.appendingPathComponent("led", isDirectory: true)
    let modelRoot = ledRoot.appendingPathComponent("Archon AK47", isDirectory: true)
    let layerRoot = modelRoot.appendingPathComponent(layer.directoryName, isDirectory: true)
    _ = try validatedDirectory(ledRoot, inside: rootURL)
    _ = try validatedDirectory(modelRoot, inside: rootURL)
    _ = try validatedDirectory(layerRoot, inside: rootURL)

    var expectedDimensions: (width: Int, height: Int)?
    return try frames.map { frame in
      let frameURL = layerRoot.appendingPathComponent(frame.filename)
      try requireInsideRoot(frameURL, rootURL: rootURL)
      let values = try resourceValues(for: frameURL)
      guard values.isSymbolicLink != true else {
        throw WindowsBackupImportError.unsafePath
      }
      guard values.isRegularFile == true,
        let byteCount = values.fileSize,
        byteCount > 0,
        byteCount <= Limits.frameBytes
      else {
        throw WindowsBackupImportError.invalidFrame
      }
      totalFrameBytes += byteCount
      guard totalFrameBytes <= Limits.totalFrameBytes else {
        throw WindowsBackupImportError.importLimitExceeded
      }

      let data = try Data(contentsOf: frameURL, options: .mappedIfSafe)
      guard data.count == byteCount,
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetCount(imageSource) == 1,
        CGImageSourceGetType(imageSource) as String? == UTType.png.identifier,
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
          as? [CFString: Any],
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
        (1...Limits.frameDimension).contains(width),
        (1...Limits.frameDimension).contains(height),
        width * height <= Limits.framePixels
      else {
        throw WindowsBackupImportError.invalidFrame
      }
      if let expectedDimensions {
        guard expectedDimensions.width == width, expectedDimensions.height == height else {
          throw WindowsBackupImportError.invalidFrame
        }
      } else {
        expectedDimensions = (width, height)
      }
      totalDecodedPixels += width * height
      guard totalDecodedPixels <= Limits.totalDecodedPixels else {
        throw WindowsBackupImportError.importLimitExceeded
      }
      guard let image = imageDecoder(imageSource) else {
        throw WindowsBackupImportError.invalidFrame
      }
      return FrameImage(
        image: image,
        width: width,
        height: height,
        delayMilliseconds: frame.delayMilliseconds
      )
    }
  }

  private func encodeGIF(_ frames: [FrameImage]) throws -> Data {
    guard !frames.isEmpty else {
      throw WindowsBackupImportError.imageEncodingFailed
    }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        UTType.gif.identifier as CFString,
        frames.count,
        nil
      )
    else {
      throw WindowsBackupImportError.imageEncodingFailed
    }

    CGImageDestinationSetProperties(
      destination,
      [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFLoopCount: 0
        ]
      ] as CFDictionary
    )
    for frame in frames {
      let delay = Double(frame.delayMilliseconds) / 1_000
      let properties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFDelayTime: delay,
          kCGImagePropertyGIFUnclampedDelayTime: delay,
        ]
      ]
      CGImageDestinationAddImage(destination, frame.image, properties as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else {
      throw WindowsBackupImportError.imageEncodingFailed
    }
    return data as Data
  }

  private func convertedLighting(_ lighting: SourceLighting?) -> LightingProfile {
    guard let lighting else {
      return LightingProfile(
        enabled: false,
        effectIdentifier: "windows-backup-no-active-lighting",
        brightnessPercent: 100,
        speedPercent: 50
      )
    }
    return LightingProfile(
      enabled: true,
      effectIdentifier: "windows-raw-mode-\(lighting.mode)",
      brightnessPercent: 100,
      speedPercent: 50
    )
  }

  private func validatedDirectory(_ url: URL, inside rootURL: URL) throws -> URL {
    try requireInsideRoot(url, rootURL: rootURL)
    let values = try resourceValues(for: url)
    guard values.isSymbolicLink != true else {
      throw WindowsBackupImportError.unsafePath
    }
    guard values.isDirectory == true else {
      throw WindowsBackupImportError.invalidFrame
    }
    return url
  }

  private func requireInsideRoot(_ candidateURL: URL, rootURL: URL) throws {
    let root = try canonicalURL(rootURL)
    let candidate = try canonicalURL(candidateURL)
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(prefix) else {
      throw WindowsBackupImportError.unsafePath
    }
  }

  private func canonicalURL(_ url: URL) throws -> URL {
    guard let pointer = realpath(url.path, nil) else {
      throw WindowsBackupImportError.unsafePath
    }
    defer { free(pointer) }
    return URL(fileURLWithPath: String(cString: pointer))
  }

  private func resourceValues(for url: URL) throws -> URLResourceValues {
    do {
      return try url.resourceValues(forKeys: [
        .fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
      ])
    } catch {
      throw WindowsBackupImportError.invalidFrame
    }
  }

  private func isSafePathComponent(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 128, value != ".", value != ".." else {
      return false
    }
    return !value.contains("/") && !value.contains("\\") && !value.contains(":")
  }

  private func boundedInteger<R: RangeExpression>(
    _ row: SQLiteRow,
    at index: Int32,
    range: R
  ) throws -> Int where R.Bound == Int {
    let value = try row.requiredInteger(at: index)
    guard let integer = Int(exactly: value), range.contains(integer) else {
      throw WindowsBackupImportError.invalidDatabase
    }
    return integer
  }
}

private struct SourceProfile {
  let identifier: Int
  let name: String
  let isActive: Bool
}

private struct SourceLighting {
  let mode: Int
  let rawValues: [String: String]
}

private struct SourceLayer {
  let identifier: Int
  let rawType: Int
  let frameCount: Int
  let directoryName: String
  let firstFilename: String
}

private struct SourceFrame {
  let filename: String
  let delayMilliseconds: Int
}

private struct FrameImage {
  let image: CGImage
  let width: Int
  let height: Int
  let delayMilliseconds: Int
}

private enum SQLiteBinding {
  case integer(Int64)
  case text(String)
}

private struct SQLiteRow {
  let values: [SQLiteValue]

  func requiredInteger(at index: Int32) throws -> Int64 {
    guard values.indices.contains(Int(index)), case .integer(let value) = values[Int(index)] else {
      throw WindowsBackupImportError.invalidDatabase
    }
    return value
  }

  func requiredText(at index: Int32) throws -> String {
    guard values.indices.contains(Int(index)), case .text(let value) = values[Int(index)] else {
      throw WindowsBackupImportError.invalidDatabase
    }
    return value
  }
}

private enum SQLiteValue {
  case integer(Int64)
  case text(String)
  case null
}

private final class ReadOnlySQLiteDatabase {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    let uri = url.absoluteString + "?mode=ro&immutable=1"
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_URI
    guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, handle != nil else {
      if let handle {
        sqlite3_close_v2(handle)
      }
      handle = nil
      throw WindowsBackupImportError.invalidDatabase
    }
    sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 2 * 1_024 * 1_024)
    sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 8_192)
    sqlite3_limit(handle, SQLITE_LIMIT_COLUMN, 64)
    sqlite3_limit(handle, SQLITE_LIMIT_EXPR_DEPTH, 64)
    sqlite3_busy_timeout(handle, 250)
    let pragmaResult = sqlite3_exec(
      handle,
      "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; PRAGMA temp_store=MEMORY;",
      nil,
      nil,
      nil
    )
    guard pragmaResult == SQLITE_OK else {
      if let handle {
        sqlite3_close_v2(handle)
      }
      self.handle = nil
      throw WindowsBackupImportError.invalidDatabase
    }
  }

  deinit {
    if let handle {
      sqlite3_close_v2(handle)
    }
  }

  func query(
    _ sql: String,
    bindings: [SQLiteBinding] = []
  ) throws -> [SQLiteRow] {
    guard let handle else {
      throw WindowsBackupImportError.invalidDatabase
    }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        == SQLITE_OK,
      let statement
    else {
      throw WindowsBackupImportError.invalidDatabase
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_bind_parameter_count(statement) == Int32(bindings.count) else {
      throw WindowsBackupImportError.invalidDatabase
    }
    for (offset, binding) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      switch binding {
      case .integer(let value):
        result = sqlite3_bind_int64(statement, index, value)
      case .text(let value):
        result = value.withCString { pointer in
          sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
        }
      }
      guard result == SQLITE_OK else {
        throw WindowsBackupImportError.invalidDatabase
      }
    }

    var rows: [SQLiteRow] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW:
        let columnCount = sqlite3_column_count(statement)
        guard columnCount <= 64 else {
          throw WindowsBackupImportError.invalidDatabase
        }
        var values: [SQLiteValue] = []
        values.reserveCapacity(Int(columnCount))
        for index in 0..<columnCount {
          switch sqlite3_column_type(statement, index) {
          case SQLITE_INTEGER:
            values.append(.integer(sqlite3_column_int64(statement, index)))
          case SQLITE_TEXT:
            let byteCount = sqlite3_column_bytes(statement, index)
            guard byteCount >= 0, byteCount <= 4_096,
              let pointer = sqlite3_column_text(statement, index)
            else {
              throw WindowsBackupImportError.invalidDatabase
            }
            let buffer = UnsafeBufferPointer(start: pointer, count: Int(byteCount))
            guard let value = String(bytes: buffer, encoding: .utf8) else {
              throw WindowsBackupImportError.invalidDatabase
            }
            values.append(.text(value))
          case SQLITE_NULL:
            values.append(.null)
          default:
            throw WindowsBackupImportError.invalidDatabase
          }
        }
        rows.append(SQLiteRow(values: values))
      case SQLITE_DONE:
        return rows
      default:
        throw WindowsBackupImportError.invalidDatabase
      }
    }
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
