import AK47InspectorCore
import AppKit
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

enum ProfileStoreStatus: Equatable {
  case ready
  case unsaved
  case saved(String)
  case imported(profileCount: Int, layerCount: Int)
  case failed(String)
}

enum LocalDisplayAssetLimits {
  static let maximumByteCount = 25 * 1_024 * 1_024
}

@MainActor
final class LocalProfileStore: ObservableObject {
  @Published private(set) var profiles: [DeviceProfile]
  @Published var selectedID: String {
    didSet {
      status = profileStatuses[selectedID] ?? .ready
    }
  }
  @Published private(set) var status: ProfileStoreStatus = .ready

  private let fileManager: FileManager
  private let storageDirectory: URL?
  private var profileStatuses: [String: ProfileStoreStatus] = [:]

  init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
    self.fileManager = fileManager
    self.storageDirectory = storageDirectory

    let loaded = Self.loadProfiles(fileManager: fileManager, storageDirectory: storageDirectory)
    let initial = loaded.isEmpty ? [DeviceProfile.keyCanvasDraft(named: "Mac Starter")] : loaded
    self.profiles = initial
    self.selectedID = initial[0].identifier
    self.profileStatuses = initial.reduce(into: [:]) { statuses, profile in
      statuses[profile.identifier] = .ready
    }
  }

  var selectedProfile: DeviceProfile {
    profiles.first(where: { $0.identifier == selectedID }) ?? profiles[0]
  }

  var statusLabel: String {
    statusLabel(in: .english)
  }

  func statusLabel(in language: AppLanguage) -> String {
    switch status {
    case .ready:
      studioText("로컬 프로필", "Local profile", language: language)
    case .unsaved:
      studioText("저장되지 않은 초안", "Unsaved draft", language: language)
    case .saved(let filename):
      studioText(
        "로컬에 저장됨: \(filename)",
        "Saved locally: \(filename)",
        language: language
      )
    case .imported(let profileCount, let layerCount):
      studioText(
        "Windows 백업 가져옴: 프로필 \(profileCount)개, 화면 레이어 \(layerCount)개",
        "Windows backup imported: \(profileCount) profiles, \(layerCount) screen layers",
        language: language
      )
    case .failed(let message):
      studioText(
        "프로필 오류: \(message)",
        "Profile error: \(message)",
        language: language
      )
    }
  }

  func newProfile() {
    let existingNames = Set(profiles.map(\.name))
    var index = profiles.count + 1
    var name = "Untitled \(index)"
    while existingNames.contains(name) {
      index += 1
      name = "Untitled \(index)"
    }

    let profile = DeviceProfile.keyCanvasDraft(named: name)
    profiles.append(profile)
    selectedID = profile.identifier
    setStatus(.unsaved, for: profile.identifier)
  }

  func renameSelected(to name: String) {
    guard let index = selectedIndex else { return }
    profiles[index].name = name
    setSelectedStatus(.unsaved)
  }

  func setKeyAssignment(_ action: KeyAction, position: Int, layer: Int = 0) {
    guard let index = selectedIndex else { return }
    profiles[index].keymap.assignments.removeAll {
      $0.layer == layer && $0.position == position
    }
    profiles[index].keymap.assignments.append(
      KeyAssignment(layer: layer, position: position, action: action)
    )
    setSelectedStatus(.unsaved)
  }

  func updateLighting(_ lighting: LightingProfile) {
    guard let index = selectedIndex else { return }
    profiles[index].lighting = lighting
    setSelectedStatus(.unsaved)
  }

  func replaceMacros(_ macros: [MacroDefinition]) {
    guard let index = selectedIndex else { return }
    profiles[index].macros = macros
    setSelectedStatus(.unsaved)
  }

  func updateTFT(_ tft: TFTProfile) {
    guard let index = selectedIndex else { return }
    profiles[index].tft = tft
    setSelectedStatus(.unsaved)
  }

  func copyDisplayAsset(
    from sourceURL: URL,
    preferredFilenameExtension: String,
    pixelWidth: Int,
    pixelHeight: Int,
    frameCount: Int
  ) throws -> DisplayAssetReference {
    guard let index = selectedIndex else {
      throw ProfileStoreError.missingProfile
    }

    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
      let byteCount = values.fileSize,
      byteCount <= LocalDisplayAssetLimits.maximumByteCount
    else {
      throw ProfileStoreError.invalidDisplayAsset
    }
    guard (1...8_192).contains(pixelWidth), (1...8_192).contains(pixelHeight),
      (1...10_000).contains(frameCount)
    else {
      throw ProfileStoreError.invalidDisplayAsset
    }

    let filenameExtension = preferredFilenameExtension.lowercased()
    guard ["png", "jpg", "jpeg", "gif"].contains(filenameExtension) else {
      throw ProfileStoreError.invalidDisplayAsset
    }

    let identifier = UUID().uuidString.lowercased()
    let sourceStem = safeFilename(for: sourceURL.deletingPathExtension().lastPathComponent)
    let stem = String(sourceStem.prefix(48))
    let filename = "\(stem)-\(identifier.prefix(8)).\(filenameExtension)"
    let resourceName = "DisplayAssets/\(filename)"
    let destinationURL = try resolvedResourceURL(
      resourceName: resourceName,
      createParentDirectory: true
    )
    try fileManager.copyItem(at: sourceURL, to: destinationURL)

    let reference = DisplayAssetReference(
      identifier: identifier,
      resourceName: resourceName,
      width: pixelWidth,
      height: pixelHeight,
      frameCount: frameCount
    )
    profiles[index].tft.enabled = true
    profiles[index].tft.canvasWidth = 240
    profiles[index].tft.canvasHeight = 135
    profiles[index].tft.assets.append(reference)
    profiles[index].tft.playlist.removeAll { $0 == reference.identifier }
    profiles[index].tft.playlist.insert(reference.identifier, at: 0)
    setSelectedStatus(.unsaved)
    return reference
  }

  func displayAssetURL(for reference: DisplayAssetReference) -> URL? {
    try? resolvedResourceURL(resourceName: reference.resourceName)
  }

  func exportDisplayAsset(_ reference: DisplayAssetReference, to destinationURL: URL) throws {
    let sourceURL = try resolvedResourceURL(resourceName: reference.resourceName)
    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
      let byteCount = values.fileSize,
      byteCount <= LocalDisplayAssetLimits.maximumByteCount
    else {
      throw ProfileStoreError.missingDisplayAsset
    }

    let data = try Data(contentsOf: sourceURL)
    try data.write(to: destinationURL, options: .atomic)
  }

  func updateSettings(_ settings: DeviceSettings) {
    guard let index = selectedIndex else { return }
    profiles[index].settings = settings
    setSelectedStatus(.unsaved)
  }

  func saveSelected() {
    let identifier = selectedID
    do {
      guard let index = selectedIndex else {
        throw ProfileStoreError.missingProfile
      }
      let directory = try profileDirectory(createIfNeeded: true)
      let profile = profiles[index]
      guard profile.identifier == identifier else {
        throw ProfileStoreError.invalidProfileIdentifier
      }
      let url = try profileFileURL(for: profile.identifier, inside: directory)
      let data = try ProfileJSONCodec.encode(profile)
      try data.write(to: url, options: .atomic)
      setStatus(.saved(url.lastPathComponent), for: identifier)
    } catch {
      setStatus(.failed(error.localizedDescription), for: identifier)
    }
  }

  func presentImportPanel() {
    let panel = NSOpenPanel()
    panel.title = "Import a KeyCanvas Profile"
    panel.prompt = "Import"
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, let url = panel.url else { return }
    importProfile(from: url)
  }

  func presentWindowsBackupImportPanel(language: AppLanguage) {
    let panel = NSOpenPanel()
    panel.title = studioText(
      "Archon AK47 Windows 백업 가져오기",
      "Import an Archon AK47 Windows Backup",
      language: language
    )
    panel.message = studioText(
      "‘Archon AK47 Driver Files’ 폴더를 선택하세요.",
      "Select the folder named ‘Archon AK47 Driver Files’.",
      language: language
    )
    panel.prompt = studioText("백업 가져오기", "Import Backup", language: language)
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.resolvesAliases = false

    guard panel.runModal() == .OK, let url = panel.url else { return }
    importWindowsBackup(from: url)
  }

  func presentExportPanel() {
    let panel = NSSavePanel()
    panel.title = "Export a KeyCanvas Profile"
    panel.prompt = "Export"
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = safeFilename(for: selectedProfile.name) + ".keycanvas.json"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let data = try ProfileJSONCodec.encode(selectedProfile)
      try data.write(to: url, options: .atomic)
      setSelectedStatus(.saved(url.lastPathComponent))
    } catch {
      setSelectedStatus(.failed(error.localizedDescription))
    }
  }

  private var selectedIndex: Int? {
    profiles.firstIndex(where: { $0.identifier == selectedID })
  }

  func importProfile(from url: URL) {
    do {
      let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard resourceValues.isRegularFile == true,
        let byteCount = resourceValues.fileSize,
        byteCount <= 2_000_000
      else {
        throw ProfileStoreError.invalidImportFile
      }

      let data = try Data(contentsOf: url)
      var profile = try ProfileJSONCodec.decode(data)
      profile.identifier = freshProfileIdentifier()
      profiles.append(profile)
      selectedID = profile.identifier
      setStatus(.unsaved, for: profile.identifier)
    } catch {
      setSelectedStatus(.failed(error.localizedDescription))
    }
  }

  func importWindowsBackup(from url: URL) {
    var createdURLs: [URL] = []
    do {
      let result = try WindowsBackupImporter(fileManager: fileManager).importBackup(at: url)
      guard !result.profiles.isEmpty,
        result.profiles.allSatisfy({ profile in
          !profiles.contains(where: { $0.identifier == profile.identifier })
        })
      else {
        throw ProfileStoreError.invalidWindowsBackup
      }

      let importedReferenceIDs = Set(
        result.profiles.flatMap { $0.tft.assets.map(\.identifier) }
      )
      guard importedReferenceIDs.count == result.assets.count,
        Set(result.assets.map(\.reference.identifier)) == importedReferenceIDs
      else {
        throw ProfileStoreError.invalidWindowsBackup
      }

      for asset in result.assets {
        guard asset.data.count <= LocalDisplayAssetLimits.maximumByteCount else {
          throw ProfileStoreError.invalidWindowsBackup
        }
        let destinationURL = try resolvedResourceURL(
          resourceName: asset.reference.resourceName,
          createParentDirectory: true
        )
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
          throw ProfileStoreError.invalidWindowsBackup
        }
        try writeAtomicallyWithoutOverwriting(asset.data, to: destinationURL)
        createdURLs.append(destinationURL)
      }

      let directory = try profileDirectory(createIfNeeded: true)
      for profile in result.profiles {
        let profileURL = try profileFileURL(for: profile.identifier, inside: directory)
        guard !fileManager.fileExists(atPath: profileURL.path) else {
          throw ProfileStoreError.invalidWindowsBackup
        }
        let data = try ProfileJSONCodec.encode(profile)
        try writeAtomicallyWithoutOverwriting(data, to: profileURL)
        createdURLs.append(profileURL)
      }

      profiles.append(contentsOf: result.profiles)
      selectedID = result.activeProfileIdentifier ?? result.profiles[0].identifier
      for profile in result.profiles {
        setStatus(.saved("\(profile.identifier).json"), for: profile.identifier)
      }
      setSelectedStatus(
        .imported(
          profileCount: result.profiles.count,
          layerCount: result.assets.count
        )
      )
    } catch {
      // Rollback is best-effort and only targets files published by this import attempt.
      for createdURL in createdURLs.reversed() {
        try? fileManager.removeItem(at: createdURL)
      }
      setSelectedStatus(.failed(error.localizedDescription))
    }
  }

  private func setSelectedStatus(_ newStatus: ProfileStoreStatus) {
    setStatus(newStatus, for: selectedID)
  }

  private func setStatus(_ newStatus: ProfileStoreStatus, for identifier: String) {
    profileStatuses[identifier] = newStatus
    if selectedID == identifier {
      status = newStatus
    }
  }

  private func profileDirectory(createIfNeeded: Bool) throws -> URL {
    if let storageDirectory {
      if createIfNeeded {
        try fileManager.createDirectory(
          at: storageDirectory,
          withIntermediateDirectories: true
        )
      }
      if fileManager.fileExists(atPath: storageDirectory.path) {
        let values = try storageDirectory.resourceValues(forKeys: [
          .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
          throw ProfileStoreError.unsafeLocalStorage
        }
      }
      return storageDirectory.standardizedFileURL
    }
    let base = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: createIfNeeded
    )
    let directory = base.appendingPathComponent("KeyCanvas", isDirectory: true)
    if createIfNeeded {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    if fileManager.fileExists(atPath: directory.path) {
      let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw ProfileStoreError.unsafeLocalStorage
      }
    }
    return directory
  }

  private func writeAtomicallyWithoutOverwriting(_ data: Data, to destinationURL: URL) throws {
    let temporaryURL = destinationURL.deletingLastPathComponent()
      .appendingPathComponent(".keycanvas-import-\(UUID().uuidString).tmp")
    let descriptor = Darwin.open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      mode_t(S_IRUSR | S_IWUSR)
    )
    guard descriptor >= 0 else {
      throw ProfileStoreError.localWriteFailed
    }
    var temporaryExists = true
    defer {
      Darwin.close(descriptor)
      if temporaryExists {
        Darwin.unlink(temporaryURL.path)
      }
    }

    try data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        guard let baseAddress = buffer.baseAddress else {
          throw ProfileStoreError.localWriteFailed
        }
        let written = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          buffer.count - offset
        )
        if written < 0, errno == EINTR {
          continue
        }
        guard written > 0 else {
          throw ProfileStoreError.localWriteFailed
        }
        offset += written
      }
    }
    guard Darwin.fsync(descriptor) == 0,
      Darwin.link(temporaryURL.path, destinationURL.path) == 0
    else {
      throw ProfileStoreError.localWriteFailed
    }
    guard Darwin.unlink(temporaryURL.path) == 0 else {
      try? fileManager.removeItem(at: destinationURL)
      throw ProfileStoreError.localWriteFailed
    }
    temporaryExists = false
  }

  private func profileFileURL(for identifier: String, inside directory: URL) throws -> URL {
    let normalizedIdentifier = identifier.lowercased()
    guard let uuid = UUID(uuidString: identifier),
      uuid.uuidString.lowercased() == normalizedIdentifier,
      identifier == normalizedIdentifier
    else {
      throw ProfileStoreError.invalidProfileIdentifier
    }

    let base = directory.standardizedFileURL
    let candidate = base.appendingPathComponent("\(normalizedIdentifier).json").standardizedFileURL
    let basePrefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
    guard candidate.deletingLastPathComponent().path == base.path,
      candidate.path.hasPrefix(basePrefix)
    else {
      throw ProfileStoreError.invalidProfileIdentifier
    }
    return candidate
  }

  private func freshProfileIdentifier() -> String {
    let existing = Set(profiles.map(\.identifier))
    var identifier: String
    repeat {
      identifier = UUID().uuidString.lowercased()
    } while existing.contains(identifier)
    return identifier
  }

  private func resolvedResourceURL(
    resourceName: String,
    createParentDirectory: Bool = false
  ) throws -> URL {
    let base = try profileDirectory(createIfNeeded: createParentDirectory).standardizedFileURL
    let components = resourceName.replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/", omittingEmptySubsequences: false)
      .map(String.init)
    guard !components.isEmpty,
      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") })
    else {
      throw ProfileStoreError.invalidDisplayAsset
    }

    var parent = base
    for component in components.dropLast() {
      parent.appendPathComponent(component, isDirectory: true)
      if fileManager.fileExists(atPath: parent.path) {
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
          throw ProfileStoreError.unsafeLocalStorage
        }
      } else if createParentDirectory {
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
      }
    }

    let candidate = parent.appendingPathComponent(components.last!).standardizedFileURL
    let basePrefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
    let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
    guard candidate.path.hasPrefix(basePrefix),
      resolvedParent.path == base.path || resolvedParent.path.hasPrefix(basePrefix)
    else {
      throw ProfileStoreError.invalidDisplayAsset
    }
    if fileManager.fileExists(atPath: candidate.path) {
      let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard values.isSymbolicLink != true else {
        throw ProfileStoreError.unsafeLocalStorage
      }
    }
    return candidate
  }

  private func safeFilename(for name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let filtered = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
    let result = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? "KeyCanvas-Profile" : result
  }

  private static func loadProfiles(
    fileManager: FileManager,
    storageDirectory: URL?
  ) -> [DeviceProfile] {
    do {
      let directory: URL
      if let storageDirectory {
        directory = storageDirectory
      } else {
        let base = try fileManager.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: false
        )
        directory = base.appendingPathComponent("KeyCanvas", isDirectory: true)
      }
      guard fileManager.fileExists(atPath: directory.path) else { return [] }

      return try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
      .filter { $0.pathExtension.lowercased() == "json" }
      .sorted {
        let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
        let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
        return (left ?? .distantPast) > (right ?? .distantPast)
      }
      .compactMap { url in
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
          values.isRegularFile == true,
          let size = values.fileSize,
          size <= 2_000_000,
          let data = try? Data(contentsOf: url)
        else {
          return nil
        }
        return try? ProfileJSONCodec.decode(data)
      }
    } catch {
      return []
    }
  }
}

