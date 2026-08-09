import AK47InspectorCore
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct DisplayComposerView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var profileStore: LocalProfileStore
  @State private var theme = "Orbit"
  @State private var accent = StudioPalette.mint
  @State private var showClock = true
  @State private var showBattery = true
  @State private var note = "HELLO, MAC"
  @State private var savedLocally = false
  @State private var selectedAssetID: String?
  @State private var assetPreview: NSImage?
  @State private var assetMessage: String?
  @State private var assetMessageIsError = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("240 × 135 시안", "240 × 135 study", language: language),
          title: studioText("디스플레이", "Display", language: language),
          detail: studioText(
            "내장 화면을 위한 구성을 미리 그려 봅니다. 이미지를 업로드하거나 장치에 쓰지 않습니다.",
            "Sketch a composition for the built-in screen. No image is uploaded or written to the device.",
            language: language
          )
        )

        HStack(alignment: .top, spacing: 20) {
          displayPreview
            .frame(maxWidth: .infinity)
          displayControls
            .frame(width: 300)
        }

        assetLibrary

        HStack(spacing: 14) {
          DisplayPreset(
            name: "Orbit", colors: [StudioPalette.ink, StudioPalette.mint], selection: $theme)
          DisplayPreset(
            name: "Horizon", colors: [StudioPalette.blue, StudioPalette.coral], selection: $theme)
          DisplayPreset(name: "Mono", colors: [.black, .gray], selection: $theme)
        }

        DemoNotice()
      }
      .padding(28)
      .frame(maxWidth: 1060)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in loadProfile() }
    .onChange(of: theme) { _ in savedLocally = false }
    .onChange(of: accent) { _ in savedLocally = false }
    .onChange(of: showClock) { _ in savedLocally = false }
    .onChange(of: showBattery) { _ in savedLocally = false }
    .onChange(of: selectedAssetID) { _ in loadAssetPreview() }
    .onChange(of: note) { newValue in
      if newValue.count > 128 {
        note = String(newValue.prefix(128))
      }
      savedLocally = false
    }
  }

  private var displayPreview: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(studioText("화면 미리보기", "Screen preview", language: language))
          .font(.headline)
        Spacer()
        StatusPill(
          label: savedLocally
            ? studioText("로컬 저장됨", "Saved locally", language: language)
            : studioText("렌더링만", "Render only", language: language),
          symbol: savedLocally ? "checkmark.circle" : "eye",
          tint: StudioPalette.mint
        )
      }

      previewCanvas
        .aspectRatio(240 / 135, contentMode: .fit)
        .overlay {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12))
        }
        .shadow(color: StudioPalette.ink.opacity(0.20), radius: 18, y: 8)

      HStack {
        Text("240 × 135 px")
        Spacer()
        if let selectedAsset {
          Text(
            "\(selectedAsset.width) × \(selectedAsset.height) · \(selectedAsset.frameCount) "
              + studioText("프레임", "frames", language: language)
          )
        } else {
          Text(studioText("정적 SwiftUI 시안", "Static SwiftUI study", language: language))
        }
      }
      .font(.caption.monospaced())
      .foregroundStyle(.secondary)
    }
    .studioPanel()
  }

  @ViewBuilder
  private var previewCanvas: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(StudioPalette.ink)

      if let assetPreview {
        Image(nsImage: assetPreview)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .padding(8)

        VStack {
          Spacer()
          HStack {
            Label(
              studioText("로컬 복사본 · 첫 프레임", "Local copy · first frame", language: language),
              systemImage: "photo"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.58), in: Capsule())
            Spacer()
          }
          .padding(12)
        }
      } else {
        LinearGradient(
          colors: previewColors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .opacity(0.72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        Circle()
          .stroke(accent.opacity(0.48), lineWidth: 18)
          .frame(width: 138, height: 138)
          .offset(x: 145, y: -48)

        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 7) {
            KeyCanvasMark(size: 34)
            Text(note.isEmpty ? "KEYCANVAS" : note.uppercased())
              .font(.system(size: 21, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(studioText("로컬 화면 시안", "LOCAL SCREEN STUDY", language: language))
              .font(.caption2.weight(.semibold))
              .tracking(1.1)
              .foregroundStyle(.white.opacity(0.64))
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 5) {
            if showClock {
              Text("10:47")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.white)
            }
            if showBattery {
              Label("82%", systemImage: "battery.75")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            }
          }
        }
        .padding(24)
      }
    }
  }

  private var assets: [DisplayAssetReference] {
    profileStore.selectedProfile.tft.assets
  }

  private var selectedAsset: DisplayAssetReference? {
    guard let selectedAssetID else { return nil }
    return assets.first(where: { $0.identifier == selectedAssetID })
  }

  private var assetLibrary: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("로컬 이미지 보관함", "Local image library", language: language))
            .font(.headline)
          Text(
            studioText(
              "PNG, JPEG, GIF를 앱 전용 폴더에 복사하고 프로필 재생 목록에 연결합니다.",
              "Copy PNG, JPEG, or GIF files into app storage and link them to the profile playlist.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button(action: importDisplayAsset) {
          Label(studioText("이미지 가져오기…", "Import image…", language: language), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
      }

      if assets.isEmpty {
        HStack(spacing: 12) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text(
            studioText(
              "아직 로컬 이미지가 없습니다. 원본 파일은 변경하지 않습니다.",
              "No local images yet. The source file is never modified.",
              language: language
            )
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(assets, id: \.identifier) { asset in
              DisplayAssetCard(
                asset: asset,
                playlistPosition: playlistPosition(for: asset.identifier),
                isSelected: asset.identifier == selectedAssetID
              ) {
                selectedAssetID = asset.identifier
                assetMessage = nil
              }
              .frame(width: 220)
            }
          }
          .padding(.vertical, 2)
        }
      }

      if let selectedAsset {
        Divider()
        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 5) {
            Text(selectedAsset.resourceName)
              .font(.caption.monospaced())
              .lineLimit(1)
              .truncationMode(.middle)
              .textSelection(.enabled)
            Label(
              compatibilityLabel(for: selectedAsset),
              systemImage: compatibilitySymbol(for: selectedAsset)
            )
            .font(.caption)
            .foregroundStyle(compatibilityTint(for: selectedAsset))
          }
          Spacer()
          Button(action: exportSelectedAsset) {
            Label(
              studioText("복사본 내보내기…", "Export copy…", language: language),
              systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.bordered)
          .disabled(profileStore.displayAssetURL(for: selectedAsset) == nil)
        }
      }

      if let assetMessage {
        Label(
          assetMessage,
          systemImage: assetMessageIsError ? "exclamationmark.triangle" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(assetMessageIsError ? StudioPalette.coral : StudioPalette.mint)
      }

      Label(
        studioText(
          "장치 연결이나 HID report 전송은 수행하지 않습니다.",
          "No device connection or HID report transfer is performed.",
          language: language
        ),
        systemImage: "lock.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .studioPanel()
  }

  private var displayControls: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(studioText("구성 요소", "Composition", language: language))
        .font(.headline)
      TextField(studioText("짧은 문구", "Short message", language: language), text: $note)
        .textFieldStyle(.roundedBorder)
      ColorPicker(studioText("강조 색", "Accent", language: language), selection: $accent)
      Toggle(studioText("시계 표시", "Show clock", language: language), isOn: $showClock)
      Toggle(studioText("배터리 예시 표시", "Show sample battery", language: language), isOn: $showBattery)
      Divider()
      Label(
        studioText(
          "이미지는 로컬 복사본으로만 사용되며 키보드 전송은 비활성 상태입니다.",
          "Images are used only as local copies; keyboard transfer remains disabled.",
          language: language
        ),
        systemImage: "lock"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Button(action: saveProfile) {
        Label(
          studioText("프로필에 저장", "Save to profile", language: language),
          systemImage: "square.and.arrow.down"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.blue)
      Spacer(minLength: 0)
    }
    .frame(minHeight: 315, alignment: .topLeading)
    .studioPanel()
  }

  private var previewColors: [Color] {
    switch theme {
    case "Horizon": [StudioPalette.blue, StudioPalette.coral, StudioPalette.ink]
    case "Mono": [.black, .gray.opacity(0.6), .black]
    default:
      [StudioPalette.ink, StudioPalette.violet.opacity(0.75), StudioPalette.mint.opacity(0.6)]
    }
  }

  private var currentTFTDraft: TFTProfile {
    let current = profileStore.selectedProfile.tft
    return TFTProfile(
      enabled: current.enabled,
      canvasWidth: 240,
      canvasHeight: 135,
      frameRate: current.frameRate,
      assets: current.assets,
      playlist: current.playlist,
      themeIdentifier: theme.lowercased(),
      message: note,
      accentColor: accent.profileRGBColor,
      showsClock: showClock,
      showsBattery: showBattery
    )
  }

  private func importDisplayAsset() {
    let panel = NSOpenPanel()
    panel.title = studioText("로컬 디스플레이 이미지 선택", "Choose a local display image", language: language)
    panel.prompt = studioText("가져오기", "Import", language: language)
    panel.allowedContentTypes = [.png, .jpeg, .gif]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
    let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if accessedSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let inspection = try DisplayAssetInspection.inspect(sourceURL)
      profileStore.updateTFT(currentTFTDraft)
      let reference = try profileStore.copyDisplayAsset(
        from: sourceURL,
        preferredFilenameExtension: inspection.preferredFilenameExtension,
        pixelWidth: inspection.pixelWidth,
        pixelHeight: inspection.pixelHeight,
        frameCount: inspection.frameCount
      )
      selectedAssetID = reference.identifier
      assetPreview = inspection.preview
      profileStore.saveSelected()

      if case .saved = profileStore.status {
        savedLocally = true
        assetMessageIsError = false
        assetMessage = studioText(
          "앱 전용 폴더에 복사하고 프로필에 저장했습니다.",
          "Copied into app storage and saved in the profile.",
          language: language
        )
      } else {
        savedLocally = false
        assetMessageIsError = true
        assetMessage = studioText(
          "로컬 복사본은 만들었지만 프로필 저장을 완료하지 못했습니다.",
          "The local copy was created, but the profile could not be saved.",
          language: language
        )
      }
    } catch {
      savedLocally = false
      assetMessageIsError = true
      assetMessage = studioText(
        "지원되는 로컬 이미지를 가져오지 못했습니다.",
        "The supported local image could not be imported.",
        language: language
      )
    }
  }

  private func exportSelectedAsset() {
    guard let selectedAsset else { return }

    let panel = NSSavePanel()
    panel.title = studioText("로컬 이미지 복사본 내보내기", "Export the local image copy", language: language)
    panel.prompt = studioText("내보내기", "Export", language: language)
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = URL(fileURLWithPath: selectedAsset.resourceName).lastPathComponent
    let filenameExtension = URL(fileURLWithPath: panel.nameFieldStringValue).pathExtension
    if let contentType = UTType(filenameExtension: filenameExtension) {
      panel.allowedContentTypes = [contentType]
    }

    guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

    do {
      try profileStore.exportDisplayAsset(selectedAsset, to: destinationURL)
      assetMessageIsError = false
      assetMessage = studioText(
        "선택한 로컬 복사본을 내보냈습니다.",
        "Exported the selected local copy.",
        language: language
      )
    } catch {
      assetMessageIsError = true
      assetMessage = studioText(
        "선택한 로컬 복사본을 내보내지 못했습니다.",
        "The selected local copy could not be exported.",
        language: language
      )
    }
  }

  private func playlistPosition(for identifier: String) -> Int? {
    profileStore.selectedProfile.tft.playlist.firstIndex(of: identifier).map { $0 + 1 }
  }

  private func compatibilityLabel(for asset: DisplayAssetReference) -> String {
    if asset.frameCount > 1 {
      return studioText(
        "로컬 애니메이션 · 장치 호환성 미확인",
        "Local animation · device compatibility unverified",
        language: language
      )
    }
    if asset.width == 240, asset.height == 135 {
      return studioText(
        "240×135 목표 캔버스와 일치", "Matches the 240×135 target canvas", language: language)
    }
    return studioText(
      "240×135 미리보기 안에 비율 유지 표시",
      "Aspect-fit inside the 240×135 preview",
      language: language
    )
  }

  private func compatibilitySymbol(for asset: DisplayAssetReference) -> String {
    if asset.frameCount > 1 { return "photo.stack" }
    return asset.width == 240 && asset.height == 135
      ? "checkmark.circle" : "rectangle.compress.vertical"
  }

  private func compatibilityTint(for asset: DisplayAssetReference) -> Color {
    if asset.frameCount > 1 { return StudioPalette.violet }
    return asset.width == 240 && asset.height == 135 ? StudioPalette.mint : StudioPalette.violet
  }

  private func saveProfile() {
    profileStore.updateTFT(currentTFTDraft)
    profileStore.saveSelected()
    if case .saved = profileStore.status {
      savedLocally = true
    } else {
      savedLocally = false
    }
  }

  private func loadProfile() {
    let tft = profileStore.selectedProfile.tft
    if let identifier = tft.themeIdentifier {
      theme =
        ["Orbit", "Horizon", "Mono"].first(where: {
          $0.lowercased() == identifier.lowercased()
        }) ?? "Orbit"
    } else {
      theme = "Orbit"
    }
    note = tft.message ?? "HELLO, MAC"
    accent = tft.accentColor?.swiftUIColor ?? StudioPalette.mint
    showClock = tft.showsClock ?? true
    showBattery = tft.showsBattery ?? true
    selectedAssetID =
      tft.playlist.first(where: { identifier in
        tft.assets.contains(where: { $0.identifier == identifier })
      }) ?? tft.assets.first?.identifier
    loadAssetPreview()
    assetMessage = nil
    savedLocally = false
  }

  private func loadAssetPreview() {
    guard let selectedAsset,
      let url = profileStore.displayAssetURL(for: selectedAsset)
    else {
      assetPreview = nil
      return
    }
    assetPreview = DisplayAssetInspection.makePreview(url)
  }
}

