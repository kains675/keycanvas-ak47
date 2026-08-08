import AK47InspectorCore
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ProfileStoreStatus: Equatable {
  case ready
  case unsaved
  case saved(String)
  case failed(String)
}

@MainActor
final class LocalProfileStore: ObservableObject {
  @Published private(set) var profiles: [DeviceProfile]
  @Published var selectedID: String
  @Published private(set) var status: ProfileStoreStatus = .ready

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager

    let loaded = Self.loadProfiles(fileManager: fileManager)
    let initial = loaded.isEmpty ? [DeviceProfile.keyCanvasDraft(named: "Mac Starter")] : loaded
    self.profiles = initial
    self.selectedID = initial[0].identifier
  }

  var selectedProfile: DeviceProfile {
    profiles.first(where: { $0.identifier == selectedID }) ?? profiles[0]
  }

  var statusLabel: String {
    switch status {
    case .ready: "Local profile"
    case .unsaved: "Unsaved draft"
    case .saved(let filename): "Saved locally: \(filename)"
    case .failed(let message): "Profile error: \(message)"
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
    status = .unsaved
  }

  func renameSelected(to name: String) {
    guard let index = selectedIndex else { return }
    profiles[index].name = name
    status = .unsaved
  }

  func setKeyAssignment(_ action: KeyAction, position: Int, layer: Int = 0) {
    guard let index = selectedIndex else { return }
    profiles[index].keymap.assignments.removeAll {
      $0.layer == layer && $0.position == position
    }
    profiles[index].keymap.assignments.append(
      KeyAssignment(layer: layer, position: position, action: action)
    )
    status = .unsaved
  }

  func updateLighting(_ lighting: LightingProfile) {
    guard let index = selectedIndex else { return }
    profiles[index].lighting = lighting
    status = .unsaved
  }

  func replaceMacros(_ macros: [MacroDefinition]) {
    guard let index = selectedIndex else { return }
    profiles[index].macros = macros
    status = .unsaved
  }

  func updateTFT(_ tft: TFTProfile) {
    guard let index = selectedIndex else { return }
    profiles[index].tft = tft
    status = .unsaved
  }

  func updateSettings(_ settings: DeviceSettings) {
    guard let index = selectedIndex else { return }
    profiles[index].settings = settings
    status = .unsaved
  }

  func saveSelected() {
    do {
      let directory = try profileDirectory(createIfNeeded: true)
      let url = directory.appendingPathComponent("\(selectedID).json")
      let data = try ProfileJSONCodec.encode(selectedProfile)
      try data.write(to: url, options: .atomic)
      status = .saved(url.lastPathComponent)
    } catch {
      status = .failed(error.localizedDescription)
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
      status = .saved(url.lastPathComponent)
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private var selectedIndex: Int? {
    profiles.firstIndex(where: { $0.identifier == selectedID })
  }

  private func importProfile(from url: URL) {
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
      if profiles.contains(where: { $0.identifier == profile.identifier }) {
        profile.identifier = UUID().uuidString.lowercased()
        profile.name = String(profile.name.prefix(117)) + " (Imported)"
      }
      profiles.append(profile)
      selectedID = profile.identifier
      status = .unsaved
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func profileDirectory(createIfNeeded: Bool) throws -> URL {
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
    return directory
  }

  private func safeFilename(for name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let filtered = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
    let result = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? "KeyCanvas-Profile" : result
  }

  private static func loadProfiles(fileManager: FileManager) -> [DeviceProfile] {
    do {
      let base = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
      let directory = base.appendingPathComponent("KeyCanvas", isDirectory: true)
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

  var errorDescription: String? {
    switch self {
    case .invalidImportFile:
      "The selected profile must be a regular JSON file no larger than 2 MB."
    }
  }
}