extension DeviceProfile {
  fileprivate static func keyCanvasDraft(named name: String) -> DeviceProfile {
    DeviceProfile(
      identifier: UUID().uuidString.lowercased(),
      name: name,
      lighting: LightingProfile(
        enabled: true,
        effectIdentifier: "flow-preview",
        brightnessPercent: 72,
        speedPercent: 38,
        baseColor: RGBColor(red: 51, green: 199, blue: 166),
        accentColor: RGBColor(red: 153, green: 107, blue: 245)
      ),
      tft: TFTProfile(
        enabled: false,
        canvasWidth: 240,
        canvasHeight: 135,
        frameRate: 30,
        themeIdentifier: "orbit",
        message: "HELLO, MAC",
        accentColor: RGBColor(red: 51, green: 199, blue: 166),
        showsClock: true,
        showsBattery: true
      )
    )
  }
}

private enum ProfileStoreError: LocalizedError {
  case invalidImportFile
  case invalidWindowsBackup
  case invalidDisplayAsset
  case missingDisplayAsset
  case missingProfile
  case localWriteFailed
  case invalidProfileIdentifier
  case unsafeLocalStorage

  var errorDescription: String? {
    switch self {
    case .invalidImportFile:
      "The selected profile must be a regular JSON file no larger than 2 MB."
    case .invalidWindowsBackup:
      "The selected folder is not a safe, supported Archon AK47 Windows backup."
    case .invalidDisplayAsset:
      "The selected display asset is not a supported local image."
    case .missingDisplayAsset:
      "The local display asset is unavailable."
    case .missingProfile:
      "No local profile is selected."
    case .localWriteFailed:
      "The imported file could not be published safely to local storage."
    case .invalidProfileIdentifier:
      "The local profile identifier is not a safe UUID. Import it again to create a safe copy."
    case .unsafeLocalStorage:
      "The KeyCanvas storage folder contains an unsafe symbolic link."
    }
  }
}
