import AK47InspectorCore
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private enum DisplayEditorReplacementAction {
  case chooseFile
  case libraryAsset(DisplayAssetReference)
}

private struct DisplayImportSession: Equatable {
  let id = UUID()
  let profileIdentifier: String
}

struct DisplayComposerView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var model: StudioModel
  @ObservedObject var profileStore: LocalProfileStore
  @State private var theme = "Orbit"
  @State private var accent = StudioPalette.mint
  @State private var showClock = true
  @State private var showBattery = true
  @State private var note = "HELLO, MAC"
  @State private var savedLocally = false
  @State private var selectedAssetID: String?
  @State private var assetPreview: NSImage?
  @State private var assetPreviewSource: DisplayAssetPreviewSource?
  @State private var assetTimeline: DisplayAnimationTimeline?
  @State private var assetEstimate: DisplayContainerEstimate?
  @State private var currentFrameIndex = 0
  @State private var previewIsPlaying = false
  @State private var playbackRevision = 0
  @State private var animationEditorInput: DisplayAnimationEditorInput?
  @State private var animationEditorDraftState: DisplayAnimationEditorDraftState?
  @State private var videoClipSelectionInput: LocalVideoClipSelectionInput?
  @State private var videoSecurityScopedURL: URL?
  @State private var videoSecurityScopeIsActive = false
  @State private var isInspectingImport = false
  @State private var importInspectionTask: Task<Void, Never>?
  @State private var activeImportSession: DisplayImportSession?
  @State private var pendingReplacementAction: DisplayEditorReplacementAction?
  @State private var showsReplacementConfirmation = false
  @State private var showsLibraryAndStudy = false
  @State private var showsDeviceRecovery = false
  @State private var qualifiedVisualReviewSnapshot: LCDQualifiedAnimationSnapshot?
  @State private var assetMessage: String?
  @State private var assetMessageIsError = false

  init(model: StudioModel) {
    self.model = model
    profileStore = model.profileStore
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("240 × 135 시안", "240 × 135 study", language: language),
          title: studioText("디스플레이", "Display", language: language),
          detail: studioText(
            "이미지·GIF·로컬 영상을 불러와 실제 240×135 화면에서 바로 편집합니다. 장치 적용은 검증된 자격과 별도 exact-plan 확인을 계속 요구합니다.",
            "Import images, GIFs, or local videos and edit them directly on the actual 240×135 canvas. Device Apply still requires verified qualification and separate exact-plan confirmation.",
            language: language
          )
        )

        primaryEditor
        libraryAndStudyDisclosure
        deviceRecoveryDisclosure
      }
      .padding(28)
      .frame(maxWidth: 1060)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .onAppear(perform: loadProfile)
    .onChange(of: profileStore.selectedID) { _ in
      cancelActiveImportSession()
      loadProfile()
    }
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
    .task(id: playbackTaskID) {
      await playSelectedAsset()
    }
    .onDisappear {
      previewIsPlaying = false
      cancelActiveImportSession()
    }
    .sheet(
      item: $videoClipSelectionInput,
      onDismiss: {
        cancelActiveImportSession()
        releaseVideoSecurityScope()
      }
    ) { input in
      LocalVideoClipSelectionView(input: input) { result in
        guard let session = activeImportSession,
          canCommitImportSession(session)
        else {
          videoClipSelectionInput = nil
          return
        }
        animationEditorInput = DisplayAnimationEditorInput(
          sourceURL: result.descriptor.sourceURL,
          displayName: result.descriptor.sourceURL.lastPathComponent,
          fallbackDelayMilliseconds: fallbackFrameDelayMilliseconds,
          preparedDecodedSource: result.decodedSource,
          preparedSourceRequiresExport: true
        )
        animationEditorDraftState = nil
        finishImportSession(session)
        videoClipSelectionInput = nil
      }
      .environment(\.studioLanguage, language)
    }
    .sheet(item: $qualifiedVisualReviewSnapshot) { snapshot in
      LCDQualifiedUploadVisualReviewSheet(
        snapshot: snapshot,
        canConfirmCorrect: model.canConfirmQualifiedLCDAnimationVisualResult,
        canReportMismatch: model.canReportQualifiedLCDAnimationVisualMismatch,
        onConfirmCorrect: {
          if model.recordQualifiedLCDAnimationVisualResult() {
            qualifiedVisualReviewSnapshot = nil
          }
        },
        onReportMismatch: {
          if model.reportQualifiedLCDAnimationVisualMismatch() {
            qualifiedVisualReviewSnapshot = nil
          }
        }
      )
      .environment(\.studioLanguage, language)
    }
    .confirmationDialog(
      studioText(
        "현재 편집 초안을 바꿀까요?",
        "Replace the current editing draft?",
        language: language
      ),
      isPresented: $showsReplacementConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        studioText("현재 초안을 버리고 계속", "Discard current draft and continue", language: language),
        role: .destructive
      ) {
        performPendingReplacementAction()
      }
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {
        pendingReplacementAction = nil
      }
    } message: {
      Text(
        studioText(
          "내보내지 않은 편집, 적용하지 않은 크롭, 메모리에만 있는 영상 구간 프레임이 사라질 수 있습니다. 새 파일은 확인 후에만 불러옵니다.",
          "Unexported edits, unapplied crop settings, and video-range frames held only in memory may be lost. A new file is chosen only after this confirmation.",
          language: language
        )
      )
    }
  }

  private var primaryEditor: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(studioText("불러오기 → 편집 → 적용", "Import → edit → Apply", language: language))
            .font(.headline)
          Text(
            studioText(
              "원본은 바꾸지 않고, 장치에 저장될 240×135 결과를 같은 화면에서 확인합니다.",
              "The source stays unchanged while the same screen shows the 240×135 result stored on the device.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        if isInspectingImport {
          ProgressView()
            .controlSize(.small)
        }
        Button(action: requestUnifiedImport) {
          Label(
            studioText("불러오기…", "Import…", language: language),
            systemImage: "square.and.arrow.down"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
        .disabled(isInspectingImport || animationEditorDraftState?.isBusy == true)
      }

      if let input = animationEditorInput {
        DisplayAnimationEditorView(
          input: input,
          studioModel: model,
          presentation: .embedded,
          onDraftStateChange: { state in
            animationEditorDraftState = state
          }
        )
        .environment(\.studioLanguage, language)
        .disabled(editorReplacementInProgress)
      } else {
        VStack(spacing: 16) {
          ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.black)
            Image(systemName: "photo.on.rectangle.angled")
              .font(.system(size: 42, weight: .light))
              .foregroundStyle(StudioPalette.mint.opacity(0.85))
          }
          .aspectRatio(240.0 / 135.0, contentMode: .fit)
          .frame(maxWidth: 640)
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(Color.white.opacity(0.12))
          }
          Text(
            studioText(
              "PNG·JPEG·GIF·MP4·MOV·M4V를 선택하면 이 자리에 편집기가 열립니다.",
              "Choose a PNG, JPEG, GIF, MP4, MOV, or M4V file to open the editor here.",
              language: language
            )
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Button(action: requestUnifiedImport) {
            Label(
              studioText("불러오기…", "Import…", language: language),
              systemImage: "plus"
            )
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.blue)
          .disabled(isInspectingImport)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .studioPanel()
      }

      if let assetMessage {
        Label(
          assetMessage,
          systemImage: assetMessageIsError ? "exclamationmark.triangle" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(assetMessageIsError ? StudioPalette.coral : StudioPalette.mint)
      }
    }
  }

  private var libraryAndStudyDisclosure: some View {
    DisclosureGroup(isExpanded: $showsLibraryAndStudy) {
      VStack(alignment: .leading, spacing: 18) {
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
      .padding(.top, 16)
    } label: {
      Label(
        studioText("보관함·재생 목록·디스플레이 시안", "Library, playlist & display study", language: language),
        systemImage: "rectangle.stack"
      )
      .font(.headline)
    }
    .studioPanel()
    .disabled(editorReplacementInProgress)
  }

  private var deviceRecoveryDisclosure: some View {
    DisclosureGroup(isExpanded: $showsDeviceRecovery) {
      VStack(alignment: .leading, spacing: 18) {
        LCDExperimentalTransferCard(
          adapterLinked: true,
          exactTargetReady: model.hasVerifiedLCDDiagnosticTarget,
          deviceOperationAllowed: model.canRunLCDDiagnosticUpload,
          qualificationAllowsFreshDiagnostic: model.qualificationAllowsFreshLCDDiagnostic,
          uploadState: model.lcdDiagnosticUploadState,
          onBeginOneFrameUpload: model.uploadLCDDiagnosticFixtureOnce
        )

        LCDExtendedQualificationCard(
          state: model.lcdExtendedQualificationViewState,
          canRefreshHardware: model.canRefreshInspector,
          canRecordVisualAttestation: model.canRecordLCDCanonicalVisualAttestation,
          canReportCanonicalVisualMismatch: model.canReportLCDCanonicalVisualMismatch,
          canRecordWiredPowerRemovalAttestation: model
            .canRecordLCDUSBModeCablePowerCycleAttestation,
          canReviewExtendedVisualResult: model.canConfirmQualifiedLCDAnimationVisualResult,
          canReportExtendedVisualMismatch: model.canReportQualifiedLCDAnimationVisualMismatch,
          canReconcileInterruptedTransfer: model.canReconcileInterruptedLCDTransfer,
          errorMessage: model.lcdExtendedQualificationError,
          onRefreshHardware: model.refreshInspector,
          onRecordVisualAttestation: model.recordLCDCanonicalVisualAttestation,
          onReportCanonicalVisualMismatch: {
            _ = model.reportLCDCanonicalVisualMismatch()
          },
          onRecordWiredPowerRemovalAttestation: model
            .recordLCDUSBModeCablePowerCycleAttestation,
          onReviewExtendedVisualResult: {
            qualifiedVisualReviewSnapshot = model.lcdQualifiedAnimationVisualReviewSnapshot
          },
          onReportExtendedVisualMismatch: {
            _ = model.reportQualifiedLCDAnimationVisualMismatch()
          },
          onReconcileInterruptedTransfer: {
            _ = model.reconcileInterruptedLCDTransfer()
          }
        )
      }
      .padding(.top, 16)
    } label: {
      Label(
        studioText(
          "장치 실험·자격·복구", "Device experiments, qualification & recovery", language: language),
        systemImage: "wrench.and.screwdriver"
      )
      .font(.headline)
    }
    .studioPanel()
    .disabled(editorReplacementInProgress)
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

      if let timeline = assetTimeline {
        animationControls(timeline: timeline)
      }

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

      if let selectedAsset, let assetEstimate {
        DisplayAssetValidationSummary(
          asset: selectedAsset,
          estimate: assetEstimate,
          currentFrameDelayMilliseconds: assetTimeline?.delayMilliseconds(
            forFrameAt: currentFrameIndex),
          totalDurationMilliseconds: assetTimeline?.totalDurationMilliseconds,
          language: language
        )
      }
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
              previewOverlayLabel,
              systemImage: assetTimeline?.frameCount ?? 0 > 1 ? "play.rectangle" : "photo"
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

  private var playlistAssets: [DisplayAssetReference] {
    let byIdentifier = Dictionary(uniqueKeysWithValues: assets.map { ($0.identifier, $0) })
    return profileStore.selectedProfile.tft.playlist.compactMap { byIdentifier[$0] }
  }

  private var selectedAsset: DisplayAssetReference? {
    guard let selectedAssetID else { return nil }
    return assets.first(where: { $0.identifier == selectedAssetID })
  }

  private var playbackTaskID: String {
    "\(selectedAssetID ?? "none"):\(previewIsPlaying):\(playbackRevision)"
  }

  private var previewOverlayLabel: String {
    guard let timeline = assetTimeline, timeline.frameCount > 1 else {
      return studioText("로컬 복사본 · 정지 이미지", "Local copy · still image", language: language)
    }
    return studioText(
      "로컬 복사본 · \(currentFrameIndex + 1)/\(timeline.frameCount) 프레임",
      "Local copy · frame \(currentFrameIndex + 1)/\(timeline.frameCount)",
      language: language
    )
  }

  private func animationControls(timeline: DisplayAnimationTimeline) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Button {
          showFrame(max(0, currentFrameIndex - 1), restartPlayback: true)
        } label: {
          Image(systemName: "backward.frame.fill")
        }
        .buttonStyle(.borderless)
        .disabled(timeline.frameCount <= 1 || currentFrameIndex == 0)

        Button {
          previewIsPlaying.toggle()
          playbackRevision += 1
        } label: {
          Image(systemName: previewIsPlaying ? "pause.fill" : "play.fill")
            .frame(width: 18)
        }
        .buttonStyle(.bordered)
        .disabled(timeline.frameCount <= 1)
        .help(
          previewIsPlaying
            ? studioText("미리보기 일시 정지", "Pause preview", language: language)
            : studioText("미리보기 재생", "Play preview", language: language)
        )

        Button {
          showFrame(min(timeline.frameCount - 1, currentFrameIndex + 1), restartPlayback: true)
        } label: {
          Image(systemName: "forward.frame.fill")
        }
        .buttonStyle(.borderless)
        .disabled(timeline.frameCount <= 1 || currentFrameIndex >= timeline.frameCount - 1)

        Slider(
          value: Binding(
            get: { Double(currentFrameIndex) },
            set: { showFrame(Int($0.rounded()), restartPlayback: true) }
          ),
          in: 0...Double(max(1, timeline.frameCount - 1)),
          step: 1
        )
        .disabled(timeline.frameCount <= 1)

        Text("\(currentFrameIndex + 1) / \(timeline.frameCount)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(minWidth: 58, alignment: .trailing)
      }

      HStack {
        Text(
          studioText(
            "소스 지연 \(timeline.delayMilliseconds(forFrameAt: currentFrameIndex) ?? 0) ms",
            "Source delay \(timeline.delayMilliseconds(forFrameAt: currentFrameIndex) ?? 0) ms",
            language: language
          )
        )
        Spacer()
        Text(
          studioText(
            "미리보기 최소 \(DisplayPreviewRuntimeLimits.minimumPlaybackDelayMilliseconds) ms",
            "Preview minimum \(DisplayPreviewRuntimeLimits.minimumPlaybackDelayMilliseconds) ms",
            language: language
          )
        )
        Spacer()
        Text(
          studioText(
            "1회 \(formattedDuration(timeline.totalDurationMilliseconds))",
            "Loop \(formattedDuration(timeline.totalDurationMilliseconds))",
            language: language
          )
        )
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }

  private var assetLibrary: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("로컬 미디어 보관함", "Local media library", language: language))
            .font(.headline)
          Text(
            studioText(
              "PNG·JPEG·GIF는 앱 전용 폴더와 재생 목록에 보관합니다. 영상 원본은 복사하지 않고 편집기로 바로 열며, 결과는 GIF로 내보내야 보존됩니다.",
              "PNG, JPEG, and GIF files are kept in app storage and the playlist. Video sources open directly in the editor without being copied; export a GIF to preserve the result.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button(action: requestUnifiedImport) {
          Label(studioText("불러오기…", "Import…", language: language), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
        .disabled(isInspectingImport || animationEditorDraftState?.isBusy == true)
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

      if !playlistAssets.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(studioText("재생 목록", "Playlist", language: language))
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text(
              studioText(
                "\(playlistAssets.count)개 로컬 항목",
                "\(playlistAssets.count) local items",
                language: language
              )
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          }

          ForEach(Array(playlistAssets.enumerated()), id: \.offset) { index, asset in
            HStack(spacing: 10) {
              Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
              Button {
                selectedAssetID = asset.identifier
              } label: {
                HStack {
                  Image(systemName: asset.frameCount > 1 ? "photo.stack" : "photo")
                  Text(URL(fileURLWithPath: asset.resourceName).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)

              Button {
                movePlaylistItem(from: index, by: -1)
              } label: {
                Image(systemName: "chevron.up")
              }
              .buttonStyle(.borderless)
              .disabled(index == 0)
              .help(studioText("위로 이동", "Move up", language: language))

              Button {
                movePlaylistItem(from: index, by: 1)
              } label: {
                Image(systemName: "chevron.down")
              }
              .buttonStyle(.borderless)
              .disabled(index == playlistAssets.count - 1)
              .help(studioText("아래로 이동", "Move down", language: language))

              Button(role: .destructive) {
                removePlaylistItem(at: index)
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
              .help(
                studioText(
                  "재생 목록에서만 제거", "Remove from playlist only", language: language)
              )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
          }
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
          if playlistPosition(for: selectedAsset.identifier) == nil {
            Button(action: addSelectedAssetToPlaylist) {
              Label(
                studioText("재생 목록에 추가", "Add to playlist", language: language),
                systemImage: "text.badge.plus"
              )
            }
            .buttonStyle(.bordered)
          }
          Button {
            requestOpenAnimationEditor(for: selectedAsset)
          } label: {
            Label(
              studioText("편집…", "Edit…", language: language),
              systemImage: "slider.horizontal.3"
            )
          }
          .buttonStyle(.bordered)
          .disabled(
            profileStore.displayAssetURL(for: selectedAsset) == nil
              || animationEditorDraftState?.isBusy == true
          )
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
          "이 화면의 미리보기·편집·저장은 로컬 전용이며 HID report를 보내지 않습니다.",
          "Preview, editing, and saving on this screen are local only and send no HID report.",
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
          "이미지와 GIF/RGB565 내보내기는 로컬 전용이며 자동 전송되지 않습니다. 자격이 검증된 뒤에도 editor의 현재 불변 snapshot만 별도 exact-plan 확인으로 적용합니다.",
          "Image and GIF/RGB565 exports remain local and are never uploaded automatically. Even after qualification, only the editor's current immutable snapshot can be applied through a separate exact-plan confirmation.",
          language: language
        ),
        systemImage: "lock.shield"
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

  private var editorReplacementInProgress: Bool {
    isInspectingImport || videoClipSelectionInput != nil || activeImportSession != nil
  }

  private func requestUnifiedImport() {
    requestReplacement(.chooseFile)
  }

  private func requestOpenAnimationEditor(for asset: DisplayAssetReference) {
    requestReplacement(.libraryAsset(asset))
  }

  private func requestReplacement(_ action: DisplayEditorReplacementAction) {
    switch DisplayEditorReplacementPolicy.decision(
      hasEditorInput: animationEditorInput != nil,
      draftState: animationEditorDraftState,
      replacementInProgress: editorReplacementInProgress
    ) {
    case .blocked:
      return
    case .confirmDiscard:
      pendingReplacementAction = action
      showsReplacementConfirmation = true
    case .proceed:
      pendingReplacementAction = action
      performPendingReplacementAction()
    }
  }

  private func performPendingReplacementAction() {
    guard let action = pendingReplacementAction else { return }
    guard animationEditorDraftState?.isBusy != true, !editorReplacementInProgress else {
      pendingReplacementAction = nil
      return
    }
    pendingReplacementAction = nil
    switch action {
    case .chooseFile:
      presentUnifiedImportPanel()
    case .libraryAsset(let asset):
      openAnimationEditor(for: asset)
    }
  }

  @discardableResult
  private func beginImportSession() -> DisplayImportSession {
    importInspectionTask?.cancel()
    let session = DisplayImportSession(profileIdentifier: profileStore.selectedID)
    activeImportSession = session
    isInspectingImport = true
    return session
  }

  private func canCommitImportSession(_ session: DisplayImportSession) -> Bool {
    activeImportSession == session
      && profileStore.selectedID == session.profileIdentifier
      && !Task.isCancelled
  }

  private func finishImportInspection(
    _ session: DisplayImportSession,
    preservingVideoSelection: Bool
  ) {
    guard activeImportSession == session else { return }
    importInspectionTask = nil
    isInspectingImport = false
    if !preservingVideoSelection {
      activeImportSession = nil
    }
  }

  private func finishImportSession(_ session: DisplayImportSession) {
    guard activeImportSession == session else { return }
    importInspectionTask = nil
    activeImportSession = nil
    isInspectingImport = false
  }

  private func cancelActiveImportSession() {
    importInspectionTask?.cancel()
    importInspectionTask = nil
    activeImportSession = nil
    isInspectingImport = false
    videoClipSelectionInput = nil
    releaseVideoSecurityScope()
  }

  private func presentUnifiedImportPanel() {
    let panel = NSOpenPanel()
    panel.title = studioText(
      "이미지·GIF 또는 영상 선택",
      "Choose an image, GIF, or video",
      language: language
    )
    panel.prompt = studioText("불러오기", "Import", language: language)
    panel.allowedContentTypes = [.png, .jpeg, .gif, .movie]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
    let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    let contentType =
      (try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType)
      ?? UTType(filenameExtension: sourceURL.pathExtension)
    if contentType?.conforms(to: .movie) == true {
      beginVideoSelection(
        sourceURL: sourceURL,
        accessedSecurityScope: accessedSecurityScope
      )
    } else {
      importLocalImage(
        sourceURL: sourceURL,
        accessedSecurityScope: accessedSecurityScope
      )
    }
  }

  private func importLocalImage(
    sourceURL: URL,
    accessedSecurityScope: Bool
  ) {
    let session = beginImportSession()
    let fallback = fallbackFrameDelayMilliseconds
    importInspectionTask = Task { @MainActor in
      defer {
        finishImportSession(session)
        if accessedSecurityScope {
          sourceURL.stopAccessingSecurityScopedResource()
        }
      }
      do {
        let loaderTask = Task.detached(priority: .userInitiated) {
          try LocalDisplayEditorSourceLoader.inspect(
            url: sourceURL,
            fallbackDelayMilliseconds: fallback
          )
        }
        defer { loaderTask.cancel() }
        let inspection = try await withTaskCancellationHandler {
          try await loaderTask.value
        } onCancel: {
          loaderTask.cancel()
        }
        try Task.checkCancellation()
        guard canCommitImportSession(session) else { throw CancellationError() }
        profileStore.updateTFT(currentTFTDraft)
        let decoded = inspection.decodedSource
        let reference = try profileStore.storeDisplayAsset(
          snapshotData: inspection.sourceData,
          originalFilename: sourceURL.lastPathComponent,
          preferredFilenameExtension: inspection.preferredFilenameExtension,
          pixelWidth: decoded.sourceWidth,
          pixelHeight: decoded.sourceHeight,
          frameCount: decoded.frames.count
        )
        selectedAssetID = reference.identifier
        profileStore.saveSelected()
        guard let storedURL = profileStore.displayAssetURL(for: reference) else {
          throw DisplayAssetInspectionError.invalidImage
        }
        animationEditorInput = DisplayAnimationEditorInput(
          sourceURL: storedURL,
          displayName: URL(fileURLWithPath: reference.resourceName).lastPathComponent,
          fallbackDelayMilliseconds: fallback,
          preparedDecodedSource: decoded
        )
        animationEditorDraftState = nil

        if case .saved = profileStore.status {
          savedLocally = true
          assetMessageIsError = false
          assetMessage = studioText(
            "앱 전용 폴더에 복사하고 편집기를 열었습니다.",
            "Copied into app storage and opened in the editor.",
            language: language
          )
        } else {
          savedLocally = false
          assetMessageIsError = true
          assetMessage = studioText(
            "로컬 복사본과 편집기는 열었지만 프로필 저장을 완료하지 못했습니다.",
            "The local copy and editor are ready, but the profile could not be saved.",
            language: language
          )
        }
      } catch is CancellationError {
        return
      } catch {
        guard canCommitImportSession(session) else { return }
        savedLocally = false
        assetMessageIsError = true
        assetMessage = studioText(
          "지원되는 로컬 이미지·GIF를 불러오지 못했습니다: \(error.localizedDescription)",
          "Could not import the supported local image or GIF: \(error.localizedDescription)",
          language: language
        )
      }
    }
  }

  private func beginVideoSelection(
    sourceURL: URL,
    accessedSecurityScope: Bool
  ) {
    releaseVideoSecurityScope()
    videoSecurityScopedURL = sourceURL
    videoSecurityScopeIsActive = accessedSecurityScope
    let session = beginImportSession()
    importInspectionTask = Task { @MainActor in
      var didPresentSelection = false
      defer {
        releaseVideoSecurityScope()
        finishImportInspection(
          session,
          preservingVideoSelection: didPresentSelection
        )
      }
      do {
        let descriptor = try await LocalVideoImportService.inspect(url: sourceURL)
        try Task.checkCancellation()
        guard canCommitImportSession(session) else { throw CancellationError() }
        videoClipSelectionInput = LocalVideoClipSelectionInput(descriptor: descriptor)
        didPresentSelection = true
        assetMessage = nil
      } catch is CancellationError {
        return
      } catch {
        guard canCommitImportSession(session) else { return }
        assetMessageIsError = true
        assetMessage = studioText(
          "로컬 영상을 열지 못했습니다: \(error.localizedDescription)",
          "Could not open the local video: \(error.localizedDescription)",
          language: language
        )
      }
    }
  }

  private func releaseVideoSecurityScope() {
    if videoSecurityScopeIsActive, let videoSecurityScopedURL {
      videoSecurityScopedURL.stopAccessingSecurityScopedResource()
    }
    videoSecurityScopedURL = nil
    videoSecurityScopeIsActive = false
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

  private func openAnimationEditor(for asset: DisplayAssetReference) {
    guard let sourceURL = profileStore.displayAssetURL(for: asset) else { return }
    let session = beginImportSession()
    let fallback = fallbackFrameDelayMilliseconds
    importInspectionTask = Task { @MainActor in
      defer { finishImportSession(session) }
      do {
        let loaderTask = Task.detached(priority: .userInitiated) {
          try LocalDisplayEditorSourceLoader.load(
            url: sourceURL,
            fallbackDelayMilliseconds: fallback
          )
        }
        defer { loaderTask.cancel() }
        let decoded = try await withTaskCancellationHandler {
          try await loaderTask.value
        } onCancel: {
          loaderTask.cancel()
        }
        try Task.checkCancellation()
        guard canCommitImportSession(session) else { throw CancellationError() }
        animationEditorInput = DisplayAnimationEditorInput(
          sourceURL: sourceURL,
          displayName: URL(fileURLWithPath: asset.resourceName).lastPathComponent,
          fallbackDelayMilliseconds: fallback,
          preparedDecodedSource: decoded
        )
        animationEditorDraftState = nil
        assetMessageIsError = false
        assetMessage = studioText(
          "선택한 보관함 항목을 편집기에서 열었습니다.",
          "Opened the selected library item in the editor.",
          language: language
        )
      } catch is CancellationError {
        return
      } catch {
        guard canCommitImportSession(session) else { return }
        assetMessageIsError = true
        assetMessage = studioText(
          "선택한 보관함 항목을 편집기로 열지 못했습니다: \(error.localizedDescription)",
          "Could not open the selected library item in the editor: \(error.localizedDescription)",
          language: language
        )
      }
    }
  }

  private func movePlaylistItem(from sourceIndex: Int, by offset: Int) {
    let playlist = profileStore.selectedProfile.tft.playlist
    applyPlaylist(DisplayPlaylistEditing.moving(playlist, from: sourceIndex, by: offset))
  }

  private func removePlaylistItem(at index: Int) {
    let playlist = profileStore.selectedProfile.tft.playlist
    applyPlaylist(DisplayPlaylistEditing.removing(playlist, at: index))
    assetMessageIsError = false
    assetMessage = studioText(
      "로컬 복사본은 유지하고 재생 목록에서만 제거했습니다.",
      "Removed it from the playlist while keeping the local copy.",
      language: language
    )
  }

  private func addSelectedAssetToPlaylist() {
    guard let selectedAsset else { return }
    let playlist = profileStore.selectedProfile.tft.playlist
    applyPlaylist(DisplayPlaylistEditing.appending(selectedAsset.identifier, to: playlist))
    assetMessageIsError = false
    assetMessage = studioText(
      "재생 목록 끝에 추가했습니다.",
      "Added it to the end of the playlist.",
      language: language
    )
  }

  private func applyPlaylist(_ playlist: [String]) {
    var draft = currentTFTDraft
    draft.playlist = playlist
    profileStore.updateTFT(draft)
    savedLocally = false
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
    assetMessage = nil
    loadAssetPreview()
    savedLocally = false
  }

  private func loadAssetPreview() {
    guard let selectedAsset,
      let url = profileStore.displayAssetURL(for: selectedAsset)
    else {
      clearAssetPreview()
      return
    }

    do {
      let source = try DisplayAssetPreviewSource(
        url: url,
        fallbackDelayMilliseconds: fallbackFrameDelayMilliseconds
      )
      let timeline = DisplayAnimationTimeline(
        frameCount: source.frameCount,
        sourceDelaysMilliseconds: source.frameDelaysMilliseconds,
        fallbackDelayMilliseconds: fallbackFrameDelayMilliseconds
      )
      assetPreviewSource = source
      assetTimeline = timeline
      assetEstimate = DisplayContainerEstimate(
        targetWidth: 240,
        targetHeight: 135,
        referenceFrameCount: selectedAsset.frameCount,
        decodedWidth: source.pixelWidth,
        decodedHeight: source.pixelHeight,
        decodedFrameCount: source.frameCount,
        decodedDelayCount: timeline.frameDelaysMilliseconds.count,
        encodedContainerByteCount: Int64(source.containerByteCount),
        maximumContainerByteCount: Int64(LocalDisplayAssetLimits.maximumByteCount),
        planningPageByteCount: 4_096
      )
      currentFrameIndex = 0
      assetPreview = source.image(at: 0)
      previewIsPlaying = false
      playbackRevision += 1
    } catch {
      clearAssetPreview()
      assetMessageIsError = true
      assetMessage = studioText(
        "로컬 복사본의 프레임을 읽지 못했습니다.",
        "The frames in the local copy could not be read.",
        language: language
      )
    }
  }

  private var fallbackFrameDelayMilliseconds: Int {
    let frameRate = max(1, profileStore.selectedProfile.tft.frameRate)
    return max(1, Int((1_000.0 / Double(frameRate)).rounded()))
  }

  private func clearAssetPreview() {
    assetPreview = nil
    assetPreviewSource = nil
    assetTimeline = nil
    assetEstimate = nil
    currentFrameIndex = 0
    previewIsPlaying = false
    playbackRevision += 1
  }

  private func showFrame(_ index: Int, restartPlayback: Bool) {
    guard let source = assetPreviewSource, source.frameCount > 0 else { return }
    let safeIndex = min(max(0, index), source.frameCount - 1)
    currentFrameIndex = safeIndex
    assetPreview = source.image(at: safeIndex) ?? assetPreview
    if restartPlayback {
      playbackRevision += 1
    }
  }

  @MainActor
  private func playSelectedAsset() async {
    guard previewIsPlaying, let timeline = assetTimeline, timeline.frameCount > 1 else { return }

    while !Task.isCancelled, previewIsPlaying {
      let delay =
        timeline.previewDelayMilliseconds(
          forFrameAt: currentFrameIndex,
          minimumMilliseconds: DisplayPreviewRuntimeLimits.minimumPlaybackDelayMilliseconds
        ) ?? DisplayPreviewRuntimeLimits.minimumPlaybackDelayMilliseconds
      do {
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
      } catch {
        return
      }
      guard !Task.isCancelled, previewIsPlaying else { return }
      showFrame((currentFrameIndex + 1) % timeline.frameCount, restartPlayback: false)
    }
  }

  private func formattedDuration(_ milliseconds: Int) -> String {
    if milliseconds < 1_000 {
      return "\(milliseconds) ms"
    }
    return String(format: "%.2f s", Double(milliseconds) / 1_000)
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

private struct DisplayAssetValidationSummary: View {
  let asset: DisplayAssetReference
  let estimate: DisplayContainerEstimate
  let currentFrameDelayMilliseconds: Int?
  let totalDurationMilliseconds: Int?
  let language: AppLanguage

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(studioText("선택 항목 검증", "Selected asset check", language: language))
          .font(.subheadline.weight(.semibold))
        Spacer()
        StatusPill(
          label: estimate.isInternallyConsistent
            ? studioText("파일 일치", "File consistent", language: language)
            : studioText("확인 필요", "Needs review", language: language),
          symbol: estimate.isInternallyConsistent ? "checkmark.circle" : "exclamationmark.triangle",
          tint: estimate.isInternallyConsistent ? StudioPalette.mint : StudioPalette.coral
        )
      }

      validationRow(
        title: studioText("캔버스", "Canvas", language: language),
        value: "\(estimate.decodedWidth)×\(estimate.decodedHeight) / 240×135",
        state: estimate.matchesTargetCanvas ? .pass : .notice
      )
      validationRow(
        title: studioText("프레임 수", "Frame count", language: language),
        value: studioText(
          "프로필 \(asset.frameCount) · 파일 \(estimate.decodedFrameCount)",
          "Profile \(asset.frameCount) · file \(estimate.decodedFrameCount)",
          language: language
        ),
        state: estimate.referenceMatchesDecodedFrameCount ? .pass : .fail
      )
      validationRow(
        title: studioText("프레임 지연", "Frame delays", language: language),
        value: delaySummary,
        state: estimate.hasOneDelayPerDecodedFrame ? .pass : .fail
      )
      validationRow(
        title: studioText("인코딩된 파일", "Encoded container", language: language),
        value: containerSummary,
        state: estimate.isContainerWithinLimit ? .pass : .fail
      )
      validationRow(
        title: studioText("4 KiB 계획 조각", "4 KiB planning chunks", language: language),
        value: studioText(
          "\(estimate.planningPageCount)개 · 마지막 \(estimate.finalPlanningPageByteCount) B",
          "\(estimate.planningPageCount) chunks · final \(estimate.finalPlanningPageByteCount) B",
          language: language
        ),
        state: .neutral
      )

      Text(
        studioText(
          "컨테이너와 4 KiB 값은 로컬 인코딩 계획치입니다. 실제 내보내기에서 형식을 다시 검증하지만, 이 값은 물리 SPI partition 끝이나 안전한 live upload 크기를 증명하지 않습니다.",
          "Container and 4 KiB values are local encoding estimates and are revalidated during export. They do not prove a physical SPI partition end or a safe live-upload size.",
          language: language
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
  }

  private var delaySummary: String {
    let count = estimate.decodedDelayCount
    guard let currentFrameDelayMilliseconds, let totalDurationMilliseconds else {
      return studioText("\(count)개", "\(count) entries", language: language)
    }
    return studioText(
      "\(count)개 · 현재 \(currentFrameDelayMilliseconds) ms · 1회 \(duration(totalDurationMilliseconds))",
      "\(count) entries · current \(currentFrameDelayMilliseconds) ms · loop \(duration(totalDurationMilliseconds))",
      language: language
    )
  }

  private var containerSummary: String {
    let byteCount = formattedBytes(estimate.encodedContainerByteCount)
    let limit = formattedBytes(estimate.maximumContainerByteCount)
    return "\(byteCount) / \(limit)"
  }

  private func validationRow(
    title: String,
    value: String,
    state: DisplayValidationState
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: state.symbol)
        .foregroundStyle(state.tint)
        .frame(width: 14)
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
        .foregroundStyle(state == .fail ? StudioPalette.coral : .primary)
    }
    .font(.caption.monospacedDigit())
  }

  private func formattedBytes(_ byteCount: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
  }

  private func duration(_ milliseconds: Int) -> String {
    guard milliseconds >= 1_000 else { return "\(milliseconds) ms" }
    return String(format: "%.2f s", Double(milliseconds) / 1_000)
  }
}

private enum DisplayValidationState {
  case pass
  case notice
  case fail
  case neutral

  var symbol: String {
    switch self {
    case .pass: "checkmark.circle.fill"
    case .notice: "rectangle.compress.vertical"
    case .fail: "exclamationmark.triangle.fill"
    case .neutral: "info.circle"
    }
  }

  var tint: Color {
    switch self {
    case .pass: StudioPalette.mint
    case .notice: StudioPalette.violet
    case .fail: StudioPalette.coral
    case .neutral: StudioPalette.blue
    }
  }
}

private struct DisplayAssetInspection {
  let pixelWidth: Int
  let pixelHeight: Int
  let frameCount: Int
  let preferredFilenameExtension: String

  static func inspect(
    _ url: URL,
    fallbackDelayMilliseconds: Int
  ) throws -> DisplayAssetInspection {
    let source = try DisplayAssetPreviewSource(
      url: url,
      fallbackDelayMilliseconds: fallbackDelayMilliseconds
    )
    return DisplayAssetInspection(
      pixelWidth: source.pixelWidth,
      pixelHeight: source.pixelHeight,
      frameCount: source.frameCount,
      preferredFilenameExtension: source.preferredFilenameExtension
    )
  }
}

private final class DisplayAssetPreviewSource {
  let pixelWidth: Int
  let pixelHeight: Int
  let frameCount: Int
  let frameDelaysMilliseconds: [Int]
  let containerByteCount: Int
  let preferredFilenameExtension: String

  private let source: CGImageSource
  private let imageCache = NSCache<NSNumber, NSImage>()

  init(url: URL, fallbackDelayMilliseconds: Int) throws {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
      let byteCount = values.fileSize,
      byteCount > 0,
      byteCount <= LocalDisplayAssetLimits.maximumByteCount
    else {
      throw DisplayAssetInspectionError.invalidImage
    }

    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
      let sourceType = CGImageSourceGetType(source),
      let contentType = UTType(sourceType as String),
      contentType.conforms(to: .png)
        || contentType.conforms(to: .jpeg)
        || contentType.conforms(to: .gif),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else {
      throw DisplayAssetInspectionError.invalidImage
    }

    let frameCount = CGImageSourceGetCount(source)
    guard
      DisplayPreviewWorkLimits.localImport.permits(
        width: width,
        height: height,
        frameCount: frameCount
      )
    else {
      throw DisplayAssetInspectionError.invalidImage
    }

    let safeFallback = min(60_000, max(1, fallbackDelayMilliseconds))
    let delays = (0..<frameCount).map { index in
      Self.frameDelayMilliseconds(source: source, index: index) ?? safeFallback
    }

    self.source = source
    self.pixelWidth = width
    self.pixelHeight = height
    self.frameCount = frameCount
    self.frameDelaysMilliseconds = delays
    self.containerByteCount = byteCount
    if contentType.conforms(to: .gif) {
      preferredFilenameExtension = "gif"
    } else if contentType.conforms(to: .png) {
      preferredFilenameExtension = "png"
    } else {
      preferredFilenameExtension = "jpg"
    }
    imageCache.countLimit = DisplayPreviewRuntimeLimits.maximumCachedFrameCount
    imageCache.totalCostLimit = DisplayPreviewRuntimeLimits.maximumCacheByteCost

    guard image(at: 0) != nil else {
      throw DisplayAssetInspectionError.invalidImage
    }
  }

  func image(at index: Int) -> NSImage? {
    guard (0..<frameCount).contains(index) else { return nil }
    let key = NSNumber(value: index)
    if let cached = imageCache.object(forKey: key) {
      return cached
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: DisplayPreviewRuntimeLimits.thumbnailMaximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    else {
      return nil
    }
    let preview = NSImage(
      cgImage: image,
      size: NSSize(width: image.width, height: image.height)
    )
    let (decodedByteCost, costOverflow) = image.bytesPerRow.multipliedReportingOverflow(
      by: image.height)
    imageCache.setObject(
      preview,
      forKey: key,
      cost: costOverflow ? DisplayPreviewRuntimeLimits.maximumCacheByteCost : decodedByteCost
    )
    return preview
  }

  private static func frameDelayMilliseconds(source: CGImageSource, index: Int) -> Int? {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        as? [CFString: Any],
      let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else {
      return nil
    }
    let seconds =
      (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
      ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
    guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
    let milliseconds = Int((seconds * 1_000).rounded())
    return (1...60_000).contains(milliseconds) ? milliseconds : nil
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
