import AK47InspectorCore
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct DisplayAnimationEditorInput: Identifiable {
  let id = UUID()
  let sourceURL: URL
  let displayName: String
  let fallbackDelayMilliseconds: Int
  let preparedDecodedSource: AK47LCDDecodedGIF?
  let preparedSourceRequiresExport: Bool

  init(
    sourceURL: URL,
    displayName: String,
    fallbackDelayMilliseconds: Int,
    preparedDecodedSource: AK47LCDDecodedGIF? = nil,
    preparedSourceRequiresExport: Bool = false
  ) {
    self.sourceURL = sourceURL
    self.displayName = displayName
    self.fallbackDelayMilliseconds = fallbackDelayMilliseconds
    self.preparedDecodedSource = preparedDecodedSource
    self.preparedSourceRequiresExport = preparedSourceRequiresExport
  }
}

typealias DisplaySourceTransformRenderer =
  @Sendable (
    _ source: AK47LCDDecodedGIF,
    _ mode: AK47LCDResizeMode,
    _ aspectFill: AK47LCDAspectFillTransform?
  ) throws -> AK47LCDAnimationProject

private let defaultDisplaySourceTransformRenderer: DisplaySourceTransformRenderer = {
  source,
  mode,
  aspectFill in
  if mode == .aspectFill {
    return try source.makeProject(aspectFill: aspectFill ?? .centered)
  }
  return try source.makeProject(resizeMode: mode)
}

enum DisplayAnimationEditorPresentation: Equatable {
  /// Legacy library flow presented in its own dismissible sheet.
  case sheet
  /// Primary Display-tab flow hosted directly inside the page.
  case embedded
}

struct DisplayAnimationEditorDraftState: Equatable, Sendable {
  let hasUnexportedChanges: Bool
  let hasPendingSourceTransform: Bool
  let isBusy: Bool
  let requiresReplacementConfirmation: Bool
}

struct DisplayAnimationEditorView: View {
  let input: DisplayAnimationEditorInput
  @ObservedObject var studioModel: StudioModel
  let presentation: DisplayAnimationEditorPresentation
  let onDraftStateChange: ((DisplayAnimationEditorDraftState) -> Void)?

  init(
    input: DisplayAnimationEditorInput,
    studioModel: StudioModel,
    presentation: DisplayAnimationEditorPresentation = .sheet,
    onDraftStateChange: ((DisplayAnimationEditorDraftState) -> Void)? = nil
  ) {
    self.input = input
    self.studioModel = studioModel
    self.presentation = presentation
    self.onDraftStateChange = onDraftStateChange
  }

  var body: some View {
    DisplayAnimationEditorSession(
      input: input,
      studioModel: studioModel,
      presentation: presentation,
      onDraftStateChange: onDraftStateChange
    )
    // Replacing an inline import must create a fresh StateObject-backed editing
    // session instead of retaining the prior asset's decoded source and draft.
    .id(input.id)
  }
}

