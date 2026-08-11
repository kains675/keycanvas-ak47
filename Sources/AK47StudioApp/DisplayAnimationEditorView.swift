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
}

struct DisplayAnimationEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.studioLanguage) private var language
  @ObservedObject private var studioModel: StudioModel
  @StateObject private var model: DisplayAnimationEditorModel
  @State private var drawingPoints: [AK47LCDPixelPoint] = []
  @State private var showsCloseDiscardConfirmation = false
  @State private var showsRerenderDiscardConfirmation = false
  @State private var pendingQualifiedUpload: LCDQualifiedAnimationSnapshot?
  @State private var qualifiedVisualReviewSnapshot: LCDQualifiedAnimationSnapshot?
  @State private var isPreparingQualifiedUpload = false
  @State private var qualifiedUploadPreparationError: String?

  init(input: DisplayAnimationEditorInput, studioModel: StudioModel) {
    self.studioModel = studioModel
    _model = StateObject(wrappedValue: DisplayAnimationEditorModel(input: input))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if model.isLoading, model.project == nil {
        ProgressView(
          studioText("GIF 프레임을 안전하게 해제하는 중…", "Safely decoding GIF frames…", language: language)
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
          Text(studioText("GIF를 열 수 없습니다", "Could not open GIF", language: language))
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
    .frame(minWidth: 1_050, idealWidth: 1_130, minHeight: 690, idealHeight: 760)
    .task {
      await model.loadIfNeeded()
    }
    .interactiveDismissDisabled(model.hasUnexportedChanges || isQualifiedUploadActive)
    .alert(
      studioText("내보내지 않은 편집을 버릴까요?", "Discard unexported edits?", language: language),
      isPresented: $showsCloseDiscardConfirmation
    ) {
      Button(studioText("계속 편집", "Keep editing", language: language), role: .cancel) {}
      Button(studioText("버리고 닫기", "Discard and close", language: language), role: .destructive) {
        dismiss()
      }
    } message: {
      Text(
        studioText(
          "마지막 편집 GIF 내보내기 이후의 변경사항이 사라집니다. LCD 컨테이너는 다시 편집할 수 있는 프로젝트 파일이 아닙니다.",
          "Changes made after the last edited-GIF export will be lost. An LCD container is not a reopenable project file.",
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
        studioText("편집을 버리고 다시 렌더링", "Discard edits and render again", language: language),
        role: .destructive
      ) {
        model.rerenderOriginalFrames()
      }
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "추가한 프레임과 모든 픽셀 편집이 사라지고 처음 가져온 GIF만 다시 사용됩니다.",
          "Added frames and all pixel edits will be removed; only the initially imported GIF is rendered again.",
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

  private var header: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text(studioText("오프라인 GIF 편집기", "Offline GIF editor", language: language))
          .font(.title3.bold())
        Text(model.input.displayName)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      Label(
        studioModel.lcdExtendedQualificationViewState.permitsExtendedUpload
          ? studioText("최대 40프레임 적용 가능", "Apply up to 40 frames", language: language)
          : studioText("장치 업로드 잠김", "Device upload locked", language: language),
        systemImage: studioModel.lcdExtendedQualificationViewState.permitsExtendedUpload
          ? "checkmark.shield" : "lock.shield"
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(
        studioModel.lcdExtendedQualificationViewState.permitsExtendedUpload
          ? StudioPalette.mint : .secondary
      )
      Button(studioText("닫기", "Close", language: language)) {
        guard !isQualifiedUploadActive else { return }
        if model.hasUnexportedChanges {
          showsCloseDiscardConfirmation = true
        } else {
          dismiss()
        }
      }
      .keyboardShortcut(.cancelAction)
      .disabled(isQualifiedUploadActive)
      .help(
        isQualifiedUploadActive
          ? studioText(
            "장치 전송이 끝날 때까지 편집기를 닫을 수 없습니다.",
            "The editor cannot close until the device transfer finishes.",
            language: language
          )
          : ""
      )
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
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
        .help(studioText("다른 GIF의 프레임 추가", "Add frames from another GIF", language: language))

        Button {
          model.duplicateSelectedFrame()
        } label: {
          Image(systemName: "plus.square.on.square")
        }
        .help(studioText("프레임 복제", "Duplicate frame", language: language))

        Button(role: .destructive) {
          model.removeSelectedFrame()
        } label: {
          Image(systemName: "trash")
        }
        .disabled(project.frames.count <= 1)
        .help(studioText("프레임 삭제", "Delete frame", language: language))

        Spacer()
        Button {
          model.moveSelectedFrame(by: -1)
        } label: {
          Image(systemName: "chevron.up")
        }
        .disabled(model.selectedFrameIndex == 0)

        Button {
          model.moveSelectedFrame(by: 1)
        } label: {
          Image(systemName: "chevron.down")
        }
        .disabled(model.selectedFrameIndex >= project.frames.count - 1)
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
        Text(studioText("240×135 결과", "240×135 result", language: language))
          .font(.headline)
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
              guard model.drawingEnabled else { return }
              let point = devicePoint(from: value.location, canvasSize: geometry.size)
              guard drawingPoints.last != point, drawingPoints.count < 4_096 else { return }
              drawingPoints.append(point)
            }
            .onEnded { _ in
              guard model.drawingEnabled else {
                drawingPoints.removeAll(keepingCapacity: true)
                return
              }
              model.applyStroke(points: drawingPoints)
              drawingPoints.removeAll(keepingCapacity: true)
            }
        )
      }
      .aspectRatio(240.0 / 135.0, contentMode: .fit)
      .frame(maxWidth: .infinity, maxHeight: 440)
      .background(Color.black)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.white.opacity(0.12))
      }

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

        GroupBox(studioText("크롭 및 맞춤", "Crop and resize", language: language)) {
          VStack(alignment: .leading, spacing: 9) {
            Picker("", selection: $model.resizeMode) {
              Text(studioText("맞춤", "Fit", language: language)).tag(AK47LCDResizeMode.aspectFit)
              Text(studioText("채움/크롭", "Fill/crop", language: language)).tag(
                AK47LCDResizeMode.aspectFill)
              Text(studioText("늘이기", "Stretch", language: language)).tag(AK47LCDResizeMode.stretch)
            }
            .pickerStyle(.segmented)

            Toggle(
              studioText("사용자 크롭", "Custom crop", language: language),
              isOn: $model.customCropEnabled)
            if model.customCropEnabled {
              Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                  cropField("X", value: $model.cropX)
                  cropField("Y", value: $model.cropY)
                }
                GridRow {
                  cropField("W", value: $model.cropWidth)
                  cropField("H", value: $model.cropHeight)
                }
              }
            }
            Button {
              if model.hasUnexportedChanges {
                showsRerenderDiscardConfirmation = true
              } else {
                model.rerenderOriginalFrames()
              }
            } label: {
              Label(
                studioText("원본에서 다시 렌더링", "Render again from source", language: language),
                systemImage: "rectangle.arrowtriangle.2.outward"
              )
            }
            .help(
              studioText(
                "현재 프레임 편집은 버리고 가져온 원본에 크롭/맞춤을 적용합니다.",
                "Discards current frame edits and reapplies crop/resize to the imported source.",
                language: language
              )
            )
          }
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
      }
      .padding(16)
    }
    .frame(width: 310)
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
        .disabled(model.project == nil || model.isLoading || isQualifiedUploadActive)
        Button {
          Task { await model.exportLCDContainer() }
        } label: {
          Label(
            studioText("LCD 컨테이너 내보내기…", "Export LCD container…", language: language),
            systemImage: "shippingbox")
        }
        .disabled(
          !model.canEncodeDeviceContainer || model.isLoading || isQualifiedUploadActive
        )
        .help(model.containerExportHelp(language: language))
        Button(role: .destructive) {
          Task { await prepareQualifiedUploadConfirmation() }
        } label: {
          Label(
            studioText("현재 편집을 장치에 적용…", "Apply current edit to device…", language: language),
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
          studioText(
            "장기 전송 중 · expected input \(completedPages) / \(totalPages). 앱 종료·sleep·케이블 분리를 하지 마세요.",
            "Long transfer in progress · expected inputs \(completedPages) / \(totalPages). Do not quit, sleep, or disconnect the cable.",
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
            "\(frameCount)프레임 host sequence 완료 · expected input \(acknowledgedPages)회. LCD 육안 검증 전에는 성공으로 확정하지 않습니다.",
            "\(frameCount)-frame host sequence completed · \(acknowledgedPages) expected inputs. Success is not established before visual LCD review.",
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
    return studioModel.canPrepareQualifiedLCDAnimation
      && (1...AK47LCDUploadAdapter.qualifiedMaximumFrameCount).contains(project.frames.count)
      && model.canEncodeDeviceContainer
      && !model.isLoading
      && !isPreparingQualifiedUpload
      && !isQualifiedUploadActive
  }

  private var isQualifiedUploadActive: Bool {
    if case .uploading = studioModel.lcdQualifiedAnimationUploadState { return true }
    return false
  }

  private var qualifiedUploadBoundaryText: String {
    guard studioModel.canPrepareQualifiedLCDAnimation else {
      return studioText(
        "Core의 전체 영속 qualification receipt가 검증되기 전까지 Apply 잠김",
        "Apply is locked until Core validates the complete durable qualification receipt",
        language: language
      )
    }
    return studioText(
      "현재 in-memory 편집을 복사해 exact snapshot으로만 승인",
      "Copies the current in-memory edit and authorizes only that exact snapshot",
      language: language
    )
  }

  private var qualifiedUploadHelp: String {
    guard let project = model.project else {
      return studioText("먼저 GIF를 불러오세요.", "Load a GIF first.", language: language)
    }
    if project.frames.count > AK47LCDUploadAdapter.qualifiedMaximumFrameCount {
      return studioText(
        "\(project.frames.count)프레임입니다. 최대 40프레임이며 자동 자르기나 강제 전송은 하지 않습니다.",
        "This edit has \(project.frames.count) frames. The maximum is 40; no truncation or forced upload is performed.",
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
    guard let project = model.project else { return }
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

private struct LCDQualifiedUploadConfirmationSheet: View {
  @Environment(\.studioLanguage) private var language
  let snapshot: LCDQualifiedAnimationSnapshot
  let onConfirm: () -> Void

  @State private var acknowledgesOverwrite = false
  @State private var acknowledgesNoReadbackOrRollback = false
  @State private var acknowledgesInputsAreNotAcceptance = false
  @State private var confirmsLongTransferSafety = false
  @State private var confirmsRecoveryPrepared = false
  @State private var confirmationConsumed = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          Text(
            studioText(
              "현재 편집 snapshot 최종 확인",
              "Final current-edit snapshot confirmation",
              language: language
            )
          )
          .font(.title2.bold())
          Text(
            studioText(
              "이 창을 열 때 복사·인코딩한 불변 값입니다. 이후 편집이나 library 원본 변경은 이 plan에 반영되지 않습니다.",
              "This is the immutable value copied and encoded when this sheet opened. Later edits or library-source changes cannot alter this plan.",
              language: language
            )
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

        GroupBox(studioText("필수 위험 확인", "Required risk acknowledgements", language: language)) {
          VStack(alignment: .leading, spacing: 10) {
            riskToggle(
              studioText(
                "현재 LCD 사용자 이미지를 이 snapshot으로 덮어씁니다.",
                "This snapshot overwrites the current user LCD image.",
                language: language
              ),
              isOn: $acknowledgesOverwrite
            )
            riskToggle(
              studioText(
                "현재 이미지를 읽어 오거나 backup·rollback하는 기능이 없습니다.",
                "There is no current-image readback, backup, or rollback.",
                language: language
              ),
              isOn: $acknowledgesNoReadbackOrRollback
            )
            riskToggle(
              studioText(
                "페이지마다 예상 input을 확인하지만 page/flash 수락이나 화면 결과 증명은 아닙니다.",
                "An expected input is checked after every page, but it is not page/flash acceptance or visible-result proof.",
                language: language
              ),
              isOn: $acknowledgesInputsAreNotAcceptance
            )
            riskToggle(
              studioText(
                "장기 전송 동안 앱 종료·Mac sleep/shutdown·케이블 분리를 피하고 다른 keyboard utility와 Windows VM을 닫았습니다.",
                "During this long transfer I will avoid app quit, Mac sleep/shutdown, and cable removal, and I closed other keyboard utilities and Windows VMs.",
                language: language
              ),
              isOn: $confirmsLongTransferSafety
            )
            riskToggle(
              studioText(
                "실패 시 재시도하지 않고 selector를 USB 위치에 둔 cable-removal→real absence→same-port exact4 복구를 진행합니다. 2.4G/BT 전환은 복구가 아닙니다.",
                "On failure I will not retry; I will keep USB mode and perform cable removal → real absence → same-port exact-four recovery. Switching to 2.4G/BT is not recovery.",
                language: language
              ),
              isOn: $confirmsRecoveryPrepared
            )
          }
          .toggleStyle(.checkbox)
          .padding(.top, 6)
        }

        HStack {
          Label(
            studioText(
              "승인은 위 SHA와 exact target을 포함한 plan 하나에만 유효합니다.",
              "Authorization is valid only for this one plan, including the shown SHA and exact target.",
              language: language
            ),
            systemImage: "lock.shield"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Spacer()
          Button(
            studioText("이 snapshot 한 번 적용", "Apply this snapshot once", language: language),
            role: .destructive
          ) {
            guard allRisksAcknowledged, !confirmationConsumed else { return }
            confirmationConsumed = true
            onConfirm()
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioPalette.coral)
          .disabled(!allRisksAcknowledged || confirmationConsumed)
        }
      }
      .padding(24)
    }
    .frame(minWidth: 660, idealWidth: 700, minHeight: 650, idealHeight: 760)
  }

  private var summary: AK47LCDQualifiedUploadPlanSummary { snapshot.summary }

  private var allRisksAcknowledged: Bool {
    acknowledgesOverwrite
      && acknowledgesNoReadbackOrRollback
      && acknowledgesInputsAreNotAcceptance
      && confirmsLongTransferSafety
      && confirmsRecoveryPrepared
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
          studioText(
            "실제 LCD와 불변 예상 애니메이션 비교",
            "Compare the actual LCD with the immutable expected animation",
            language: language
          )
        )
        .font(.title2.bold())
        Text(
          studioText(
            "host sequence 완료는 화면 성공의 증명이 아닙니다. 아래 미리보기는 source RGBA가 아니라 실제 제출한 little-endian RGB565 바이트를 다시 해석한 결과입니다. 내용·순서·방향·색을 키보드 LCD와 직접 비교하세요.",
            "Host-sequence completion does not prove the visible result. The preview below decodes the exact submitted little-endian RGB565 bytes, not the source RGBA. Compare its content, order, orientation, and colors directly with the keyboard LCD.",
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
          studioText("정확히 일치함 기록", "Record exact visual match", language: language)
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
          "이 선택은 영속 40프레임 자격을 폐기합니다. 재시도하지 말고 USB mode에서 cable을 분리해 완전 무전원·real absence·same-port exact4 복구 뒤 새 고정 진단부터 진행하세요.",
          "This revokes the durable 40-frame qualification. Do not retry; in USB mode, remove the cable and complete unpowered, real-absence, same-port exact-four recovery before a fresh fixed diagnostic.",
          language: language
        )
      )
    }
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
  @Published private(set) var selectedFrameIndex = 0
  @Published private(set) var isLoading = false
  @Published private(set) var message: String?
  @Published private(set) var messageIsError = false
  @Published private(set) var isPlaying = false
  @Published private var playbackRevision = 0
  @Published var resizeMode: AK47LCDResizeMode = .aspectFit
  @Published var customCropEnabled = false
  @Published var cropX = 0
  @Published var cropY = 0
  @Published var cropWidth = 240
  @Published var cropHeight = 135
  @Published var textOverlay = "KEYCANVAS"
  @Published var textX = 8
  @Published var textY = 8
  @Published var textScale = 2
  @Published var authoringColor = Color.white
  @Published var drawingEnabled = false
  @Published var strokeRadius = 2

  private var decodedSource: AK47LCDDecodedGIF?
  private var lastExportedProject: AK47LCDAnimationProject?

  init(input: DisplayAnimationEditorInput) {
    self.input = input
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
    return project != lastExportedProject
  }

  var playbackTaskID: String {
    "\(isPlaying):\(playbackRevision)"
  }

  func loadIfNeeded() async {
    guard project == nil, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let sourceURL = input.sourceURL
      let fallback = input.fallbackDelayMilliseconds
      let decoded = try await Task.detached(priority: .userInitiated) {
        try AK47LCDGIFDecoder.decode(
          url: sourceURL,
          fallbackDelayMilliseconds: fallback
        )
      }.value
      decodedSource = decoded
      cropWidth = decoded.sourceWidth
      cropHeight = decoded.sourceHeight
      project = try decoded.makeProject(resizeMode: resizeMode)
      lastExportedProject = project
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

  func rerenderOriginalFrames() {
    guard let decodedSource else { return }
    do {
      let crop =
        customCropEnabled
        ? AK47LCDPixelRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        : nil
      project = try decodedSource.makeProject(
        resizeMode: resizeMode,
        cropRectangle: crop
      )
      selectedFrameIndex = min(selectedFrameIndex, (project?.frames.count ?? 1) - 1)
      refreshPreview()
      succeed("Re-rendered the imported source; prior pixel edits were discarded.")
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
    guard let project else { return }
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
      succeed("Exported an edited GIF without changing the library source.")
    } catch {
      fail(error)
    }
  }

  func exportLCDContainer() async {
    guard let project else { return }
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
    guard canEncodeDeviceContainer else {
      return studioText(
        "모든 소스 지연을 0…511 ms로 맞춰야 byte wrap 없이 인코딩할 수 있습니다.",
        "Every source delay must be 0…511 ms to encode without byte wrapping.",
        language: language
      )
    }
    return studioText(
      "검증된 로컬 RGB565 컨테이너 파일만 만듭니다. 내보내기는 장치 전송을 승인하지 않으며, 자격이 검증된 editor snapshot Apply는 별도 exact-plan 확인이 필요합니다.",
      "Creates only a validated local RGB565 container file. Export does not authorize device transfer; qualified editor-snapshot Apply requires a separate exact-plan confirmation.",
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
    guard let project, let frame = project.frames[safe: selectedFrameIndex],
      let cgImage = frame.image.makeCGImage()
    else {
      previewImage = nil
      return
    }
    previewImage = NSImage(
      cgImage: cgImage,
      size: NSSize(width: AK47LCDFormat.canvasWidth, height: AK47LCDFormat.canvasHeight)
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
