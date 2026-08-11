import AK47InspectorCore
import SwiftUI

struct LocalVideoClipSelectionInput: Identifiable, Equatable {
  let id = UUID()
  let descriptor: LocalVideoImportDescriptor

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }
}

struct LocalVideoClipSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.studioLanguage) private var language
  @StateObject private var model: LocalVideoClipSelectionModel
  let onComplete: (LocalVideoImportResult) -> Void

  init(
    input: LocalVideoClipSelectionInput,
    onComplete: @escaping (LocalVideoImportResult) -> Void
  ) {
    _model = StateObject(
      wrappedValue: LocalVideoClipSelectionModel(descriptor: input.descriptor)
    )
    self.onComplete = onComplete
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("영상 구간 선택", "Choose video range", language: language))
            .font(.title3.bold())
          Text(model.descriptor.sourceURL.lastPathComponent)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
        Label(
          "\(model.descriptor.metadata.width)×\(model.descriptor.metadata.height)",
          systemImage: "rectangle.inset.filled"
        )
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 14) {
        timeControl(
          title: studioText("시작", "Start", language: language),
          milliseconds: Binding(
            get: { model.startMilliseconds },
            set: { model.setStartMilliseconds($0) }
          ),
          range: 0...max(0, model.endMilliseconds - 1)
        )
        timeControl(
          title: studioText("끝", "End", language: language),
          milliseconds: Binding(
            get: { model.endMilliseconds },
            set: { model.setEndMilliseconds($0) }
          ),
          range: min(
            model.startMilliseconds + 1, model.durationMilliseconds)...model
            .durationMilliseconds
        )

        HStack {
          Text(studioText("초당 프레임", "Frames per second", language: language))
          Spacer()
          Stepper(
            "\(model.framesPerSecond) FPS",
            value: $model.framesPerSecond,
            in: AK47LCDVideoSelection
              .minimumFramesPerSecond...AK47LCDVideoSelection
              .maximumFramesPerSecond
          )
          .monospacedDigit()
          .fixedSize()
        }
      }
      .disabled(model.isExtracting)

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          if let plan = model.plan {
            summaryRow(
              studioText("예상 프레임", "Expected frames", language: language),
              "\(plan.expectedFrameCount) / \(AK47LCDFormat.maximumFrameCount)"
            )
            summaryRow(
              studioText("편집 소스 크기", "Editor source size", language: language),
              "≤ \(plan.maximumExtractionWidth)×\(plan.maximumExtractionHeight)"
            )
            summaryRow(
              studioText("디코드 작업량", "Decoded work", language: language),
              ByteCountFormatter.string(
                fromByteCount: Int64(plan.estimatedDecodedPixelCount * 4),
                countStyle: .memory
              )
            )
          } else if let planningError = model.planningError {
            Label(planningError, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(StudioPalette.coral)
          }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(studioText("변환 미리 계산", "Conversion preflight", language: language))
      }

      if model.isExtracting {
        VStack(alignment: .leading, spacing: 7) {
          ProgressView(value: model.progressFraction)
          Text(
            studioText(
              "프레임 \(model.completedFrameCount) / \(model.totalFrameCount) 변환 중…",
              "Converting frame \(model.completedFrameCount) / \(model.totalFrameCount)…",
              language: language
            )
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
      }

      if let errorMessage = model.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      }

      Label(
        studioText(
          "가장 가까운 영상 프레임을 선택 간격의 절반 안에서 사용합니다. 원본 영상은 바꾸거나 보관함에 복사하지 않으며, 편집 결과는 GIF로 내보내야 보존됩니다.",
          "The nearest source frame within half a sample interval is used. The original video is neither changed nor copied into the library; export an edited GIF to preserve the result.",
          language: language
        ),
        systemImage: "lock.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Button(studioText("취소", "Cancel", language: language), role: .cancel) {
          model.cancel()
          dismiss()
        }
        Spacer()
        Button {
          model.extract { result in
            onComplete(result)
          }
        } label: {
          Label(
            studioText("편집기에서 열기", "Open in editor", language: language),
            systemImage: "slider.horizontal.3"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
        .disabled(model.plan == nil || model.isExtracting)
      }
    }
    .padding(22)
    .frame(width: 560)
    .interactiveDismissDisabled(model.isExtracting)
    .onDisappear { model.cancel() }
  }

  private func timeControl(
    title: String,
    milliseconds: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Text(formattedTime(milliseconds.wrappedValue))
          .font(.callout.monospacedDigit().weight(.semibold))
      }
      Slider(
        value: Binding(
          get: { Double(milliseconds.wrappedValue) },
          set: { milliseconds.wrappedValue = Int($0.rounded()) }
        ),
        in: Double(range.lowerBound)...Double(max(range.lowerBound, range.upperBound)),
        step: Double(model.timeControlStepMilliseconds)
      )
    }
  }

  private func summaryRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
    }
  }

  private func formattedTime(_ milliseconds: Int) -> String {
    String(format: "%.3f s", Double(milliseconds) / 1_000)
  }
}