private struct DisplayAssetCard: View {
  let asset: DisplayAssetReference
  let playlistPosition: Int?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: asset.frameCount > 1 ? "photo.stack" : "photo")
            .foregroundStyle(isSelected ? StudioPalette.blue : .secondary)
          Spacer()
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? StudioPalette.blue : .secondary)
        }

        Text(URL(fileURLWithPath: asset.resourceName).lastPathComponent)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)

        HStack {
          Text("\(asset.width)×\(asset.height)")
          Spacer()
          Text("\(asset.frameCount)f")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)

        if let playlistPosition {
          Label("Playlist #\(playlistPosition)", systemImage: "list.number")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(13)
      .background(
        isSelected ? StudioPalette.blue.opacity(0.10) : Color.primary.opacity(0.035),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(isSelected ? StudioPalette.blue.opacity(0.45) : Color.primary.opacity(0.08))
      }
    }
    .buttonStyle(.plain)
  }
}

private struct DisplayAssetInspection {
  let pixelWidth: Int
  let pixelHeight: Int
  let frameCount: Int
  let preferredFilenameExtension: String
  let preview: NSImage

  static func inspect(_ url: URL) throws -> DisplayAssetInspection {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
      let byteCount = values.fileSize,
      byteCount > 0,
      byteCount <= LocalDisplayAssetLimits.maximumByteCount,
      let source = makeSource(url),
      let sourceType = CGImageSourceGetType(source),
      let contentType = UTType(sourceType as String),
      contentType.conforms(to: .png)
        || contentType.conforms(to: .jpeg)
        || contentType.conforms(to: .gif),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      (1...8_192).contains(width),
      (1...8_192).contains(height)
    else {
      throw DisplayAssetInspectionError.invalidImage
    }

    let frameCount = CGImageSourceGetCount(source)
    guard (1...10_000).contains(frameCount),
      let preview = makePreview(source)
    else {
      throw DisplayAssetInspectionError.invalidImage
    }

    let filenameExtension: String
    if contentType.conforms(to: .gif) {
      filenameExtension = "gif"
    } else if contentType.conforms(to: .png) {
      filenameExtension = "png"
    } else {
      filenameExtension = "jpg"
    }

    return DisplayAssetInspection(
      pixelWidth: width,
      pixelHeight: height,
      frameCount: frameCount,
      preferredFilenameExtension: filenameExtension,
      preview: preview
    )
  }

  static func makePreview(_ url: URL) -> NSImage? {
    guard let source = makeSource(url) else { return nil }
    return makePreview(source)
  }

  private static func makeSource(_ url: URL) -> CGImageSource? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    return CGImageSourceCreateWithURL(url as CFURL, options)
  }

  private static func makePreview(_ source: CGImageSource) -> NSImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 480,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      return nil
    }
    return NSImage(
      cgImage: image,
      size: NSSize(width: image.width, height: image.height)
    )
  }
}

private enum DisplayAssetInspectionError: LocalizedError {
  case invalidImage

  var errorDescription: String? {
    "The selected file is not a supported local display image."
  }
}

private struct DisplayPreset: View {
  let name: String
  let colors: [Color]
  @Binding var selection: String

  var body: some View {
    Button {
      selection = name
    } label: {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: 54, height: 34)
        Text(name)
          .font(.callout.weight(.semibold))
        Spacer()
        Image(systemName: selection == name ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selection == name ? StudioPalette.blue : .secondary)
      }
      .frame(maxWidth: .infinity)
      .studioPanel(padding: 12)
    }
    .buttonStyle(.plain)
  }
}
