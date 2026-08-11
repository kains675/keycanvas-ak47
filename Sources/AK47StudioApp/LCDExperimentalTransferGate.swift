import AK47InspectorCore
import SwiftUI

/// Session-local safety state for the first LCD experiment.
///
/// This model neither owns nor invokes a transport. A concrete adapter and an
/// exact device match are independent prerequisites supplied by the caller.
/// It deliberately cannot record recovery evidence or authorize a larger
/// transfer; only the Core-owned durable qualification receipt may do that.
struct LCDExperimentalTransferGate: Equatable {
  static let expectedOutputEndpoint: UInt8 = 0x03
  static let expectedInputEndpoint: UInt8 = 0x84
  static let expectedAcknowledgementCount = 16
  var applyAcknowledgement = LCDExperimentalApplyAcknowledgement()

  var confirmationWasConsumed: Bool {
    applyAcknowledgement.wasConsumed
  }

  var hasRequiredAcknowledgement: Bool {
    applyAcknowledgement.isAcknowledged
  }

  func canRequestOneFrameUpload(
    adapterLinked: Bool,
    exactTargetReady: Bool,
    deviceOperationAllowed: Bool
  ) -> Bool {
    adapterLinked
      && exactTargetReady
      && deviceOperationAllowed
      && applyAcknowledgement.canApply
  }

  /// Consumes the one and only approval in this UI session.
  mutating func consumeOneFrameConfirmation(
    adapterLinked: Bool,
    exactTargetReady: Bool,
    deviceOperationAllowed: Bool
  ) -> Bool {
    guard
      canRequestOneFrameUpload(
        adapterLinked: adapterLinked,
        exactTargetReady: exactTargetReady,
        deviceOperationAllowed: deviceOperationAllowed
      )
    else {
      return false
    }
    return applyAcknowledgement.consume()
  }

}

/// Read-only UI projection of the Core-owned durable qualification receipt.
///
/// This type carries no transition methods and is never persisted by Studio.
/// Only a validated Core receipt may produce `.qualified`.
enum LCDExtendedQualificationViewState: Equatable {
  case receiptUnavailable
  case awaitingVisualAttestation
  case awaitingObservedAbsence
  case awaitingExactReappearance
  case awaitingWiredPowerRemovalAttestation
  case awaitingMaximumBoundaryTrial
  case maximumBoundaryTransferInProgress
  case awaitingMaximumBoundaryVisualAttestation(
    containerSHA256: String,
    frameCount: Int,
    pageCount: Int
  )
  case awaitingMaximumBoundaryObservedAbsence
  case awaitingMaximumBoundaryExactReappearance
  case awaitingMaximumBoundaryWiredPowerRemovalAttestation
  case maximumBoundaryVisualMismatchQuarantinePending
  case qualified(maximumFrameCount: Int)
  case canonicalTransferInProgress
  case canonicalVisualMismatchQuarantinePending
  case extendedTransferInProgress
  case interruptedTransferQuarantinePending
  case awaitingExtendedVisualAttestation(
    containerSHA256: String,
    frameCount: Int,
    pageCount: Int
  )
  case extendedVisualMismatchQuarantinePending
  case invalidatedRequiresFreshDiagnostic
  case blocked(String)

  var permitsExtendedUpload: Bool {
    guard case .qualified(let maximumFrameCount) = self else { return false }
    return maximumFrameCount == AK47LCDUploadAdapter.qualifiedMaximumFrameCount
  }

  var permitsMaximumBoundaryTrial: Bool {
    self == .awaitingMaximumBoundaryTrial
  }
}

enum LCDExtendedQualificationDetailsPresentation {
  static let initiallyExpanded = false

  static func isAvailable(for state: LCDExtendedQualificationViewState) -> Bool {
    if case .qualified = state { return false }
    return true
  }
}

/// Visible safety and one-use confirmation for the allowlisted first experiment.
/// The actual adapter independently revalidates target identity, payload shape,
/// fixture SHA-256, authorization fingerprint, and durable quarantine state.
struct LCDExperimentalTransferCard: View {
  @Environment(\.studioLanguage) private var language
  let adapterLinked: Bool
  let exactTargetReady: Bool
  let deviceOperationAllowed: Bool
  let qualificationAllowsFreshDiagnostic: Bool
  let uploadState: LCDDiagnosticUploadState
  let onBeginOneFrameUpload: () -> Void