private struct DisplayAnimationEditorSession: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.studioLanguage) private var language
  @ObservedObject private var studioModel: StudioModel
  private let presentation: DisplayAnimationEditorPresentation
  private let onDraftStateChange: ((DisplayAnimationEditorDraftState) -> Void)?
  @StateObject private var model: DisplayAnimationEditorModel
  @State private var drawingPoints: [AK47LCDPixelPoint] = []
  @State private var showsCloseDiscardConfirmation = false
  @State private var showsRerenderDiscardConfirmation = false
  @State private var pendingQualifiedUpload: LCDQualifiedAnimationSnapshot?
  @State private var qualifiedVisualReviewSnapshot: LCDQualifiedAnimationSnapshot?
  @State private var isPreparingQualifiedUpload = false
  @State private var qualifiedUploadPreparationError: String?

  init(
    input: DisplayAnimationEditorInput,
    studioModel: StudioModel,
    presentation: DisplayAnimationEditorPresentation,
    onDraftStateChange: ((DisplayAnimationEditorDraftState) -> Void)?
  ) {
    self.studioModel = studioModel
    self.presentation = presentation
    self.onDraftStateChange = onDraftStateChange
    _model = StateObject(wrappedValue: DisplayAnimationEditorModel(input: input))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if model.isLoading, model.project == nil {
        ProgressView(
          studioText(
            "미디어 프레임을 안전하게 준비하는 중…",
            "Safely preparing media frames…",
            language: language
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let project = model.project {
        HStack(alignment: .top, spacing: 0) {
          frameRail(project: project)
          Divider()
          previewPane(project: project)
          Divider()
          controls(project: project)
        }
      } else {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(StudioPalette.coral)
          Text(
            studioText(
              "이미지·애니메이션을 열 수 없습니다",
              "Could not open the image or animation",
              language: language
            )
          )
          .font(.headline)
          Text(model.message ?? "")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      footer
    }
    .frame(
      minWidth: presentation == .sheet ? 1_050 : nil,
      idealWidth: presentation == .sheet ? 1_130 : nil,
      minHeight: 690,
      idealHeight: 760
    )
    .task {
      await model.loadIfNeeded()
    }
    .onAppear {
      onDraftStateChange?(draftState)
    }
    .onChange(of: draftState) { state in
      onDraftStateChange?(state)
    }
    .interactiveDismissDisabled(
      presentation == .sheet
        && (model.requiresReplacementConfirmation || model.isLoading || isQualifiedUploadActive)
    )
    .alert(
      studioText("현재 편집을 버릴까요?", "Discard the current edit?", language: language),
      isPresented: $showsCloseDiscardConfirmation
    ) {
      Button(studioText("계속 편집", "Keep editing", language: language), role: .cancel) {}
      Button(studioText("버리고 닫기", "Discard and close", language: language), role: .destructive) {
        dismiss()
      }
    } message: {
      Text(
        studioText(
          "편집 GIF로 내보내지 않은 불러온 영상 프레임, 변경 내용, 미적용 크롭 설정이 사라집니다. LCD 컨테이너는 다시 편집할 수 있는 프로젝트 파일이 아닙니다.",
          "Imported video frames not exported as an edited GIF, later changes, and unapplied crop settings will be lost. An LCD container is not a reopenable project file.",
          language: language
        )
      )
    }
    .confirmationDialog(
      studioText(
        "현재 프레임 편집을 원본 렌더링으로 바꿀까요?",
        "Replace current frame edits with a source render?",
        language: language
      ),
      isPresented: $showsRerenderDiscardConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        studioText("편집을 버리고 이 화면으로 적용", "Discard edits and apply this view", language: language),
        role: .destructive
      ) {
        Task { await model.applyPendingSourceTransform() }
      }
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "불러온 원본을 기준으로 전체 프레임을 다시 만듭니다. 추가한 프레임과 픽셀 편집은 사라지지만, 프레임 수가 같으면 조정한 지연 값은 유지합니다.",
          "All frames are rebuilt from the imported source. Added frames and pixel edits are removed; adjusted delays are preserved when the frame count still matches.",
          language: language
        )
      )
    }
    .sheet(item: $pendingQualifiedUpload) { snapshot in
      LCDQualifiedUploadConfirmationSheet(
        snapshot: snapshot,
        onConfirm: {
          studioModel.uploadQualifiedLCDAnimation(snapshot)
          pendingQualifiedUpload = nil
        }
      )
      .environment(\.studioLanguage, language)
    }
    .sheet(item: $qualifiedVisualReviewSnapshot) { snapshot in
      LCDQualifiedUploadVisualReviewSheet(
        snapshot: snapshot,
        canConfirmCorrect: studioModel.canConfirmQualifiedLCDAnimationVisualResult,
        canReportMismatch: studioModel.canReportQualifiedLCDAnimationVisualMismatch,
        onConfirmCorrect: {
          if studioModel.recordQualifiedLCDAnimationVisualResult() {
            qualifiedVisualReviewSnapshot = nil
          }
        },
        onReportMismatch: {
          if studioModel.reportQualifiedLCDAnimationVisualMismatch() {
            qualifiedVisualReviewSnapshot = nil
          }
        }
      )
      .environment(\.studioLanguage, language)
    }
    .onChange(of: studioModel.lcdQualifiedAnimationVisualReviewSnapshot?.id) { identifier in
      guard identifier != nil else { return }
      qualifiedVisualReviewSnapshot = studioModel.lcdQualifiedAnimationVisualReviewSnapshot
    }
  }

  private var draftState: DisplayAnimationEditorDraftState {
    DisplayAnimationEditorDraftState(
      hasUnexportedChanges: model.hasUnexportedChanges,
      hasPendingSourceTransform: model.hasPendingSourceTransform,
      isBusy: model.isLoading || isPreparingQualifiedUpload || isQualifiedUploadActive
        || pendingQualifiedUpload != nil || qualifiedVisualReviewSnapshot != nil,
      requiresReplacementConfirmation: model.requiresReplacementConfirmation
    )
  }

  private var header: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          studioText(
            "이미지·애니메이션 편집기",
            "Image & animation editor",
            language: language
          )
        )
        .font(.title3.bold())
        Text(model.input.displayName)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      Label(
        deviceUploadCapabilityLabel,
        systemImage: deviceUploadCapabilitySymbol
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(deviceUploadCapabilityTint)
      if presentation == .sheet {
        Button(studioText("닫기", "Close", language: language)) {
          guard !isQualifiedUploadActive, !model.isLoading else { return }
          if model.requiresReplacementConfirmation {
            showsCloseDiscardConfirmation = true
          } else {
            dismiss()
          }
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isQualifiedUploadActive || model.isLoading)
        .help(
          isQualifiedUploadActive || model.isLoading
            ? studioText(
              "현재 작업이 끝날 때까지 편집기를 닫을 수 없습니다.",
              "The editor cannot close until the current operation finishes.",
              language: language
            )
            : ""
        )
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private var deviceUploadCapabilityLabel: String {
    if studioModel.lcdExtendedQualificationViewState.permitsExtendedUpload {
      return studioText("최대 140프레임 적용 가능", "Apply up to 140 frames", language: language)
    }
    if studioModel.lcdExtendedQualificationViewState.permitsMaximumBoundaryTrial {
      return studioText(
        "정확히 140프레임 경계 시험 필요",
        "Exact 140-frame boundary trial required",
        language: language
      )
    }
    return studioText("장치 업로드 잠김", "Device upload locked", language: language)
  }

  private var deviceUploadCapabilitySymbol: String {
    if studioModel.lcdExtendedQualificationViewState.permitsExtendedUpload {
      return "checkmark.shield"
    }
    if studioModel.lcdExtendedQualificationViewState.permitsMaximumBoundaryTrial {
      return "gauge.with.dots.needle.100percent"
    }
    return "lock.shield"
  }

  private var deviceUploadCapabilityTint: Color {
    if studioModel.lcdExtendedQualificationViewState.permitsExtendedUpload {
      return StudioPalette.mint
    }
    if studioModel.lcdExtendedQualificationViewState.permitsMaximumBoundaryTrial {
      return StudioPalette.coral
    }
    return .secondary
  }

  private func frameRail(project: AK47LCDAnimationProject) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(studioText("프레임", "Frames", language: language))
          .font(.headline)
        Spacer()
        Text("\(project.frames.count)/\(AK47LCDFormat.maximumFrameCount)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      ScrollView {
        LazyVStack(spacing: 7) {
          ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
            Button {
              model.selectFrame(index)
            } label: {
              HStack(spacing: 9) {
                Text("\(index + 1)")
                  .font(.caption.monospacedDigit().weight(.semibold))
                  .frame(width: 28, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                  Text("\(frame.sourceDelay.milliseconds) ms")
                    .font(.caption.monospacedDigit())
                  Text(model.deviceDelayLabel(for: frame))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(.horizontal, 9)
              .padding(.vertical, 8)
              .background(
                index == model.selectedFrameIndex
                  ? StudioPalette.blue.opacity(0.14) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 9)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 9)
                  .strokeBorder(
                    index == model.selectedFrameIndex
                      ? StudioPalette.blue.opacity(0.45) : Color.clear
                  )
              }
            }
            .buttonStyle(.plain)
          }
        }
      }

      HStack(spacing: 6) {
        Button {
          Task { await model.addFramesFromGIF() }
        } label: {
          Image(systemName: "plus")
        }
        .disabled(model.hasPendingSourceTransform || model.isLoading)
        .help(studioText("다른 GIF의 프레임 추가", "Add frames from another GIF", language: language))

        Button {
          model.duplicateSelectedFrame()
        } label: {
          Image(systemName: "plus.square.on.square")
        }
        .disabled(model.hasPendingSourceTransform || model.isLoading)
        .help(studioText("프레임 복제", "Duplicate frame", language: language))

        Button(role: .destructive) {
          model.removeSelectedFrame()
        } label: {
          Image(systemName: "trash")
        }
        .disabled(
          project.frames.count <= 1 || model.hasPendingSourceTransform || model.isLoading
        )
        .help(studioText("프레임 삭제", "Delete frame", language: language))

        Spacer()
        Button {
          model.moveSelectedFrame(by: -1)
        } label: {
          Image(systemName: "chevron.up")
        }
        .disabled(
          model.selectedFrameIndex == 0 || model.hasPendingSourceTransform || model.isLoading
        )

        Button {
          model.moveSelectedFrame(by: 1)
        } label: {
          Image(systemName: "chevron.down")
        }
        .disabled(
          model.selectedFrameIndex >= project.frames.count - 1 || model.hasPendingSourceTransform
            || model.isLoading
        )
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(16)
    .frame(width: 220)
  }

  private func previewPane(project: AK47LCDAnimationProject) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(studioText("실제 LCD 출력", "Actual LCD output", language: language))
          .font(.headline)
        Text("240×135 · 16:9")
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(.secondary)
        if model.hasPendingSourceTransform {
          Label(
            studioText("미적용 미리보기", "Unapplied preview", language: language),
            systemImage: "eye"
          )
          .font(.caption2.weight(.semibold))
          .foregroundStyle(StudioPalette.violet)
        }
        Spacer()
        Text("\(model.selectedFrameIndex + 1) / \(project.frames.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      GeometryReader { geometry in
        ZStack {
          Color.black
          if let image = model.previewImage {
            Image(nsImage: image)
              .resizable()
              .interpolation(.none)
              .frame(width: geometry.size.width, height: geometry.size.height)
          }
          if model.drawingEnabled {
            RoundedRectangle(cornerRadius: 4)
              .strokeBorder(StudioPalette.mint.opacity(0.9), lineWidth: 2)
          }
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard model.drawingEnabled, !model.hasPendingSourceTransform, !model.isLoading else {
                return
              }
              let point = devicePoint(from: value.location, canvasSize: geometry.size)
              guard drawingPoints.last != point, drawingPoints.count < 4_096 else { return }
              drawingPoints.append(point)
            }
            .onEnded { _ in
              guard model.drawingEnabled, !model.hasPendingSourceTransform, !model.isLoading else {
                drawingPoints.removeAll(keepingCapacity: true)
                return
              }
              model.applyStroke(points: drawingPoints)
              drawingPoints.removeAll(keepingCapacity: true)
            }
        )
      }
      .aspectRatio(240.0 / 135.0, contentMode: .fit)
      .background(Color.black)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.white.opacity(0.12))
      }
      .frame(maxWidth: .infinity, maxHeight: 440)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        studioText(
          "실제 LCD와 같은 240 곱하기 135, 16대 9 출력 미리보기",
          "Output preview at the LCD's exact 240 by 135, 16 by 9 aspect ratio",
          language: language
        )
      )

      Text(
        model.hasPendingSourceTransform
          ? studioText(
            "현재 화면은 원본에 크롭·맞춤을 적용한 실제 출력 미리보기입니다. 내보내기나 장치 적용 전에 아래 ‘이 화면 적용’을 눌러주세요.",
            "This is the actual output preview with crop and resize applied to the source. Choose Apply this view before exporting or sending it to the device.",
            language: language
          )
          : studioText(
            "검은 여백과 잘림까지 장치에 저장될 240×135 픽셀을 그대로 표시합니다.",
            "Shows the exact 240×135 pixels stored on the device, including black bars and clipping.",
            language: language
          )
      )
      .font(.caption2)
      .foregroundStyle(model.hasPendingSourceTransform ? StudioPalette.violet : .secondary)

      HStack(spacing: 10) {
        Button {
          model.showPreviousFrame()
        } label: {
          Image(systemName: "backward.frame.fill")
        }
        .disabled(model.selectedFrameIndex == 0)
        Button {
          model.togglePlayback()
        } label: {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            .frame(width: 18)
        }
        .disabled(project.frames.count <= 1)
        Button {
          model.showNextFrame()
        } label: {
          Image(systemName: "forward.frame.fill")
        }
        .disabled(model.selectedFrameIndex >= project.frames.count - 1)
        Spacer()
        Text(
          studioText(
            "소스 1회 \(formattedDuration(project.sourceDurationMilliseconds))",
            "Source loop \(formattedDuration(project.sourceDurationMilliseconds))",
            language: language
          )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      }
      .buttonStyle(.bordered)
      .task(id: model.playbackTaskID) {
        await model.play()
      }

      if let message = model.message {
        Label(
          message,
          systemImage: model.messageIsError ? "exclamationmark.triangle" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(model.messageIsError ? StudioPalette.coral : StudioPalette.mint)
        .lineLimit(3)
      }
      Spacer(minLength: 0)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func controls(project: AK47LCDAnimationProject) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GroupBox(studioText("프레임 지연", "Frame delay", language: language)) {
          VStack(alignment: .leading, spacing: 9) {
            Stepper(
              value: Binding(
                get: { model.selectedSourceDelayMilliseconds },
                set: { model.setSelectedSourceDelay(milliseconds: $0) }
              ),
              in: 0...AK47LCDFormat.maximumSourceDelayMilliseconds,
              step: 1
            ) {
              Text("\(model.selectedSourceDelayMilliseconds) ms")
                .monospacedDigit()
            }
            Text(model.selectedDeviceTimingDetail)
              .font(.caption.monospacedDigit())
              .foregroundStyle(
                model.selectedDelayIsDeviceEncodable ? .secondary : StudioPalette.coral)
            if model.selectedDelayUsesFirmwareMinimum {
              Text(
                studioText(
                  "raw 1…15는 펌웨어 스케줄러가 25(약 50 ms)로 올립니다.",
                  "For raw 1…15, firmware schedules 25 (about 50 ms).",
                  language: language
                )
              )
              .font(.caption2)
              .foregroundStyle(StudioPalette.violet)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 5)
        }
        .disabled(model.hasPendingSourceTransform || model.isLoading)

        GroupBox(studioText("크롭 및 맞춤", "Crop and resize", language: language)) {
          sourceTransformControls
            .padding(.top, 5)
        }

        GroupBox(studioText("텍스트", "Text", language: language)) {
          VStack(alignment: .leading, spacing: 8) {
            TextField("A–Z 0–9 - _ . : ! ? %", text: $model.textOverlay)
              .textFieldStyle(.roundedBorder)
            HStack {
              cropField("X", value: $model.textX)
              cropField("Y", value: $model.textY)
              Stepper("×\(model.textScale)", value: $model.textScale, in: 1...6)
            }
            ColorPicker(
              studioText("색상", "Color", language: language), selection: $model.authoringColor)
            Button {
              model.applyTextOverlay()
            } label: {
              Label(
                studioText("현재 프레임에 추가", "Add to current frame", language: language),
                systemImage: "textformat")
            }
          }
          .padding(.top, 5)
        }
        .disabled(model.hasPendingSourceTransform || model.isLoading)

        GroupBox(studioText("펜", "Pen", language: language)) {
          VStack(alignment: .leading, spacing: 8) {
            Toggle(
              studioText("캔버스에 그리기", "Draw on canvas", language: language),
              isOn: $model.drawingEnabled)
            Stepper(
              studioText(
                "반지름 \(model.strokeRadius) px", "Radius \(model.strokeRadius) px",
                language: language),
              value: $model.strokeRadius,
              in: 1...16
            )
            Text(
              studioText(
                "한 번의 선은 최대 4,096개 좌표로 제한됩니다.",
                "Each stroke is limited to 4,096 points.",
                language: language
              )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          .padding(.top, 5)
        }
        .disabled(model.hasPendingSourceTransform || model.isLoading)
      }
      .padding(16)
    }
    .frame(width: 310)
  }

  @ViewBuilder
  private var sourceTransformControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(
        studioText("화면 맞춤 방식", "Screen sizing mode", language: language),
        selection: Binding(
          get: { model.resizeMode },
          set: { model.setResizeMode($0) }
        )
      ) {
        Text(studioText("전체 맞춤", "Fit all", language: language)).tag(
          AK47LCDResizeMode.aspectFit)
        Text(studioText("채움/크롭", "Fill/crop", language: language)).tag(
          AK47LCDResizeMode.aspectFill)
        Text(studioText("늘이기", "Stretch", language: language)).tag(AK47LCDResizeMode.stretch)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .disabled(model.isLoading)

      Label(sourceTransformModeDescription, systemImage: sourceTransformModeSymbol)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if model.resizeMode == .aspectFill,
        let sourceImage = model.sourceOverviewImage,
        let layout = model.aspectFillLayout
      {
        LCDSourceCropMap(
          image: sourceImage,
          sourceWidth: model.sourceWidth,
          sourceHeight: model.sourceHeight,
          viewport: layout.viewport
        )
        .frame(height: 112)

        if model.sourcePreviewUsesImportedFrameReference {
          Label(
            studioText(
              "현재 프로젝트가 편집되어 불러온 원본의 \(model.sourcePreviewFrameNumber)번 프레임을 미리보기 기준으로 사용합니다.",
              "The current project has edits, so imported-source frame \(model.sourcePreviewFrameNumber) is used as the source-preview reference.",
              language: language
            ),
            systemImage: "info.circle"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }

        HStack {
          Text(
            studioText(
              "원본 \(model.sourceWidth)×\(model.sourceHeight)",
              "Source \(model.sourceWidth)×\(model.sourceHeight)",
              language: language
            )
          )
          Spacer()
          Text(
            studioText(
              "보이는 영역 \(formattedViewport(layout.viewport))",
              "Visible \(formattedViewport(layout.viewport))",
              language: language
            )
          )
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)

        cropXAxisControl(layout: layout)
        cropYAxisControl(layout: layout)

        HStack {
          Button {
            model.centerAspectFillCrop()
          } label: {
            Label(studioText("가운데", "Center", language: language), systemImage: "scope")
          }
          .disabled(
            (model.fillOffsetX == 0 && model.fillOffsetY == 0) || model.isLoading
          )
          .help(
            studioText(
              "원본의 가운데를 LCD 가운데에 맞춥니다.",
              "Centers the source inside the LCD crop window.",
              language: language
            )
          )
          Spacer()
          Text(
            studioText(
              "안쪽 화살표 1 px · 바깥 화살표 10 px",
              "Inner arrows 1 px · outer arrows 10 px",
              language: language
            )
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        .controlSize(.small)
      }

      if model.hasPendingSourceTransform {
        Divider()
        Label(
          studioText(
            "위 설정은 실제 LCD 출력으로 미리보기 중이며 아직 프로젝트에는 적용되지 않았습니다.",
            "These settings are shown as the actual LCD output, but are not applied to the project yet.",
            language: language
          ),
          systemImage: "eye"
        )
        .font(.caption2)
        .foregroundStyle(StudioPalette.violet)

        HStack {
          Button(studioText("되돌리기", "Reset", language: language)) {
            model.resetPendingSourceTransform()
          }
          Button {
            applySourceTransform()
          } label: {
            Label(
              studioText("이 화면 적용", "Apply this view", language: language),
              systemImage: "checkmark.rectangle.stack"
            )
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.blue)
          .disabled(model.isLoading)
        }
        .controlSize(.small)
      }
    }
  }

  private var sourceTransformModeDescription: String {
    switch model.resizeMode {
    case .aspectFit:
      return studioText(
        "잘림 없이 원본 전체를 240×135 안으로 축소·확대하며 비율을 유지합니다. 비율이 다르면 검은 여백이 생깁니다.",
        "Fits the entire source inside 240×135 with no cropping and preserves its proportions. Different aspect ratios produce black bars.",
        language: language
      )
    case .aspectFill:
      return studioText(
        "비율을 유지한 채 16:9 LCD를 빈틈없이 채웁니다. 화살표로 잘릴 부분을 고릅니다.",
        "Fills the 16:9 LCD without gaps while preserving aspect ratio. Use the arrows to choose what gets clipped.",
        language: language
      )
    case .stretch:
      return studioText(
        "잘림과 여백 없이 원본 전체를 240×135로 늘리므로 원본 비율이 변형됩니다.",
        "Stretches the whole source to 240×135 with no clipping or bars, which changes its proportions.",
        language: language
      )
    }
  }

  private var sourceTransformModeSymbol: String {
    switch model.resizeMode {
    case .aspectFit: "rectangle.inset.filled"
    case .aspectFill: "rectangle.fill.on.rectangle.fill"
    case .stretch: "arrow.up.left.and.arrow.down.right"
    }
  }

  private func cropXAxisControl(layout: AK47LCDAspectFillLayout) -> some View {
    HStack(spacing: 6) {
      Text("X")
        .font(.caption.monospaced().weight(.semibold))
        .frame(width: 16)
      cropNudgeButton(
        symbol: "chevron.left.2",
        accessibilityLabel: studioText("X 10픽셀 왼쪽", "Move X 10 pixels left", language: language),
        disabled: !model.canNudgeAspectFill(x: -10, y: 0)
      ) {
        model.nudgeAspectFill(x: -10, y: 0)
      }
      cropNudgeButton(
        symbol: "chevron.left",
        accessibilityLabel: studioText("X 1픽셀 왼쪽", "Move X 1 pixel left", language: language),
        disabled: !model.canNudgeAspectFill(x: -1, y: 0)
      ) {
        model.nudgeAspectFill(x: -1, y: 0)
      }
      Text(formattedSourceOffset(layout.appliedSourceOffsetX))
        .font(.caption.monospacedDigit())
        .frame(minWidth: 55)
        .accessibilityLabel(
          studioText(
            "실제 X 이동 \(formattedSourceOffset(layout.appliedSourceOffsetX)), 조작 범위 \(layout.sourcePixelOffsetXRange.lowerBound)에서 \(layout.sourcePixelOffsetXRange.upperBound)",
            "Applied X offset \(formattedSourceOffset(layout.appliedSourceOffsetX)), control range \(layout.sourcePixelOffsetXRange.lowerBound) through \(layout.sourcePixelOffsetXRange.upperBound)",
            language: language
          )
        )
      cropNudgeButton(
        symbol: "chevron.right",
        accessibilityLabel: studioText("X 1픽셀 오른쪽", "Move X 1 pixel right", language: language),
        disabled: !model.canNudgeAspectFill(x: 1, y: 0)
      ) {
        model.nudgeAspectFill(x: 1, y: 0)
      }
      cropNudgeButton(
        symbol: "chevron.right.2",
        accessibilityLabel: studioText("X 10픽셀 오른쪽", "Move X 10 pixels right", language: language),
        disabled: !model.canNudgeAspectFill(x: 10, y: 0)
      ) {
        model.nudgeAspectFill(x: 10, y: 0)
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }

  private func cropYAxisControl(layout: AK47LCDAspectFillLayout) -> some View {
    HStack(spacing: 6) {
      Text("Y")
        .font(.caption.monospaced().weight(.semibold))
        .frame(width: 16)
      cropNudgeButton(
        symbol: "chevron.up.2",
        accessibilityLabel: studioText("Y 10픽셀 위쪽", "Move Y 10 pixels up", language: language),
        disabled: !model.canNudgeAspectFill(x: 0, y: -10)
      ) {
        model.nudgeAspectFill(x: 0, y: -10)
      }
      cropNudgeButton(
        symbol: "chevron.up",
        accessibilityLabel: studioText("Y 1픽셀 위쪽", "Move Y 1 pixel up", language: language),
        disabled: !model.canNudgeAspectFill(x: 0, y: -1)
      ) {
        model.nudgeAspectFill(x: 0, y: -1)
      }
      Text(formattedSourceOffset(layout.appliedSourceOffsetY))
        .font(.caption.monospacedDigit())
        .frame(minWidth: 55)
        .accessibilityLabel(
          studioText(
            "실제 Y 이동 \(formattedSourceOffset(layout.appliedSourceOffsetY)), 조작 범위 \(layout.sourcePixelOffsetYRange.lowerBound)에서 \(layout.sourcePixelOffsetYRange.upperBound)",
            "Applied Y offset \(formattedSourceOffset(layout.appliedSourceOffsetY)), control range \(layout.sourcePixelOffsetYRange.lowerBound) through \(layout.sourcePixelOffsetYRange.upperBound)",
            language: language
          )
        )
      cropNudgeButton(
        symbol: "chevron.down",
        accessibilityLabel: studioText("Y 1픽셀 아래쪽", "Move Y 1 pixel down", language: language),
        disabled: !model.canNudgeAspectFill(x: 0, y: 1)
      ) {
        model.nudgeAspectFill(x: 0, y: 1)
      }
      cropNudgeButton(
        symbol: "chevron.down.2",
        accessibilityLabel: studioText("Y 10픽셀 아래쪽", "Move Y 10 pixels down", language: language),
        disabled: !model.canNudgeAspectFill(x: 0, y: 10)
      ) {
        model.nudgeAspectFill(x: 0, y: 10)
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }

  private func cropNudgeButton(
    symbol: String,
    accessibilityLabel: String,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 13)
    }
    .disabled(disabled || model.isLoading)
    .accessibilityLabel(accessibilityLabel)
    .help(accessibilityLabel)
  }

  private func applySourceTransform() {
    if model.wouldDiscardEditsWhenApplyingSourceTransform {
      showsRerenderDiscardConfirmation = true
    } else {
      Task { await model.applyPendingSourceTransform() }
    }
  }

  private func formattedViewport(_ viewport: AK47LCDSourceViewport) -> String {
    "\(Int(viewport.width.rounded()))×\(Int(viewport.height.rounded()))"
  }

  private func formattedSourceOffset(_ offset: Double) -> String {
    if offset.rounded() == offset { return "\(Int(offset)) px" }
    return String(format: "%+.2f px", offset)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      qualifiedUploadStatus

      if let qualifiedUploadPreparationError {
        Label(qualifiedUploadPreparationError, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      }

      HStack(spacing: 10) {
        if model.isLoading || isPreparingQualifiedUpload {
          ProgressView()
            .controlSize(.small)
        }
        Label(
          qualifiedUploadBoundaryText,
          systemImage: studioModel.canPrepareQualifiedLCDAnimation
            ? "checkmark.shield" : "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Spacer()
        Button {
          Task { await model.exportEditedGIF() }
        } label: {
          Label(
            studioText("편집 GIF 내보내기…", "Export edited GIF…", language: language),
            systemImage: "photo.stack")
        }
        .disabled(
          model.project == nil || model.hasPendingSourceTransform || model.isLoading
            || isQualifiedUploadActive
        )
        .help(
          model.hasPendingSourceTransform
            ? studioText(
              "먼저 크롭 미리보기의 ‘이 화면 적용’을 눌러주세요.",
              "Apply the crop preview to the project first.",
              language: language
            ) : ""
        )
        Button {
          Task { await model.exportLCDContainer() }
        } label: {
          Label(
            studioText("LCD 컨테이너 내보내기…", "Export LCD container…", language: language),
            systemImage: "shippingbox")
        }
        .disabled(
          !model.canEncodeDeviceContainer || model.hasPendingSourceTransform || model.isLoading
            || isQualifiedUploadActive
        )
        .help(model.containerExportHelp(language: language))
        Button(role: .destructive) {
          Task { await prepareQualifiedUploadConfirmation() }
        } label: {
          Label(
            maximumBoundaryTrialPending
              ? studioText(
                "140프레임 경계 시험…",
                "Run 140-frame boundary trial…",
                language: language
              )
              : studioText(
                "현재 편집을 장치에 적용…",
                "Apply current edit to device…",
                language: language
              ),
            systemImage: "display.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.coral)
        .disabled(!canPrepareQualifiedUpload)
        .help(qualifiedUploadHelp)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 13)
  }

  @ViewBuilder
  private var qualifiedUploadStatus: some View {
    switch studioModel.lcdQualifiedAnimationUploadState {
    case .idle:
      EmptyView()
    case .uploading(let completedPages, let totalPages):
      VStack(alignment: .leading, spacing: 5) {
        ProgressView(value: Double(completedPages), total: Double(totalPages))
        Text(
          LCDUploadProgressPresentation.text(
            completedAcknowledgements: completedPages,
            totalAcknowledgements: totalPages,
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    case .succeeded(let frameCount, let acknowledgedPages, _):
      HStack(spacing: 10) {
        Label(
          studioText(
            "\(frameCount)프레임 전송 완료(ACK \(acknowledgedPages)회). ‘결과 비교’를 눌러 실제 LCD를 확인하세요.",
            "\(frameCount)-frame transfer complete (\(acknowledgedPages) ACKs). Choose Compare result and check the actual LCD.",
            language: language
          ),
          systemImage: "eye.trianglebadge.exclamationmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let snapshot = studioModel.lcdQualifiedAnimationVisualReviewSnapshot,
          studioModel.canConfirmQualifiedLCDAnimationVisualResult
        {
          Button(studioText("결과 비교…", "Compare result…", language: language)) {
            qualifiedVisualReviewSnapshot = snapshot
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.blue)
        }
      }
    case .failed(let acknowledgedPages, let message):
      VStack(alignment: .leading, spacing: 4) {
        Label(
          studioText(
            "확장 전송 중단 · expected input \(acknowledgedPages)회",
            "Extended transfer stopped · \(acknowledgedPages) expected inputs",
            language: language
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(StudioPalette.coral)
        Text(message)
          .font(.caption2.monospaced())
          .textSelection(.enabled)
        Text(
          studioText(
            "재시도하지 말고 Device Inspector의 USB-mode cable-removal 복구 절차를 진행하세요.",
            "Do not retry. Follow Device Inspector's USB-mode cable-removal recovery flow.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var canPrepareQualifiedUpload: Bool {
    guard let project = model.project else { return false }
    let frameCountAllowed =
      maximumBoundaryTrialPending
      ? project.frames.count == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
      : (1...AK47LCDUploadAdapter.qualifiedMaximumFrameCount).contains(project.frames.count)
    return studioModel.canPrepareAnyLCDAnimation
      && frameCountAllowed
      && model.canEncodeDeviceContainer
      && !model.hasPendingSourceTransform
      && !model.isLoading
      && !isPreparingQualifiedUpload
      && !isQualifiedUploadActive
  }

  private var isQualifiedUploadActive: Bool {
    if case .uploading = studioModel.lcdQualifiedAnimationUploadState { return true }
    return false
  }

  private var maximumBoundaryTrialPending: Bool {
    studioModel.lcdExtendedQualificationViewState.permitsMaximumBoundaryTrial
  }

  private var qualifiedUploadBoundaryText: String {
    if model.hasPendingSourceTransform {
      return studioText(
        "크롭 미리보기를 프로젝트에 적용한 뒤 내보내기·장치 적용 가능",
        "Apply the crop preview to the project before export or device upload",
        language: language
      )
    }
    if maximumBoundaryTrialPending {
      guard model.project?.frames.count == AK47LCDUploadAdapter.qualifiedMaximumFrameCount else {
        return studioText(
          "일반 Apply는 잠겨 있습니다. 현재 편집을 정확히 140프레임으로 만든 뒤 경계 시험을 진행하세요.",
          "General Apply is locked. Make the current edit exactly 140 frames to run the boundary trial.",
          language: language
        )
      }
      return studioText(
        "140프레임 경계 시험을 시작할 준비가 됐습니다.",
        "The 140-frame boundary test is ready to start.",
        language: language
      )
    }
    guard studioModel.canPrepareQualifiedLCDAnimation else {
      return studioText(
        "장치 적용 준비가 끝나지 않았습니다. 아래 ‘장치 적용 준비·복구’에서 다음 단계를 확인하세요.",
        "Device Apply is not ready. Check Device Apply readiness & recovery below for the next step.",
        language: language
      )
    }
    return studioText(
      "현재 편집을 장치에 적용할 준비가 됐습니다.",
      "The current edit is ready to apply to the device.",
      language: language
    )
  }

  private var qualifiedUploadHelp: String {
    guard let project = model.project else {
      return studioText(
        "먼저 이미지나 애니메이션을 불러오세요.",
        "Load an image or animation first.",
        language: language
      )
    }
    if model.hasPendingSourceTransform {
      return studioText(
        "지금 보이는 크롭은 미리보기입니다. ‘이 화면 적용’을 먼저 눌러주세요.",
        "The visible crop is still a preview. Choose Apply this view first.",
        language: language
      )
    }
    if project.frames.count > AK47LCDUploadAdapter.qualifiedMaximumFrameCount {
      return studioText(
        "\(project.frames.count)프레임입니다. 최대 140프레임이며 자동 자르기나 강제 전송은 하지 않습니다.",
        "This edit has \(project.frames.count) frames. The maximum is 140; no truncation or forced upload is performed.",
        language: language
      )
    }
    if !model.canEncodeDeviceContainer {
      return studioText(
        "모든 source delay가 0…511 ms 범위여야 합니다.",
        "Every source delay must be within 0...511 ms.",
        language: language
      )
    }
    return qualifiedUploadBoundaryText
  }

  private func prepareQualifiedUploadConfirmation() async {
    guard let project = model.project, !model.hasPendingSourceTransform else { return }
    isPreparingQualifiedUpload = true
    qualifiedUploadPreparationError = nil
    defer { isPreparingQualifiedUpload = false }
    do {
      // `project` is a value snapshot. Detached encoding and the final sheet
      // never reload the older library source or observe later editor changes.
      pendingQualifiedUpload = try await studioModel.prepareQualifiedLCDAnimation(
        project: project
      )
    } catch {
      qualifiedUploadPreparationError = error.localizedDescription
    }
  }

  private func cropField(_ label: String, value: Binding<Int>) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
      TextField("", value: value, format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 48)
    }
  }

  private func devicePoint(from location: CGPoint, canvasSize: CGSize) -> AK47LCDPixelPoint {
    let x = min(
      AK47LCDFormat.canvasWidth - 1,
      max(0, Int((location.x / max(1, canvasSize.width)) * Double(AK47LCDFormat.canvasWidth)))
    )
    let y = min(
      AK47LCDFormat.canvasHeight - 1,
      max(0, Int((location.y / max(1, canvasSize.height)) * Double(AK47LCDFormat.canvasHeight)))
    )
    return AK47LCDPixelPoint(x: x, y: y)
  }

  private func formattedDuration(_ milliseconds: Int) -> String {
    if milliseconds < 1_000 { return "\(milliseconds) ms" }
    return String(format: "%.2f s", Double(milliseconds) / 1_000)
  }
}

private struct LCDSourceCropMap: View {
  @Environment(\.studioLanguage) private var language
  let image: NSImage
  let sourceWidth: Int
  let sourceHeight: Int
  let viewport: AK47LCDSourceViewport

  var body: some View {
    GeometryReader { geometry in
      let imageRectangle = aspectFitRectangle(in: geometry.size)
      let cropRectangle = scaledViewport(in: imageRectangle)

      ZStack(alignment: .topLeading) {
        Color.black.opacity(0.85)
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .frame(width: imageRectangle.width, height: imageRectangle.height)
          .position(x: imageRectangle.midX, y: imageRectangle.midY)

        Path { path in
          path.addRect(imageRectangle)
          path.addRect(cropRectangle)
        }
        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))

        Rectangle()
          .strokeBorder(StudioPalette.mint, lineWidth: 2)
          .background(StudioPalette.mint.opacity(0.05))
          .frame(width: cropRectangle.width, height: cropRectangle.height)
          .position(x: cropRectangle.midX, y: cropRectangle.midY)

        Text(studioText("원본 크롭 지도", "Source crop map", language: language))
          .font(.caption2.weight(.semibold))
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(.black.opacity(0.68), in: Capsule())
          .padding(6)
      }
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay {
        RoundedRectangle(cornerRadius: 7)
          .strokeBorder(Color.white.opacity(0.14))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      studioText(
        "원본 이미지에서 LCD에 보이는 영역. 박스 밖의 어두운 부분은 잘립니다.",
        "The part of the source visible on the LCD. Dimmed areas outside the box are clipped.",
        language: language
      )
    )
  }

  private func aspectFitRectangle(in availableSize: CGSize) -> CGRect {
    guard sourceWidth > 0, sourceHeight > 0 else { return .zero }
    let scale = min(
      availableSize.width / CGFloat(sourceWidth),
      availableSize.height / CGFloat(sourceHeight)
    )
    let size = CGSize(width: CGFloat(sourceWidth) * scale, height: CGFloat(sourceHeight) * scale)
    return CGRect(
      x: (availableSize.width - size.width) / 2,
      y: (availableSize.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
  }

  private func scaledViewport(in imageRectangle: CGRect) -> CGRect {
    guard sourceWidth > 0, sourceHeight > 0 else { return .zero }
    let scaleX = imageRectangle.width / CGFloat(sourceWidth)
    let scaleY = imageRectangle.height / CGFloat(sourceHeight)
    return CGRect(
      x: imageRectangle.minX + CGFloat(viewport.x) * scaleX,
      y: imageRectangle.minY + CGFloat(viewport.y) * scaleY,
      width: CGFloat(viewport.width) * scaleX,
      height: CGFloat(viewport.height) * scaleY
    )
  }
}

private struct LCDQualifiedUploadConfirmationSheet: View {
  @Environment(\.studioLanguage) private var language
  let snapshot: LCDQualifiedAnimationSnapshot
  let onConfirm: () -> Void

  @State private var applyAcknowledgement = LCDExperimentalApplyAcknowledgement()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          Text(
            confirmationTitle
          )
          .font(.title2.bold())
          Text(
            confirmationSubtitle
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        GroupBox(studioText("Exact plan", "Exact plan", language: language)) {
          VStack(alignment: .leading, spacing: 9) {
            summaryRow(
              studioText("대상", "Target", language: language),
              "\(summary.target.product) · USB 0C45:800A"
            )
            summaryRow(
              studioText("Revision / location", "Revision / location", language: language),
              String(
                format: "0x%04llX / 0x%08llX",
                summary.target.versionNumber,
                summary.target.locationID
              )
            )
            summaryRow(
              studioText("Serial", "Serial", language: language),
              summary.target.serialNumber
                ?? studioText("없음", "Absent", language: language)
            )
            summaryRow(
              studioText("프레임", "Frames", language: language),
              "\(summary.frameCount) / \(AK47LCDUploadAdapter.qualifiedMaximumFrameCount)"
            )
            summaryRow(
              studioText("페이지 / 예상 input", "Pages / expected inputs", language: language),
              "\(summary.pageCount) / \(summary.expectedInputAcknowledgementCount)"
            )
            summaryRow(
              studioText("컨테이너", "Container", language: language),
              "\(summary.containerByteCount.formatted()) bytes"
            )
            summaryRow(
              studioText("전송 주소", "Transfer addresses", language: language),
              String(
                format: "[0x%llX, 0x%llX)",
                summary.transferStartAddress,
                summary.transferEndAddressExclusive
              )
            )
            Divider()
            Text("SHA-256")
              .font(.caption.weight(.semibold))
            Text(summary.containerSHA256)
              .font(.caption2.monospaced())
              .textSelection(.enabled)
          }
          .padding(.top, 6)
        }

        GroupBox(studioText("지연 변환", "Delay conversion", language: language)) {
          VStack(alignment: .leading, spacing: 7) {
            Label(delayRangeText, systemImage: "timer")
            if oddDelayFrameIndices.isEmpty {
              Label(
                studioText(
                  "홀수 source delay의 1 ms 절삭 없음",
                  "No 1 ms truncation from odd source delays",
                  language: language
                ),
                systemImage: "checkmark.circle"
              )
            } else {
              Label(
                studioText(
                  "홀수 source delay는 integer /2 과정에서 1 ms를 잃습니다: frame \(formattedFrameIndices(oddDelayFrameIndices))",
                  "Odd source delays lose 1 ms during integer /2 encoding: frames \(formattedFrameIndices(oddDelayFrameIndices))",
                  language: language
                ),
                systemImage: "exclamationmark.triangle"
              )
            }
            if summary.firmwareMinimumAppliedFrameIndices.isEmpty {
              Label(
                studioText(
                  "firmware minimum timing 적용 frame 없음",
                  "No frame uses the firmware minimum timing",
                  language: language
                ),
                systemImage: "checkmark.circle"
              )
            } else {
              Label(
                studioText(
                  "firmware minimum timing이 적용됩니다: frame \(formattedFrameIndices(summary.firmwareMinimumAppliedFrameIndices))",
                  "Firmware minimum timing applies to frames \(formattedFrameIndices(summary.firmwareMinimumAppliedFrameIndices))",
                  language: language
                ),
                systemImage: "exclamationmark.triangle"
              )
            }
          }
          .font(.caption)
          .padding(.top, 6)
        }

        GroupBox(
          studioText(
            "실험 기능 확인", "Experimental feature acknowledgement", language: language)
        ) {
          VStack(alignment: .leading, spacing: 10) {
            riskToggle(
              studioText(
                LCDExperimentalApplyAcknowledgement.koreanText,
                LCDExperimentalApplyAcknowledgement.englishText,
                language: language
              ),
              isOn: $applyAcknowledgement.isAcknowledged
            )
          }
          .toggleStyle(.checkbox)
          .padding(.top, 6)
        }

        HStack {
          Label(
            studioText(
              snapshot.purpose == .maximumBoundaryTrial
                ? "이 경계 승인은 정확히 140프레임·2215페이지와 위 SHA·exact target인 plan 하나에만 유효합니다."
                : "승인은 위 SHA와 exact target을 포함한 plan 하나에만 유효합니다.",
              snapshot.purpose == .maximumBoundaryTrial
                ? "This boundary authorization is valid only for this exact 140-frame, 2,215-page plan with the shown SHA and target."
                : "Authorization is valid only for this one plan, including the shown SHA and exact target.",
              language: language
            ),
            systemImage: "lock.shield"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Spacer()
          Button(
            snapshot.purpose == .maximumBoundaryTrial
              ? studioText(
                "140프레임 경계 시험 한 번 실행",
                "Run 140-frame boundary trial once",
                language: language
              )
              : studioText(
                "이 snapshot 한 번 적용",
                "Apply this snapshot once",
                language: language
              ),
            role: .destructive
          ) {
            guard applyAcknowledgement.consume() else { return }
            onConfirm()
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.coral)
          .disabled(!applyAcknowledgement.canApply)
        }
      }
      .padding(24)
    }
    .frame(minWidth: 660, idealWidth: 700, minHeight: 650, idealHeight: 760)
  }

  private var summary: AK47LCDQualifiedUploadPlanSummary { snapshot.summary }

  private var confirmationTitle: String {
    if snapshot.purpose == .maximumBoundaryTrial {
      return studioText(
        "140프레임 경계 시험 확인",
        "Confirm 140-frame boundary test",
        language: language
      )
    }
    return studioText(
      "현재 편집 적용 확인",
      "Confirm current edit Apply",
      language: language
    )
  }

  private var confirmationSubtitle: String {
    if snapshot.purpose == .maximumBoundaryTrial {
      return studioText(
        "지금 표시된 140프레임만 한 번 전송합니다. 이후 편집 내용은 이번 전송에 반영되지 않습니다.",
        "Only the 140 frames shown here will be sent once. Later edits will not affect this transfer.",
        language: language
      )
    }
    return studioText(
      "지금 표시된 편집 내용만 한 번 전송합니다. 이후 편집 내용은 이번 전송에 반영되지 않습니다.",
      "Only the edit shown here will be sent once. Later edits will not affect this transfer.",
      language: language
    )
  }

  private var oddDelayFrameIndices: [Int] {
    snapshot.plan.container.sourceDelaysMilliseconds.enumerated().compactMap {
      $0.element.isMultiple(of: 2) ? nil : $0.offset
    }
  }

  private var delayRangeText: String {
    let source = snapshot.plan.container.sourceDelaysMilliseconds
    let effective = snapshot.plan.container.effectiveDeviceDelaysMilliseconds
    guard let sourceMinimum = source.min(), let sourceMaximum = source.max(),
      let effectiveMinimum = effective.min(), let effectiveMaximum = effective.max()
    else {
      return studioText("지연 정보 없음", "No delay metadata", language: language)
    }
    return studioText(
      "source \(sourceMinimum)…\(sourceMaximum) ms → firmware effective \(effectiveMinimum)…\(effectiveMaximum) ms",
      "Source \(sourceMinimum)...\(sourceMaximum) ms → firmware effective \(effectiveMinimum)...\(effectiveMaximum) ms",
      language: language
    )
  }

  private func formattedFrameIndices(_ zeroBasedIndices: [Int]) -> String {
    let visible = zeroBasedIndices.prefix(24).map { String($0 + 1) }.joined(separator: ", ")
    return zeroBasedIndices.count > 24 ? "\(visible), …" : visible
  }

  private func summaryRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.callout.monospacedDigit())
        .textSelection(.enabled)
    }
  }

  private func riskToggle(_ label: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      Text(label)
        .font(.caption)
    }
  }
}

struct LCDQualifiedUploadVisualReviewSheet: View {
  @Environment(\.studioLanguage) private var language
  let snapshot: LCDQualifiedAnimationSnapshot
  let canConfirmCorrect: Bool
  let canReportMismatch: Bool
  let onConfirmCorrect: () -> Void
  let onReportMismatch: () -> Void

  @State private var frameIndex = 0
  @State private var isPlaying = true
  @State private var showsMismatchConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(
          visualReviewTitle
        )
        .font(.title2.bold())
        Text(
          studioText(
            "아래 화면은 실제 전송한 RGB565 데이터를 다시 표시한 것입니다. 키보드 LCD와 내용·순서·방향·색을 직접 비교하세요.",
            "The preview below reproduces the RGB565 data that was actually sent. Compare its content, order, orientation, and colors with the keyboard LCD.",
            language: language
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      ZStack {
        Color.black
        if let expectedImage {
          Image(nsImage: expectedImage)
            .resizable()
            .interpolation(.none)
        } else {
          Label(
            studioText("예상 frame을 표시할 수 없음", "Expected frame unavailable", language: language),
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(StudioPalette.coral)
        }
      }
      .aspectRatio(240.0 / 135.0, contentMode: .fit)
      .frame(maxWidth: .infinity, maxHeight: 420)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.white.opacity(0.16))
      }

      HStack(spacing: 10) {
        Button {
          isPlaying = false
          frameIndex = max(0, frameIndex - 1)
        } label: {
          Image(systemName: "backward.frame.fill")
        }
        .disabled(frameIndex == 0)

        Button {
          isPlaying.toggle()
        } label: {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .frame(width: 18)
        }
        .disabled(snapshot.project.frames.count <= 1)

        Button {
          isPlaying = false
          frameIndex = min(snapshot.project.frames.count - 1, frameIndex + 1)
        } label: {
          Image(systemName: "forward.frame.fill")
        }
        .disabled(frameIndex >= snapshot.project.frames.count - 1)

        Slider(
          value: Binding(
            get: { Double(frameIndex) },
            set: {
              isPlaying = false
              frameIndex = min(
                snapshot.project.frames.count - 1,
                max(0, Int($0.rounded()))
              )
            }
          ),
          in: 0...Double(max(1, snapshot.project.frames.count - 1)),
          step: 1
        )
        .disabled(snapshot.project.frames.count <= 1)

        Text("\(frameIndex + 1) / \(snapshot.project.frames.count)")
          .font(.caption.monospacedDigit())
        Text("\(currentEffectiveDelayMilliseconds) ms")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      GroupBox(studioText("비교 대상", "Comparison identity", language: language)) {
        VStack(alignment: .leading, spacing: 7) {
          comparisonRow(
            studioText("프레임 / 페이지", "Frames / pages", language: language),
            "\(snapshot.summary.frameCount) / \(snapshot.summary.pageCount)"
          )
          comparisonRow(
            studioText("대상", "Target", language: language),
            String(
              format: "%@ · rev 0x%04llX · loc 0x%08llX",
              snapshot.summary.target.product,
              snapshot.summary.target.versionNumber,
              snapshot.summary.target.locationID
            )
          )
          comparisonRow(
            studioText("Serial", "Serial", language: language),
            snapshot.summary.target.serialNumber
              ?? studioText("없음", "Absent", language: language)
          )
          Divider()
          Text("SHA-256")
            .font(.caption.weight(.semibold))
          Text(snapshot.summary.containerSHA256)
            .font(.caption2.monospaced())
            .textSelection(.enabled)
        }
        .padding(.top, 5)
      }

      HStack(alignment: .center, spacing: 12) {
        Text(
          studioText(
            "판단을 미루면 자격은 잠긴 채 유지됩니다. 정확함을 추정하지 마세요.",
            "If you defer the decision, qualification remains locked. Do not infer correctness.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Spacer()
        Button(
          studioText("틀림 또는 확인 불가…", "Wrong or unverifiable…", language: language),
          role: .destructive
        ) {
          showsMismatchConfirmation = true
        }
        .disabled(!canReportMismatch)
        Button(
          isMaximumBoundaryTrial
            ? studioText(
              "일치 기록 후 전원 복구로",
              "Record match and continue to power recovery",
              language: language
            )
            : studioText(
              "정확히 일치함 기록",
              "Record exact visual match",
              language: language
            )
        ) {
          onConfirmCorrect()
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.mint)
        .disabled(!canConfirmCorrect || expectedImage == nil)
      }
    }
    .padding(24)
    .frame(minWidth: 720, idealWidth: 780, minHeight: 650, idealHeight: 720)
    .interactiveDismissDisabled(canReportMismatch)
    .task(id: playbackTaskID) {
      guard isPlaying, snapshot.project.frames.count > 1 else { return }
      try? await Task.sleep(
        nanoseconds: UInt64(max(1, currentEffectiveDelayMilliseconds)) * 1_000_000
      )
      guard !Task.isCancelled else { return }
      frameIndex = (frameIndex + 1) % snapshot.project.frames.count
    }
    .confirmationDialog(
      studioText(
        "자격을 폐기하고 장치를 격리할까요?",
        "Revoke qualification and quarantine the device?",
        language: language
      ),
      isPresented: $showsMismatchConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        studioText(
          "틀림/확인 불가 기록 및 격리",
          "Record wrong/unverifiable and quarantine",
          language: language
        ),
        role: .destructive
      ) {
        onReportMismatch()
      }
      .disabled(!canReportMismatch)
      Button(studioText("계속 비교", "Keep comparing", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          isMaximumBoundaryTrial
            ? "이 선택은 140프레임 경계 provenance를 폐기하고 장치를 격리합니다. 재시도하지 말고 USB-mode cable-removal 복구 뒤 새 고정 진단부터 진행하세요."
            : "이 선택은 영속 140프레임 자격을 폐기합니다. 재시도하지 말고 USB mode에서 cable을 분리해 완전 무전원·real absence·same-port exact4 복구 뒤 새 고정 진단부터 진행하세요.",
          isMaximumBoundaryTrial
            ? "This revokes the 140-frame boundary provenance and quarantines the device. Do not retry; complete USB-mode cable-removal recovery, then restart from a fresh fixed diagnostic."
            : "This revokes the durable 140-frame qualification. Do not retry; in USB mode, remove the cable and complete unpowered, real-absence, same-port exact-four recovery before a fresh fixed diagnostic.",
          language: language
        )
      )
    }
  }

  private var isMaximumBoundaryTrial: Bool {
    snapshot.purpose == .maximumBoundaryTrial
  }

  private var visualReviewTitle: String {
    if isMaximumBoundaryTrial {
      return studioText(
        "140프레임 전송 결과 비교",
        "Compare the 140-frame transfer result",
        language: language
      )
    }
    return studioText(
      "전송 결과 비교",
      "Compare transfer result",
      language: language
    )
  }

  private var expectedImage: NSImage? {
    guard
      let decoded = try? LCDQualifiedUploadPreviewDecoder.decodeFrame(
        from: snapshot.plan.container,
        at: frameIndex
      ),
      let cgImage = decoded.makeCGImage()
    else { return nil }
    return NSImage(
      cgImage: cgImage,
      size: NSSize(width: AK47LCDFormat.canvasWidth, height: AK47LCDFormat.canvasHeight)
    )
  }

  private var currentEffectiveDelayMilliseconds: Int {
    guard snapshot.plan.container.effectiveDeviceDelaysMilliseconds.indices.contains(frameIndex)
    else { return 1 }
    return snapshot.plan.container.effectiveDeviceDelaysMilliseconds[frameIndex]
  }

  private var playbackTaskID: String {
    "\(isPlaying)-\(frameIndex)-\(snapshot.id)"
  }

  private func comparisonRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.caption.monospacedDigit())
        .textSelection(.enabled)
    }
  }
}

@MainActor
final class DisplayAnimationEditorModel: ObservableObject {
  let input: DisplayAnimationEditorInput

  @Published private(set) var project: AK47LCDAnimationProject?
  @Published private(set) var previewImage: NSImage?
  @Published private(set) var previewFrameImage: AK47LCDRGBAImage?
  @Published private(set) var sourceOverviewImage: NSImage?
  @Published private(set) var selectedFrameIndex = 0
  @Published private(set) var isLoading = false
  @Published private(set) var message: String?
  @Published private(set) var messageIsError = false
  @Published private(set) var isPlaying = false
  @Published private var playbackRevision = 0
  @Published private(set) var resizeMode: AK47LCDResizeMode = .aspectFit
  @Published private(set) var fillOffsetX = 0
  @Published private(set) var fillOffsetY = 0
  @Published var textOverlay = "KEYCANVAS"
  @Published var textX = 8
  @Published var textY = 8
  @Published var textScale = 2
  @Published var authoringColor = Color.white
  @Published var drawingEnabled = false
  @Published var strokeRadius = 2

  private var decodedSource: AK47LCDDecodedGIF?
  private var lastExportedProject: AK47LCDAnimationProject?
  private var sourceRenderedProject: AK47LCDAnimationProject?
  private var appliedResizeMode: AK47LCDResizeMode = .aspectFit
  private var appliedFillOffsetX = 0
  private var appliedFillOffsetY = 0
  private var sourceTransformRevision = 0
  private var sourceOverviewFrameIndex: Int?
  private var hasExportedPreparedSource = false
  private let sourceTransformRenderer: DisplaySourceTransformRenderer

  init(
    input: DisplayAnimationEditorInput,
    sourceTransformRenderer: @escaping DisplaySourceTransformRenderer =
      defaultDisplaySourceTransformRenderer
  ) {
    self.input = input
    self.sourceTransformRenderer = sourceTransformRenderer
  }

  var selectedSourceDelayMilliseconds: Int {
    guard let project, project.frames.indices.contains(selectedFrameIndex) else { return 100 }
    return project.frames[selectedFrameIndex].sourceDelay.milliseconds
  }

  var selectedDelayIsDeviceEncodable: Bool {
    selectedDeviceDelay != nil
  }

  var selectedDelayUsesFirmwareMinimum: Bool {
    selectedDeviceDelay?.usesFirmwareMinimum == true
  }

  var selectedDeviceTimingDetail: String {
    guard let delay = selectedDeviceDelay else {
      return "Device: unavailable (source must be 0…511 ms)"
    }
    return
      "Device raw \(delay.rawValue) · nominal \(delay.nominalMilliseconds) ms · firmware \(delay.effectiveFirmwareMilliseconds) ms"
  }

  var canEncodeDeviceContainer: Bool {
    guard let project else { return false }
    return project.frames.allSatisfy {
      (try? AK47LCDDeviceDelay(verifiedSourceDelay: $0.sourceDelay)) != nil
    }
  }

  var hasUnexportedChanges: Bool {
    guard let project else { return false }
    return project != lastExportedProject || hasPendingSourceTransform
  }

  var requiresReplacementConfirmation: Bool {
    hasUnexportedChanges
      || (input.preparedDecodedSource != nil
        && input.preparedSourceRequiresExport
        && !hasExportedPreparedSource)
  }

  var hasPendingSourceTransform: Bool {
    guard decodedSource != nil else { return false }
    if resizeMode != appliedResizeMode { return true }
    guard resizeMode == .aspectFill else { return false }
    return fillOffsetX != appliedFillOffsetX || fillOffsetY != appliedFillOffsetY
  }

  var wouldDiscardEditsWhenApplyingSourceTransform: Bool {
    guard hasPendingSourceTransform, let project else { return false }
    return project != sourceRenderedProject
  }

  var sourcePreviewUsesImportedFrameReference: Bool {
    guard let project else { return false }
    return project != sourceRenderedProject
  }

  var sourcePreviewFrameNumber: Int {
    guard let decodedSource, !decodedSource.frames.isEmpty else { return 0 }
    return min(selectedFrameIndex, decodedSource.frames.count - 1) + 1
  }

  var sourceWidth: Int {
    decodedSource?.sourceWidth ?? 0
  }

  var sourceHeight: Int {
    decodedSource?.sourceHeight ?? 0
  }

  var aspectFillLayout: AK47LCDAspectFillLayout? {
    guard let decodedSource, let transform = currentAspectFillTransform else { return nil }
    return try? transform.resolved(
      sourceWidth: decodedSource.sourceWidth,
      sourceHeight: decodedSource.sourceHeight
    )
  }

  var playbackTaskID: String {
    "\(isPlaying):\(playbackRevision)"
  }

  func loadIfNeeded() async {
    guard project == nil, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let decoded: AK47LCDDecodedGIF
      if let preparedDecodedSource = input.preparedDecodedSource {
        decoded = preparedDecodedSource
      } else {
        let sourceURL = input.sourceURL
        let fallback = input.fallbackDelayMilliseconds
        decoded = try await Task.detached(priority: .userInitiated) {
          try AK47LCDGIFDecoder.decode(
            url: sourceURL,
            fallbackDelayMilliseconds: fallback
          )
        }.value
      }
      decodedSource = decoded
      project = try decoded.makeProject(resizeMode: resizeMode)
      lastExportedProject = project
      sourceRenderedProject = project
      appliedResizeMode = resizeMode
      appliedFillOffsetX = fillOffsetX
      appliedFillOffsetY = fillOffsetY
      selectedFrameIndex = 0
      refreshPreview()
      succeed("Loaded \(decoded.frames.count) fully composited local frame(s).")
    } catch {
      fail(error)
    }
  }

  func selectFrame(_ index: Int) {
    guard let project, project.frames.indices.contains(index) else { return }
    selectedFrameIndex = index
    isPlaying = false
    playbackRevision += 1
    refreshPreview()
  }

  func duplicateSelectedFrame() {
    mutateProject { project in
      try project.duplicateFrame(at: selectedFrameIndex)
      selectedFrameIndex += 1
    }
  }

  func removeSelectedFrame() {
    mutateProject { project in
      try project.removeFrame(at: selectedFrameIndex)
      selectedFrameIndex = min(selectedFrameIndex, project.frames.count - 1)
    }
  }

  func moveSelectedFrame(by offset: Int) {
    let destination = selectedFrameIndex + offset
    mutateProject { project in
      try project.moveFrame(from: selectedFrameIndex, to: destination)
      selectedFrameIndex = destination
    }
  }

  func setSelectedSourceDelay(milliseconds: Int) {
    mutateProject(showSuccess: false) { project in
      try project.setSourceDelay(milliseconds: milliseconds, at: selectedFrameIndex)
    }
  }

  func showPreviousFrame() {
    selectFrame(max(0, selectedFrameIndex - 1))
  }

  func showNextFrame() {
    guard let project else { return }
    selectFrame(min(project.frames.count - 1, selectedFrameIndex + 1))
  }

  func togglePlayback() {
    isPlaying.toggle()
    playbackRevision += 1
  }

  func play() async {
    guard isPlaying, let project, project.frames.count > 1 else { return }
    while !Task.isCancelled, isPlaying {
      guard let current = self.project?.frames[safe: selectedFrameIndex] else { return }
      let delay = max(16, current.sourceDelay.milliseconds)
      do {
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
      } catch {
        return
      }
      guard !Task.isCancelled, isPlaying, let active = self.project else { return }
      selectedFrameIndex = (selectedFrameIndex + 1) % active.frames.count
      refreshPreview()
    }
  }

  func addFramesFromGIF() async {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.gif]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isLoading = true
    defer { isLoading = false }
    do {
      let fallback = input.fallbackDelayMilliseconds
      let mode = resizeMode
      let decoded = try await Task.detached(priority: .userInitiated) {
        try AK47LCDGIFDecoder.decode(url: url, fallbackDelayMilliseconds: fallback)
      }.value
      let addition = try decoded.makeProject(resizeMode: mode)
      guard var updated = project else { return }
      let firstAddedIndex = updated.frames.count
      try updated.append(contentsOf: addition.frames)
      project = updated
      selectedFrameIndex = firstAddedIndex
      refreshPreview()
      succeed("Added \(addition.frames.count) frame(s) from a local GIF.")
    } catch {
      fail(error)
    }
  }

  func setResizeMode(_ mode: AK47LCDResizeMode) {
    guard resizeMode != mode, !isLoading else { return }
    resizeMode = mode
    sourceTransformRevision += 1
    clampAspectFillOffsetsIfNeeded()
    isPlaying = false
    playbackRevision += 1
    refreshPreview()
  }

  func nudgeAspectFill(x deltaX: Int, y deltaY: Int) {
    guard resizeMode == .aspectFill, !isLoading, let decodedSource else { return }
    do {
      let currentLayout = try AK47LCDAspectFillTransform.centered.resolved(
        sourceWidth: decodedSource.sourceWidth,
        sourceHeight: decodedSource.sourceHeight
      )
      let requestedX = min(
        currentLayout.sourcePixelOffsetXRange.upperBound,
        max(currentLayout.sourcePixelOffsetXRange.lowerBound, fillOffsetX + deltaX)
      )
      let requestedY = min(
        currentLayout.sourcePixelOffsetYRange.upperBound,
        max(currentLayout.sourcePixelOffsetYRange.lowerBound, fillOffsetY + deltaY)
      )
      let transform = try AK47LCDAspectFillTransform.sourcePixels(
        x: Double(requestedX),
        y: Double(requestedY)
      )
      _ = try transform.resolved(
        sourceWidth: decodedSource.sourceWidth,
        sourceHeight: decodedSource.sourceHeight
      )
      // Preserve the clamped requested integer at fractional crop extremes.
      // The resolved layout separately exposes the exact applied Double value.
      fillOffsetX = requestedX
      fillOffsetY = requestedY
      sourceTransformRevision += 1
      isPlaying = false
      playbackRevision += 1
      refreshPreview()
    } catch {
      fail(error)
    }
  }

  func canNudgeAspectFill(x deltaX: Int, y deltaY: Int) -> Bool {
    guard resizeMode == .aspectFill, let layout = aspectFillLayout else { return false }
    if deltaX < 0, fillOffsetX > layout.sourcePixelOffsetXRange.lowerBound { return true }
    if deltaX > 0, fillOffsetX < layout.sourcePixelOffsetXRange.upperBound { return true }
    if deltaY < 0, fillOffsetY > layout.sourcePixelOffsetYRange.lowerBound { return true }
    if deltaY > 0, fillOffsetY < layout.sourcePixelOffsetYRange.upperBound { return true }
    return false
  }

  func centerAspectFillCrop() {
    guard resizeMode == .aspectFill, fillOffsetX != 0 || fillOffsetY != 0, !isLoading else {
      return
    }
    fillOffsetX = 0
    fillOffsetY = 0
    sourceTransformRevision += 1
    isPlaying = false
    playbackRevision += 1
    refreshPreview()
  }

  func resetPendingSourceTransform() {
    guard hasPendingSourceTransform, !isLoading else { return }
    resizeMode = appliedResizeMode
    fillOffsetX = appliedFillOffsetX
    fillOffsetY = appliedFillOffsetY
    sourceTransformRevision += 1
    isPlaying = false
    playbackRevision += 1
    refreshPreview()
    succeed("Reset the live crop preview to the applied project.")
  }

  func applyPendingSourceTransform() async {
    guard hasPendingSourceTransform, !isLoading, let decodedSource, let currentProject = project
    else { return }

    let mode = resizeMode
    let transform = currentAspectFillTransform
    let revision = sourceTransformRevision
    let renderer = sourceTransformRenderer
    let preservedDelays =
      currentProject.frames.count == decodedSource.frames.count
      ? currentProject.frames.map(\.sourceDelay.milliseconds) : nil

    isLoading = true
    isPlaying = false
    playbackRevision += 1
    defer { isLoading = false }

    do {
      let rendered = try await Task.detached(priority: .userInitiated) {
        var updated = try renderer(decodedSource, mode, transform)
        if let preservedDelays {
          for (index, milliseconds) in preservedDelays.enumerated() {
            try updated.setSourceDelay(milliseconds: milliseconds, at: index)
          }
        }
        return updated
      }.value

      guard revision == sourceTransformRevision, project == currentProject else {
        succeed(
          "The source view or project changed while rendering; the newer local edit was kept unapplied."
        )
        refreshPreview()
        return
      }

      project = rendered
      sourceRenderedProject = rendered
      appliedResizeMode = mode
      appliedFillOffsetX = fillOffsetX
      appliedFillOffsetY = fillOffsetY
      selectedFrameIndex = min(selectedFrameIndex, rendered.frames.count - 1)
      refreshPreview()
      succeed("Applied the exact 240×135 source view to every original frame.")
    } catch {
      fail(error)
    }
  }

  func applyTextOverlay() {
    mutateProject { project in
      try project.drawBitmapText(
        at: selectedFrameIndex,
        text: textOverlay,
        origin: AK47LCDPixelPoint(x: textX, y: textY),
        scale: textScale,
        color: rgbaColor
      )
    }
  }

  func applyStroke(points: [AK47LCDPixelPoint]) {
    guard !points.isEmpty else { return }
    mutateProject(showSuccess: false) { project in
      try project.drawStroke(
        at: selectedFrameIndex,
        points: points,
        radius: strokeRadius,
        color: rgbaColor
      )
    }
  }

  func exportEditedGIF() async {
    guard let project, !hasPendingSourceTransform else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.gif]
    panel.nameFieldStringValue =
      input.sourceURL.deletingPathExtension().lastPathComponent
      + "-edited.gif"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isLoading = true
    defer { isLoading = false }
    do {
      let data = try await Task.detached(priority: .userInitiated) {
        try AK47LCDGIFEncoder.encode(project)
      }.value
      try data.write(to: url, options: .atomic)
      lastExportedProject = project
      hasExportedPreparedSource = true
      succeed("Exported an edited GIF without changing the library source.")
    } catch {
      fail(error)
    }
  }

  func exportLCDContainer() async {
    guard let project, !hasPendingSourceTransform else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.data]
    panel.nameFieldStringValue =
      input.sourceURL.deletingPathExtension().lastPathComponent
      + ".ak47lcd.bin"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isLoading = true
    defer { isLoading = false }
    do {
      let encoded = try await Task.detached(priority: .userInitiated) {
        try AK47LCDContainerEncoder.encode(project: project)
      }.value
      try encoded.data.write(to: url, options: .atomic)
      succeed(
        "Exported \(encoded.pageCount) complete 4096-byte pages (\(encoded.data.count) bytes)."
      )
    } catch {
      fail(error)
    }
  }

  func deviceDelayLabel(for frame: AK47LCDAnimationFrame) -> String {
    guard let delay = try? AK47LCDDeviceDelay(verifiedSourceDelay: frame.sourceDelay) else {
      return "device: blocked"
    }
    return "raw \(delay.rawValue) → \(delay.effectiveFirmwareMilliseconds) ms"
  }

  func containerExportHelp(language: AppLanguage) -> String {
    if hasPendingSourceTransform {
      return studioText(
        "먼저 크롭 미리보기의 ‘이 화면 적용’을 눌러주세요.",
        "Apply the crop preview to the project first.",
        language: language
      )
    }
    guard canEncodeDeviceContainer else {
      return studioText(
        "모든 소스 지연을 0…511 ms로 맞춰야 byte wrap 없이 인코딩할 수 있습니다.",
        "Every source delay must be 0…511 ms to encode without byte wrapping.",
        language: language
      )
    }
    return studioText(
      "로컬 RGB565 컨테이너 파일만 만들며 장치로 전송하지 않습니다.",
      "Creates a local RGB565 container file only and does not send it to the device.",
      language: language
    )
  }

  private var selectedDeviceDelay: AK47LCDDeviceDelay? {
    guard let project, let frame = project.frames[safe: selectedFrameIndex] else { return nil }
    return try? AK47LCDDeviceDelay(verifiedSourceDelay: frame.sourceDelay)
  }

  private var rgbaColor: AK47LCDRGBAColor {
    guard let converted = NSColor(authoringColor).usingColorSpace(.sRGB) else { return .white }
    return AK47LCDRGBAColor(
      red: UInt8(clamping: Int((converted.redComponent * 255).rounded())),
      green: UInt8(clamping: Int((converted.greenComponent * 255).rounded())),
      blue: UInt8(clamping: Int((converted.blueComponent * 255).rounded())),
      alpha: UInt8(clamping: Int((converted.alphaComponent * 255).rounded()))
    )
  }

  private var currentAspectFillTransform: AK47LCDAspectFillTransform? {
    try? AK47LCDAspectFillTransform.sourcePixels(
      x: Double(fillOffsetX),
      y: Double(fillOffsetY)
    )
  }

  private func clampAspectFillOffsetsIfNeeded() {
    guard let layout = aspectFillLayout else { return }
    fillOffsetX = min(
      layout.sourcePixelOffsetXRange.upperBound,
      max(layout.sourcePixelOffsetXRange.lowerBound, fillOffsetX)
    )
    fillOffsetY = min(
      layout.sourcePixelOffsetYRange.upperBound,
      max(layout.sourcePixelOffsetYRange.lowerBound, fillOffsetY)
    )
  }

  private func mutateProject(
    showSuccess: Bool = true,
    _ mutation: (inout AK47LCDAnimationProject) throws -> Void
  ) {
    guard var updated = project else { return }
    do {
      try mutation(&updated)
      project = updated
      isPlaying = false
      playbackRevision += 1
      refreshPreview()
      if showSuccess {
        succeed("Updated the local animation draft.")
      }
    } catch {
      fail(error)
    }
  }

  private func refreshPreview() {
    refreshSourceOverview()

    let outputImage: AK47LCDRGBAImage?
    if hasPendingSourceTransform, let sourceFrame = selectedDecodedSourceFrame {
      do {
        if resizeMode == .aspectFill, let layout = aspectFillLayout {
          outputImage = try sourceFrame.image.renderedForDevice(aspectFillLayout: layout)
        } else {
          outputImage = try sourceFrame.image.renderedForDevice(mode: resizeMode)
        }
      } catch {
        outputImage = nil
        fail(error)
      }
    } else {
      outputImage = project?.frames[safe: selectedFrameIndex]?.image
    }

    guard let outputImage, let cgImage = outputImage.makeCGImage() else {
      previewFrameImage = nil
      previewImage = nil
      return
    }
    previewFrameImage = outputImage
    previewImage = NSImage(
      cgImage: cgImage,
      size: NSSize(width: AK47LCDFormat.canvasWidth, height: AK47LCDFormat.canvasHeight)
    )
  }

  private var selectedDecodedSourceFrame: AK47LCDDecodedGIFFrame? {
    guard let decodedSource, let sourceIndex = selectedDecodedSourceFrameIndex else { return nil }
    return decodedSource.frames[sourceIndex]
  }

  private var selectedDecodedSourceFrameIndex: Int? {
    guard let decodedSource, !decodedSource.frames.isEmpty else { return nil }
    return min(selectedFrameIndex, decodedSource.frames.count - 1)
  }

  private func refreshSourceOverview() {
    guard let sourceIndex = selectedDecodedSourceFrameIndex,
      let sourceFrame = selectedDecodedSourceFrame
    else {
      sourceOverviewFrameIndex = nil
      sourceOverviewImage = nil
      return
    }
    guard sourceOverviewFrameIndex != sourceIndex || sourceOverviewImage == nil else { return }
    guard let cgImage = sourceFrame.image.makeCGImage() else {
      sourceOverviewFrameIndex = nil
      sourceOverviewImage = nil
      return
    }
    sourceOverviewFrameIndex = sourceIndex
    sourceOverviewImage = NSImage(
      cgImage: cgImage,
      size: NSSize(width: sourceFrame.image.width, height: sourceFrame.image.height)
    )
  }

  private func succeed(_ message: String) {
    self.message = message
    messageIsError = false
  }

  private func fail(_ error: Error) {
    message = error.localizedDescription
    messageIsError = true
    isPlaying = false
    playbackRevision += 1
  }
}

extension Collection {
  fileprivate subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