@MainActor
final class LocalVideoClipSelectionModel: ObservableObject {
  let descriptor: LocalVideoImportDescriptor
  @Published private(set) var startMilliseconds: Int
  @Published private(set) var endMilliseconds: Int
  @Published var framesPerSecond: Int
  @Published private(set) var isExtracting = false
  @Published private(set) var completedFrameCount = 0
  @Published private(set) var totalFrameCount = 0
  @Published private(set) var errorMessage: String?
  private var extractionTask: Task<Void, Never>?
  private var extractionGeneration: UUID?

  init(descriptor: LocalVideoImportDescriptor) {
    self.descriptor = descriptor
    let recommended = try? AK47LCDVideoSelection.recommended(for: descriptor.metadata)
    startMilliseconds = recommended?.startMilliseconds ?? 0
    endMilliseconds = recommended?.endMilliseconds ?? descriptor.metadata.durationMilliseconds
    framesPerSecond =
      recommended?.framesPerSecond
      ?? AK47LCDVideoSelection.recommendedFramesPerSecond
  }

  var durationMilliseconds: Int { descriptor.metadata.durationMilliseconds }

  var timeControlStepMilliseconds: Int {
    durationMilliseconds >= 100 ? 50 : 1
  }

  var selection: AK47LCDVideoSelection? {
    try? AK47LCDVideoSelection(
      startMilliseconds: startMilliseconds,
      endMilliseconds: endMilliseconds,
      framesPerSecond: framesPerSecond
    )
  }

  var plan: AK47LCDVideoImportPlan? {
    guard let selection else { return nil }
    return try? AK47LCDVideoImportPlan(metadata: descriptor.metadata, selection: selection)
  }

  var planningError: String? {
    do {
      let selection = try AK47LCDVideoSelection(
        startMilliseconds: startMilliseconds,
        endMilliseconds: endMilliseconds,
        framesPerSecond: framesPerSecond
      )
      _ = try AK47LCDVideoImportPlan(metadata: descriptor.metadata, selection: selection)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  var progressFraction: Double {
    guard totalFrameCount > 0 else { return 0 }
    return Double(completedFrameCount) / Double(totalFrameCount)
  }

  func setStartMilliseconds(_ value: Int) {
    startMilliseconds = min(max(0, value), max(0, endMilliseconds - 1))
    errorMessage = nil
  }

  func setEndMilliseconds(_ value: Int) {
    endMilliseconds = min(
      durationMilliseconds,
      max(startMilliseconds + 1, value)
    )
    errorMessage = nil
  }

  func extract(
    onComplete: @escaping @MainActor @Sendable (LocalVideoImportResult) -> Void
  ) {
    guard !isExtracting, let selection, let plan else { return }
    isExtracting = true
    completedFrameCount = 0
    totalFrameCount = plan.expectedFrameCount
    errorMessage = nil
    let generation = UUID()
    extractionGeneration = generation
    let descriptor = descriptor
    // Capture one stable MainActor reference for the @Sendable progress sink.
    // Capturing the outer task's mutable weak-self storage would be a Swift 6
    // data-race error.
    let progressModel = self
    extractionTask = Task { [weak self] in
      do {
        let result = try await LocalVideoImportService.extract(
          descriptor: descriptor,
          selection: selection
        ) { progress in
          Task { @MainActor in
            guard progressModel.extractionGeneration == generation,
              progressModel.isExtracting
            else { return }
            progressModel.completedFrameCount = progress.completedFrameCount
            progressModel.totalFrameCount = progress.totalFrameCount
          }
        }
        guard !Task.isCancelled, self?.extractionGeneration == generation else { return }
        self?.isExtracting = false
        self?.extractionTask = nil
        self?.extractionGeneration = nil
        onComplete(result)
      } catch is CancellationError {
        guard self?.extractionGeneration == generation else { return }
        self?.isExtracting = false
        self?.extractionTask = nil
        self?.extractionGeneration = nil
      } catch {
        guard self?.extractionGeneration == generation else { return }
        self?.isExtracting = false
        self?.extractionTask = nil
        self?.extractionGeneration = nil
        self?.errorMessage = error.localizedDescription
      }
    }
  }

  func cancel() {
    extractionTask?.cancel()
    extractionTask = nil
    extractionGeneration = nil
    isExtracting = false
  }
}