  @State private var gate = LCDExperimentalTransferGate()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("1프레임 화면 시험", "One-frame display test", language: language))
            .font(.headline)
          Text(
            studioText(
              "먼저 모서리 4색 화면 한 장을 전송해 장치 적용을 확인합니다.",
              "First, send one four-corner color frame to check device Apply.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        StatusPill(
          label: availabilityLabel,
          symbol: adapterLinked ? "cable.connector" : "lock.shield",
          tint: adapterLinked ? StudioPalette.coral : .secondary
        )
      }

      HStack(alignment: .top, spacing: 18) {
        diagnosticPreview
          .frame(width: 320)

        VStack(alignment: .leading, spacing: 8) {
          fixtureLine(
            studioText(
              "정확히 1프레임 · \(AK47LCDDiagnosticFixture.expectedPageCount)페이지 · \(AK47LCDDiagnosticFixture.expectedContainerByteCount.formatted())바이트",
              "Exactly 1 frame · \(AK47LCDDiagnosticFixture.expectedPageCount) pages · \(AK47LCDDiagnosticFixture.expectedContainerByteCount.formatted()) bytes",
              language: language
            )
          )
          fixtureLine(
            studioText(
              "macOS 검증: FF13 IF3 + FF68 IF2 · 동일 physical USB parent",
              "macOS verifies FF13 IF3 + FF68 IF2 · same physical USB parent",
              language: language
            )
          )
          fixtureLine(
            studioText(
              "Windows 관찰 endpoint OUT 0x03 → IN 0x84 · 예상 input \(LCDExperimentalTransferGate.expectedAcknowledgementCount)회",
              "Windows-observed endpoints OUT 0x03 → IN 0x84 · \(LCDExperimentalTransferGate.expectedAcknowledgementCount) expected inputs",
              language: language
            )
          )
          fixtureLine("SHA-256 \(abbreviatedFixtureHash)")
          Text(
            studioText(
              "검정 바탕 / 좌상 빨강 / 우상 초록 / 좌하 파랑 / 우하 흰색",
              "Black / TL red / TR green / BL blue / BR white",
              language: language
            )
          )
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Toggle(isOn: $gate.applyAcknowledgement.isAcknowledged) {
          Text(
            studioText(
              LCDExperimentalApplyAcknowledgement.koreanText,
              LCDExperimentalApplyAcknowledgement.englishText,
              language: language
            )
          )
        }
      }
      .toggleStyle(.checkbox)
      .font(.caption)

      HStack(spacing: 12) {
        Button(role: .destructive) {
          guard
            gate.consumeOneFrameConfirmation(
              adapterLinked: adapterLinked,
              exactTargetReady: exactTargetReady,
              deviceOperationAllowed: deviceOperationAllowed
            )
          else { return }
          onBeginOneFrameUpload()
        } label: {
          Label(
            studioText("1프레임 시험 시작", "Start one-frame test", language: language),
            systemImage: "display.and.arrow.down"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.coral)
        .disabled(!canRequestUpload)

        Text(lockReason)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      uploadStatus

      Label(
        studioText(
          "전송 후 실제 LCD의 네 모서리를 확인하고 아래 복구 단계를 계속하세요.",
          "After transfer, check the four LCD corners and continue with the recovery steps below.",
          language: language
        ),
        systemImage: "lock"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .studioPanel()
  }

  @ViewBuilder
  private var uploadStatus: some View {
    switch uploadState {
    case .idle:
      EmptyView()
    case .uploading(let completedPages, let totalPages):
      VStack(alignment: .leading, spacing: 6) {
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
    case .succeeded(let acknowledgedPages, _):
      Label(
        studioText(
          "이미지 전송 완료(ACK \(acknowledgedPages)/16). LCD의 네 모서리 색과 방향을 확인하세요.",
          "Image transfer complete (ACK \(acknowledgedPages)/16). Check all four LCD corner colors and orientation.",
          language: language
        ),
        systemImage: "checkmark.seal"
      )
      .font(.caption)
      .foregroundStyle(StudioPalette.mint)
    case .failed(let acknowledgedPages, let message):
      VStack(alignment: .leading, spacing: 5) {
        Label(
          studioText(
            "전송 중단 · 예상 input \(acknowledgedPages) / 16",
            "Transfer stopped · expected inputs \(acknowledgedPages) / 16",
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
            "다시 시도하지 마세요. selector를 USB 위치에 둔 채 케이블을 분리하고 LCD·LED가 완전히 꺼진 뒤 실제 열거 0개를 확인하는 복구 절차를 진행하세요. 2.4G 또는 Bluetooth 전환은 복구가 아닙니다.",
            "Do not retry. Keep the selector in USB mode, disconnect the cable, verify that the LCD and LEDs are fully off, and refresh until real enumeration shows zero matching collections. Switching to 2.4G or Bluetooth is not recovery.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var canRequestUpload: Bool {
    qualificationAllowsFreshDiagnostic
      && gate.canRequestOneFrameUpload(
        adapterLinked: adapterLinked,
        exactTargetReady: exactTargetReady,
        deviceOperationAllowed: deviceOperationAllowed
      )
  }

  private var availabilityLabel: String {
    if case .uploading(let completedPages, let totalPages) = uploadState {
      let percent = LCDUploadProgressPresentation.percentage(
        completedAcknowledgements: completedPages,
        totalAcknowledgements: totalPages
      )
      return studioText(
        "\(percent)% 전송 중",
        "Transferring \(percent)%",
        language: language
      )
    }
    if !adapterLinked {
      return studioText("어댑터 연결 전 잠김", "Locked until adapter is linked", language: language)
    }
    if !exactTargetReady {
      return studioText("정확한 장치 필요", "Exact target required", language: language)
    }
    return studioText("실험 경로", "Experimental path", language: language)
  }

  private var lockReason: String {
    if !adapterLinked {
      return studioText(
        "구체 전송 어댑터가 아직 UI에 연결되지 않았습니다.",
        "The concrete transfer adapter is not linked to the UI yet.",
        language: language
      )
    }
    if !exactTargetReady {
      return studioText(
        "유선 AK47 revision 0x0115의 정확한 HID 구성이 필요합니다.",
        "The exact wired AK47 revision 0x0115 HID topology is required.",
        language: language
      )
    }
    if !deviceOperationAllowed {
      return studioText(
        "다른 장치 작업이 진행 중이거나 장치가 격리되었습니다.",
        "Another device operation is active or the device is quarantined.",
        language: language
      )
    }
    if !qualificationAllowsFreshDiagnostic {
      return studioText(
        "첫 시험이 이미 진행됐습니다. 아래 장치 적용 준비 카드에서 다음 단계를 확인하세요.",
        "The first test has already started. Check the Device Apply readiness card below for the next step.",
        language: language
      )
    }
    if gate.confirmationWasConsumed {
      return studioText(
        "이 세션의 단발 승인은 이미 사용했습니다.",
        "The one-time approval for this session was already consumed.",
        language: language
      )
    }
    if !gate.hasRequiredAcknowledgement {
      return studioText(
        "실험 기능 위험 확인이 필요합니다.",
        "The experimental-feature risk acknowledgement is required.",
        language: language
      )
    }
    return studioText(
      "이 확인은 한 번의 적용에만 유효합니다.",
      "This acknowledgement is valid for one Apply only.",
      language: language
    )
  }

  private var diagnosticPreview: some View {
    GeometryReader { geometry in
      let cornerSize = Double(AK47LCDDiagnosticFixture.cornerSize)
      let cornerWidth = geometry.size.width * (cornerSize / 240.0)
      let cornerHeight = geometry.size.height * (cornerSize / 135.0)
      ZStack {
        Color.black
        Color.red
          .frame(width: cornerWidth, height: cornerHeight)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Color.green
          .frame(width: cornerWidth, height: cornerHeight)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        Color.blue
          .frame(width: cornerWidth, height: cornerHeight)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        Color.white
          .frame(width: cornerWidth, height: cornerHeight)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
    }
    .aspectRatio(240.0 / 135.0, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.16))
    }
  }

  private func fixtureLine(_ text: String) -> some View {
    Label(text, systemImage: "checkmark.circle.fill")
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
  }

  private var abbreviatedFixtureHash: String {
    let hash = AK47LCDDiagnosticFixture.expectedContainerSHA256
    return "\(hash.prefix(8))…\(hash.suffix(6))"
  }
}

struct LCDExtendedQualificationCard: View {
  @Environment(\.studioLanguage) private var language
  let state: LCDExtendedQualificationViewState
  let canRefreshHardware: Bool
  let canRecordVisualAttestation: Bool
  let canReportCanonicalVisualMismatch: Bool
  let canRecordWiredPowerRemovalAttestation: Bool
  let canReviewExtendedVisualResult: Bool
  let canReportExtendedVisualMismatch: Bool
  let canReconcileInterruptedTransfer: Bool
  let errorMessage: String?
  let onRefreshHardware: () -> Void
  let onRecordVisualAttestation: () -> Void
  let onReportCanonicalVisualMismatch: () -> Void
  let onRecordWiredPowerRemovalAttestation: () -> Void
  let onReviewExtendedVisualResult: () -> Void
  let onReportExtendedVisualMismatch: () -> Void
  let onReconcileInterruptedTransfer: () -> Void

  @State private var showsVisualAttestation = false
  @State private var showsCanonicalMismatchRetry = false
  @State private var showsWiredPowerRemovalAttestation = false
  @State private var showsExtendedVisualMismatch = false
  @State private var showsInterruptedTransferReconciliation = false
  @State private var showsDetailedSteps =
    LCDExtendedQualificationDetailsPresentation.initiallyExpanded

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            studioText(
              "장치 적용 준비",
              "Device Apply readiness",
              language: language
            )
          )
          .font(.headline)
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        StatusPill(
          label: state.permitsExtendedUpload
            ? studioText("적용 준비 완료", "Ready to Apply", language: language)
            : state.permitsMaximumBoundaryTrial
              ? studioText("140프레임 시험 필요", "140-frame test required", language: language)
              : studioText("잠김", "Locked", language: language),
          symbol: state.permitsExtendedUpload
            ? "checkmark.shield.fill"
            : state.permitsMaximumBoundaryTrial
              ? "gauge.with.dots.needle.100percent"
              : "lock.shield",
          tint: state.permitsExtendedUpload
            ? StudioPalette.mint
            : state.permitsMaximumBoundaryTrial ? StudioPalette.coral : .secondary
        )
      }

      if LCDExtendedQualificationDetailsPresentation.isAvailable(for: state) {
        DisclosureGroup(isExpanded: $showsDetailedSteps) {
          recoverySequence
            .padding(.top, 8)
        } label: {
          Label(
            studioText("자세한 단계", "Detailed steps", language: language),
            systemImage: "list.number"
          )
          .font(.caption.weight(.semibold))
        }
      }

      if let action = action {
        HStack(spacing: 10) {
          Button(action.title) {
            action.perform()
          }
          .buttonStyle(.borderedProminent)
          .tint(action.isDestructive ? StudioPalette.coral : StudioPalette.blue)
          .disabled(!action.isEnabled)

          Text(action.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if awaitsSubmittedVisualReview {
        HStack(spacing: 10) {
          if canReviewExtendedVisualResult {
            Button(
              studioText(
                "불변 예상 애니메이션과 비교…",
                "Compare with immutable expected animation…",
                language: language
              )
            ) {
              onReviewExtendedVisualResult()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioPalette.blue)
          }

          Button(
            studioText(
              "틀림 또는 확인 불가…",
              "Wrong or unverifiable…",
              language: language
            ),
            role: .destructive
          ) {
            showsExtendedVisualMismatch = true
          }
          .disabled(!canReportExtendedVisualMismatch)

          if !canReviewExtendedVisualResult {
            Text(
              studioText(
                "재시작으로 exact 예상 preview가 사라져 ‘정확함’은 기록할 수 없습니다.",
                "The exact expected preview was lost after relaunch, so a correct result cannot be recorded.",
                language: language
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      }

    }
    .studioPanel()
    .confirmationDialog(
      studioText(
        "고정 진단 화면의 네 모서리를 확인했나요?",
        "Did you verify all four corners of the fixed diagnostic?",
        language: language
      ),
      isPresented: $showsVisualAttestation,
      titleVisibility: .visible
    ) {
      Button(
        studioText("색·위치·방향 확인 기록", "Record color, position, and orientation", language: language),
        role: nil
      ) {
        onRecordVisualAttestation()
      }
      .disabled(!canRecordVisualAttestation)
      Button(
        studioText(
          "틀림 또는 확인 불가 — 격리",
          "Wrong or unverifiable — quarantine",
          language: language
        ),
        role: .destructive
      ) {
        onReportCanonicalVisualMismatch()
      }
      .disabled(!canReportCanonicalVisualMismatch)
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "검정 바탕에서 좌상 빨강, 우상 초록, 좌하 파랑, 우하 흰색이 정확히 보인 경우에만 기록하세요. host의 16개 input sequence만으로는 이 화면 결과를 증명할 수 없습니다.",
          "Record this only if a black background shows red at top-left, green at top-right, blue at bottom-left, and white at bottom-right. The 16 host input sequences alone do not prove this visible result.",
          language: language
        )
      )
    }
    .confirmationDialog(
      studioText(
        "중단된 LCD lease를 격리 상태로 전환할까요?",
        "Move the interrupted LCD lease into quarantine?",
        language: language
      ),
      isPresented: $showsInterruptedTransferReconciliation,
      titleVisibility: .visible
    ) {
      Button(
        studioText(
          "중단 상태 reconcile 및 격리",
          "Reconcile interruption and quarantine",
          language: language
        ),
        role: .destructive
      ) {
        onReconcileInterruptedTransfer()
      }
      .disabled(!canReconcileInterruptedTransfer)
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "다른 KeyCanvas process에서 전송이 실제 진행 중이면 취소하세요. 실행 중인 process가 없고 이전 전송이 앱 종료·중단 뒤 남은 경우에만 선택하세요. Core는 이전 lease를 성공으로 복원하지 않고 exact target을 durable quarantine한 뒤 자격을 폐기합니다.",
          "Cancel if a transfer is actually active in another KeyCanvas process. Continue only when no process is active and the prior transfer lease survived an app exit or interruption. Core never restores the old lease as success; it durably quarantines the exact target and revokes qualification.",
          language: language
        )
      )
    }
    .confirmationDialog(
      studioText(
        "LCD 결과가 틀렸거나 확인할 수 없나요?",
        "Is the LCD result wrong or unverifiable?",
        language: language
      ),
      isPresented: $showsExtendedVisualMismatch,
      titleVisibility: .visible
    ) {
      Button(
        studioText(
          "자격 폐기 및 장치 격리",
          "Revoke qualification and quarantine device",
          language: language
        ),
        role: .destructive
      ) {
        onReportExtendedVisualMismatch()
      }
      .disabled(!canReportExtendedVisualMismatch)
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "실제 LCD가 불변 예상 애니메이션과 다르거나 비교할 수 없다면 정확함을 추정하지 마세요. 이 선택은 영속 자격을 폐기하고 USB-mode cable-removal 복구 전까지 장치를 격리합니다.",
          "Do not infer success if the actual LCD differs from the immutable expected animation or cannot be compared. This revokes the durable qualification and quarantines the device until USB-mode cable-removal recovery.",
          language: language
        )
      )
    }
    .confirmationDialog(
      studioText(
        "고정 진단 mismatch 격리를 다시 완료할까요?",
        "Retry durable quarantine for the canonical mismatch?",
        language: language
      ),
      isPresented: $showsCanonicalMismatchRetry,
      titleVisibility: .visible
    ) {
      Button(
        studioText(
          "영속 격리 완료 재시도",
          "Retry durable quarantine completion",
          language: language
        ),
        role: .destructive
      ) {
        onReportCanonicalVisualMismatch()
      }
      .disabled(!canReportCanonicalVisualMismatch)
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "화면 mismatch receipt는 이미 저장됐습니다. 이 동작은 화면 성공을 다시 판단하지 않고, 중단된 durable quarantine 설정만 동일 exact target에 재시도합니다.",
          "The visual-mismatch receipt is already saved. This does not reconsider visual success; it only retries interrupted durable quarantine setup for the same exact target.",
          language: language
        )
      )
    }
    .confirmationDialog(
      studioText(
        "USB 전원 제거 복구를 최종 확인할까요?",
        "Confirm wired-power-removal recovery?",
        language: language
      ),
      isPresented: $showsWiredPowerRemovalAttestation,
      titleVisibility: .visible
    ) {
      Button(
        studioText("복구 사실 기록", "Record recovery attestation", language: language),
        role: .destructive
      ) {
        onRecordWiredPowerRemovalAttestation()
      }
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "selector를 USB 위치에 둔 채 cable을 분리해 LCD·LED와 장치가 완전히 꺼졌고, 분리 상태의 실제 열거 0개 뒤 같은 원래 Mac USB 포트에서 동일 장치의 exact 4 collection 재등장을 확인한 경우에만 계속하세요. 2.4G/Bluetooth 전환은 복구가 아닙니다.",
          "Continue only if the selector stayed in USB mode; cable removal fully powered down the LCD, LEDs, and device; real enumeration then observed zero matching collections; and the same device's exact four collections reappeared at the original Mac USB port. Switching to 2.4G/Bluetooth is not recovery.",
          language: language
        )
      )
    }
  }

  private var awaitsSubmittedVisualReview: Bool {
    switch state {
    case .awaitingMaximumBoundaryVisualAttestation, .awaitingExtendedVisualAttestation:
      true
    default:
      false
    }
  }

  private var summary: String {
    switch state {
    case .receiptUnavailable:
      studioText(
        "장치 적용 준비가 필요합니다. 먼저 위의 1프레임 화면 시험을 진행하세요.",
        "Device Apply is not ready. Start with the one-frame display test above.",
        language: language
      )
    case .awaitingVisualAttestation:
      studioText(
        "1프레임 전송이 끝났습니다. ‘네 모서리 확인’을 눌러 실제 LCD를 확인하세요.",
        "The one-frame transfer is complete. Choose Confirm four corners and check the actual LCD.",
        language: language
      )
    case .awaitingObservedAbsence:
      studioText(
        "LCD 확인이 끝났습니다. 키보드를 USB 모드에 둔 채 케이블을 분리하고 ‘분리 상태 새로고침’을 누르세요.",
        "LCD review is complete. Keep the keyboard in USB mode, disconnect the cable, then choose Refresh while disconnected.",
        language: language
      )
    case .awaitingExactReappearance:
      studioText(
        "장치가 사라진 것을 확인했습니다. 같은 Mac USB 포트에 다시 연결한 뒤 ‘재연결 상태 새로고침’을 누르세요.",
        "Device absence is confirmed. Reconnect it to the same Mac USB port, then choose Refresh after reconnection.",
        language: language
      )
    case .awaitingWiredPowerRemovalAttestation:
      studioText(
        "재연결까지 확인했습니다. 케이블 분리로 전원이 완전히 꺼졌다면 ‘USB 전원 제거 확인’을 누르세요.",
        "Reconnection is confirmed. If cable removal fully powered off the device, choose Confirm wired-power removal.",
        language: language
      )
    case .awaitingMaximumBoundaryTrial:
      studioText(
        "첫 시험과 복구가 끝났습니다. 편집기를 정확히 140프레임으로 만든 뒤 경계 시험을 시작하세요.",
        "The first test and recovery are complete. Make the edit exactly 140 frames, then start the boundary test.",
        language: language
      )
    case .maximumBoundaryTransferInProgress:
      studioText(
        "140프레임 전송이 진행 중이거나 중단된 상태입니다. 다른 장치 작업을 시작하지 마세요.",
        "The 140-frame transfer is running or was interrupted. Do not start another device operation.",
        language: language
      )
    case .awaitingMaximumBoundaryVisualAttestation:
      studioText(
        "140프레임 전송이 끝났습니다. ‘불변 예상 애니메이션과 비교’를 눌러 실제 LCD를 확인하세요.",
        "The 140-frame transfer is complete. Choose Compare with immutable expected animation and check the actual LCD.",
        language: language
      )
    case .awaitingMaximumBoundaryObservedAbsence:
      studioText(
        "LCD 일치 확인이 끝났습니다. USB 모드에서 케이블을 분리하고 ‘분리 상태 새로고침’을 누르세요.",
        "LCD match review is complete. Disconnect the cable in USB mode, then choose Refresh while disconnected.",
        language: language
      )
    case .awaitingMaximumBoundaryExactReappearance:
      studioText(
        "장치가 사라진 것을 확인했습니다. 같은 Mac USB 포트에 다시 연결한 뒤 ‘재연결 상태 새로고침’을 누르세요.",
        "Device absence is confirmed. Reconnect it to the same Mac USB port, then choose Refresh after reconnection.",
        language: language
      )
    case .awaitingMaximumBoundaryWiredPowerRemovalAttestation:
      studioText(
        "재연결까지 확인했습니다. 케이블 분리로 전원이 완전히 꺼졌다면 ‘USB 전원 제거 확인’을 누르세요.",
        "Reconnection is confirmed. If cable removal fully powered off the device, choose Confirm wired-power removal.",
        language: language
      )
    case .maximumBoundaryVisualMismatchQuarantinePending:
      studioText(
        "140프레임 화면이 다르거나 확인할 수 없어 장치 격리를 완료해야 합니다. 아래 재시도 버튼만 사용하세요.",
        "The 140-frame display was wrong or unverifiable, so device quarantine must finish. Use only the retry button below.",
        language: language
      )
    case .qualified(let maximumFrameCount):
      studioText(
        "장치 적용 준비가 끝났습니다. 편집기에서 최대 \(maximumFrameCount)프레임 이미지를 선택해 적용하세요.",
        "Device Apply is ready. Choose an image of up to \(maximumFrameCount) frames in the editor and apply it.",
        language: language
      )
    case .canonicalTransferInProgress:
      studioText(
        "1프레임 전송이 진행 중이거나 중단된 상태입니다. 다른 전송이 실행 중이 아니라면 아래에서 중단 상태를 정리하세요.",
        "The one-frame transfer is running or was interrupted. If no other transfer is active, reconcile the interrupted state below.",
        language: language
      )
    case .canonicalVisualMismatchQuarantinePending:
      studioText(
        "1프레임 화면이 다르거나 확인할 수 없어 장치 격리를 완료해야 합니다. 일반 전송을 재시도하지 마세요.",
        "The one-frame display was wrong or unverifiable, so device quarantine must finish. Do not retry a normal transfer.",
        language: language
      )
    case .extendedTransferInProgress:
      studioText(
        "이미지 전송이 진행 중이거나 중단된 상태입니다. 다른 전송이 실행 중이 아니라면 아래에서 격리한 뒤 복구 절차를 진행하세요.",
        "An image transfer is running or was interrupted. If no other transfer is active, quarantine it below and complete recovery.",
        language: language
      )
    case .interruptedTransferQuarantinePending:
      studioText(
        "중단된 전송이 있습니다. 아래 버튼으로 장치 격리를 완료한 뒤 복구 절차를 진행하세요.",
        "A transfer was interrupted. Finish device quarantine below, then complete recovery.",
        language: language
      )
    case .awaitingExtendedVisualAttestation:
      studioText(
        "이미지 전송이 끝났습니다. ‘불변 예상 애니메이션과 비교’를 눌러 실제 LCD를 확인하세요.",
        "The image transfer is complete. Choose Compare with immutable expected animation and check the actual LCD.",
        language: language
      )
    case .extendedVisualMismatchQuarantinePending:
      studioText(
        "화면이 다르거나 확인할 수 없어 장치 격리를 완료해야 합니다. 일반 전송을 재시도하지 마세요.",
        "The display was wrong or unverifiable, so device quarantine must finish. Do not retry a normal transfer.",
        language: language
      )
    case .invalidatedRequiresFreshDiagnostic:
      studioText(
        "이미지 전송에 실패해 장치 적용이 잠겼습니다. USB 모드 케이블 복구를 마친 뒤 1프레임 시험부터 다시 시작하세요.",
        "Image transfer failed and Device Apply is locked. Complete USB-mode cable recovery, then restart with the one-frame test.",
        language: language
      )
    case .blocked(let message):
      message
    }
  }

  @ViewBuilder
  private var recoverySequence: some View {
    VStack(alignment: .leading, spacing: 6) {
      qualificationStep(
        number: 1,
        text: studioText(
          "1프레임 화면 전송",
          "One-frame display transfer", language: language),
        completed: stepCompletion >= 1
      )
      qualificationStep(
        number: 2,
        text: studioText(
          "LCD 네 모서리 확인", "Check the four LCD corners",
          language: language),
        completed: stepCompletion >= 2
      )
      qualificationStep(
        number: 3,
        text: studioText(
          "USB 모드에서 케이블 분리 후 장치 사라짐 확인",
          "Disconnect in USB mode and confirm device absence", language: language),
        completed: stepCompletion >= 3
      )
      qualificationStep(
        number: 4,
        text: studioText(
          "같은 USB 포트에 다시 연결",
          "Reconnect to the same USB port", language: language),
        completed: stepCompletion >= 4
      )
      qualificationStep(
        number: 5,
        text: studioText(
          "완전 전원 차단 확인", "Confirm complete power loss", language: language),
        completed: stepCompletion >= 5
      )
      Divider()
        .padding(.vertical, 2)
      qualificationStep(
        number: 6,
        text: studioText(
          "140프레임 경계 화면 전송",
          "140-frame boundary display transfer",
          language: language
        ),
        completed: stepCompletion >= 6
      )
      qualificationStep(
        number: 7,
        text: studioText(
          "전송한 화면과 실제 LCD 비교",
          "Compare the transferred image with the actual LCD",
          language: language
        ),
        completed: stepCompletion >= 7
      )
      qualificationStep(
        number: 8,
        text: studioText(
          "USB 모드에서 케이블 분리 후 장치 사라짐 확인",
          "Disconnect in USB mode and confirm device absence",
          language: language
        ),
        completed: stepCompletion >= 8
      )
      qualificationStep(
        number: 9,
        text: studioText(
          "같은 USB 포트에 다시 연결",
          "Reconnect to the same USB port",
          language: language
        ),
        completed: stepCompletion >= 9
      )
      qualificationStep(
        number: 10,
        text: studioText(
          "완전 전원 차단 확인",
          "Confirm complete power loss",
          language: language
        ),
        completed: stepCompletion >= 10
      )
    }
  }

  private func qualificationStep(number: Int, text: String, completed: Bool) -> some View {
    Label {
      Text("\(number). \(text)")
    } icon: {
      Image(systemName: completed ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(completed ? StudioPalette.mint : .secondary)
    }
    .font(.caption)
  }

  private var stepCompletion: Int {
    switch state {
    case .receiptUnavailable, .canonicalTransferInProgress,
      .canonicalVisualMismatchQuarantinePending,
      .interruptedTransferQuarantinePending,
      .invalidatedRequiresFreshDiagnostic, .blocked:
      0
    case .awaitingVisualAttestation:
      1
    case .awaitingObservedAbsence:
      2
    case .awaitingExactReappearance:
      3
    case .awaitingWiredPowerRemovalAttestation:
      4
    case .awaitingMaximumBoundaryTrial, .maximumBoundaryTransferInProgress:
      5
    case .awaitingMaximumBoundaryVisualAttestation:
      6
    case .maximumBoundaryVisualMismatchQuarantinePending:
      6
    case .awaitingMaximumBoundaryObservedAbsence:
      7
    case .awaitingMaximumBoundaryExactReappearance:
      8
    case .awaitingMaximumBoundaryWiredPowerRemovalAttestation:
      9
    case .qualified, .extendedTransferInProgress, .awaitingExtendedVisualAttestation,
      .extendedVisualMismatchQuarantinePending:
      10
    }
  }

  private struct Action {
    let title: String
    let detail: String
    let isEnabled: Bool
    let isDestructive: Bool
    let perform: () -> Void
  }

  private var action: Action? {
    switch state {
    case .receiptUnavailable, .awaitingMaximumBoundaryTrial, .qualified,
      .awaitingMaximumBoundaryVisualAttestation, .awaitingExtendedVisualAttestation,
      .invalidatedRequiresFreshDiagnostic, .blocked:
      nil
    case .canonicalTransferInProgress, .maximumBoundaryTransferInProgress,
      .extendedTransferInProgress,
      .interruptedTransferQuarantinePending:
      Action(
        title: studioText(
          "중단된 전송 정리…",
          "Resolve interrupted transfer…",
          language: language
        ),
        detail: studioText(
          "다른 KeyCanvas 전송이 실행 중이지 않을 때만 진행",
          "Continue only when no other KeyCanvas transfer is active",
          language: language
        ),
        isEnabled: canReconcileInterruptedTransfer,
        isDestructive: true,
        perform: { showsInterruptedTransferReconciliation = true }
      )
    case .canonicalVisualMismatchQuarantinePending:
      Action(
        title: studioText(
          "장치 격리 완료 재시도…",
          "Retry device quarantine…",
          language: language
        ),
        detail: studioText(
          "저장된 화면 오류에 대한 격리만 다시 시도",
          "Retries quarantine only for the saved display error",
          language: language
        ),
        isEnabled: canReportCanonicalVisualMismatch,
        isDestructive: true,
        perform: { showsCanonicalMismatchRetry = true }
      )
    case .maximumBoundaryVisualMismatchQuarantinePending:
      Action(
        title: studioText(
          "장치 격리 완료 재시도…",
          "Retry device quarantine…",
          language: language
        ),
        detail: studioText(
          "저장된 화면 오류에 대한 격리만 다시 시도",
          "Retries quarantine only for the saved display error",
          language: language
        ),
        isEnabled: canReportExtendedVisualMismatch,
        isDestructive: true,
        perform: { showsExtendedVisualMismatch = true }
      )
    case .extendedVisualMismatchQuarantinePending:
      Action(
        title: studioText(
          "장치 격리 완료 재시도…",
          "Retry device quarantine…",
          language: language
        ),
        detail: studioText(
          "저장된 화면 오류에 대한 격리만 다시 시도",
          "Retries quarantine only for the saved display error",
          language: language
        ),
        isEnabled: canReportExtendedVisualMismatch,
        isDestructive: true,
        perform: { showsExtendedVisualMismatch = true }
      )
    case .awaitingVisualAttestation:
      Action(
        title: studioText("네 모서리 확인…", "Confirm four corners…", language: language),
        detail: studioText(
          "실제 LCD를 직접 확인", "Check the actual LCD directly",
          language: language),
        isEnabled: canRecordVisualAttestation || canReportCanonicalVisualMismatch,
        isDestructive: true,
        perform: { showsVisualAttestation = true }
      )
    case .awaitingObservedAbsence, .awaitingMaximumBoundaryObservedAbsence:
      Action(
        title: studioText("분리 상태 새로고침", "Refresh while disconnected", language: language),
        detail: studioText(
          "케이블이 분리된 상태에서 장치 검색",
          "Search for the device while the cable is disconnected", language: language),
        isEnabled: canRefreshHardware,
        isDestructive: false,
        perform: onRefreshHardware
      )
    case .awaitingExactReappearance, .awaitingMaximumBoundaryExactReappearance:
      Action(
        title: studioText("재연결 상태 새로고침", "Refresh after reconnection", language: language),
        detail: studioText(
          "같은 USB 포트에 연결한 뒤 장치 검색",
          "Reconnect to the same USB port, then search for the device", language: language),
        isEnabled: canRefreshHardware,
        isDestructive: false,
        perform: onRefreshHardware
      )
    case .awaitingWiredPowerRemovalAttestation,
      .awaitingMaximumBoundaryWiredPowerRemovalAttestation:
      Action(
        title: studioText("USB 전원 제거 확인…", "Confirm wired-power removal…", language: language),
        detail: studioText(
          "부재와 재등장 관찰 뒤에만 기록 가능", "Available only after observed absence and reappearance",
          language: language),
        isEnabled: canRecordWiredPowerRemovalAttestation,
        isDestructive: true,
        perform: { showsWiredPowerRemovalAttestation = true }
      )
    }
  }
}
