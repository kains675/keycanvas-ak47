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
  var acknowledgesCurrentImageOverwrite = false
  var acknowledgesNoReadbackOrRollback = false
  var confirmsOtherUtilitiesAndVMsAreClosed = false
  var confirmsColdRecoveryIsPrepared = false

  private(set) var confirmationWasConsumed = false

  var hasAllRiskAcknowledgements: Bool {
    acknowledgesCurrentImageOverwrite
      && acknowledgesNoReadbackOrRollback
      && confirmsOtherUtilitiesAndVMsAreClosed
      && confirmsColdRecoveryIsPrepared
  }

  func canRequestOneFrameUpload(
    adapterLinked: Bool,
    exactTargetReady: Bool,
    deviceOperationAllowed: Bool
  ) -> Bool {
    adapterLinked
      && exactTargetReady
      && deviceOperationAllowed
      && hasAllRiskAcknowledgements
      && !confirmationWasConsumed
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
    confirmationWasConsumed = true
    return true
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
    return maximumFrameCount == 40
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
  @State private var showsFinalConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("LCD 실기 전송", "Live LCD experiment", language: language))
            .font(.headline)
          Text(
            studioText(
              "고정된 모서리 4색 진단 화면 한 장만 사용하는 최초 시험입니다.",
              "The first experiment uses only one fixed four-corner diagnostic frame.",
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
        Toggle(isOn: $gate.acknowledgesCurrentImageOverwrite) {
          Text(
            studioText(
              "현재 LCD 사용자 이미지를 덮어쓴다는 것을 이해했습니다.",
              "I understand this overwrites the current user LCD image.",
              language: language
            )
          )
        }
        Toggle(isOn: $gate.acknowledgesNoReadbackOrRollback) {
          Text(
            studioText(
              "현재 이미지를 읽어 오거나 자동으로 되돌리는 기능이 없음을 이해했습니다.",
              "I understand there is no current-image readback or automatic rollback.",
              language: language
            )
          )
        }
        Toggle(isOn: $gate.confirmsOtherUtilitiesAndVMsAreClosed) {
          Text(
            studioText(
              "Windows 제조사 프로그램, 다른 키보드 도구와 USB를 쓰는 가상 머신을 모두 닫았습니다.",
              "I closed the Windows vendor app, other keyboard utilities, and USB-using VMs.",
              language: language
            )
          )
        }
        Toggle(isOn: $gate.confirmsColdRecoveryIsPrepared) {
          Text(
            studioText(
              "실패 시 selector를 USB 위치에 둔 채 케이블을 분리하고 LCD·LED가 완전히 꺼진 상태에서 실제 열거 0개를 확인하겠습니다.",
              "If it fails, I will keep the selector in USB mode, disconnect the cable, verify the LCD and LEDs are fully off, and refresh until real enumeration shows zero matching collections.",
              language: language
            )
          )
        }
      }
      .toggleStyle(.checkbox)
      .font(.caption)

      HStack(spacing: 12) {
        Button(role: .destructive) {
          showsFinalConfirmation = true
        } label: {
          Label(
            studioText("1프레임 실기 승인…", "Approve one-frame experiment…", language: language),
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
          "1…40프레임 editor Apply는 Core의 fresh 영속 성공 receipt와 순서가 검증된 USB 전원 제거 복구 receipt가 모두 기록되기 전까지 제공되지 않습니다.",
          "The 1...40-frame editor Apply path is not offered until Core holds both a fresh durable success receipt and an ordered, verified wired-power-removal recovery receipt.",
          language: language
        ),
        systemImage: "lock"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .studioPanel()
    .confirmationDialog(
      studioText(
        "현재 LCD 이미지를 1프레임 진단 화면으로 덮어쓸까요?",
        "Overwrite the current LCD image with the one-frame diagnostic?",
        language: language
      ),
      isPresented: $showsFinalConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        studioText("한 번만 전송", "Upload once", language: language),
        role: .destructive
      ) {
        guard
          gate.consumeOneFrameConfirmation(
            adapterLinked: adapterLinked,
            exactTargetReady: exactTargetReady,
            deviceOperationAllowed: deviceOperationAllowed
          )
        else { return }
        onBeginOneFrameUpload()
      }
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
    } message: {
      Text(
        studioText(
          "재시도 없이 Output 16개를 제출하고 각 완료 뒤 예상한 input report를 검증합니다. input에는 page index가 없어 flash 수락을 증명하지 않습니다. 실패하면 다른 장치 작업을 중단하고 selector를 USB 위치에 둔 채 케이블을 분리해 LCD·LED가 완전히 꺼지고 실제 열거가 0이 되는지 확인해야 합니다.",
          "This submits 16 Outputs without retry and validates the expected input report after each completion. The input has no page index and does not prove flash acceptance. On failure, stop other device operations, keep the selector in USB mode, disconnect the cable, and verify that the LCD and LEDs turn fully off and real enumeration reaches zero.",
          language: language
        )
      )
    }
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
          studioText(
            "예상 input 확인 \(completedPages) / \(totalPages) · 전송 중에는 앱을 종료하거나 Mac을 잠자기 상태로 두지 마세요.",
            "Expected inputs \(completedPages) / \(totalPages) · do not quit the app or put the Mac to sleep during transfer.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    case .succeeded(let acknowledgedPages, _):
      Label(
        studioText(
          "호스트 sequence 완료 · 예상 input \(acknowledgedPages) / 16. LCD의 네 모서리 색과 방향을 직접 확인해 주세요.",
          "Host sequence completed · expected inputs \(acknowledgedPages) / 16. Visually verify all four LCD corner colors and orientation.",
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
      return studioText(
        "Input \(completedPages)/\(totalPages)",
        "Input \(completedPages)/\(totalPages)",
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
        "영속 qualification receipt가 이미 진행 중이거나 완료되어 새 진단 전송을 차단했습니다.",
        "A durable qualification receipt is already in progress or complete, so a new diagnostic transfer is blocked.",
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
    if !gate.hasAllRiskAcknowledgements {
      return studioText(
        "위 네 가지 안전 확인이 모두 필요합니다.",
        "All four safety acknowledgements are required.",
        language: language
      )
    }
    return studioText(
      "마지막 확인 후 한 번만 실행합니다.", "Runs once after final confirmation.", language: language)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(studioText("40프레임 자격", "40-frame qualification", language: language))
            .font(.headline)
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        StatusPill(
          label: state.permitsExtendedUpload
            ? studioText("Core receipt 검증됨", "Core receipt verified", language: language)
            : studioText("잠김", "Locked", language: language),
          symbol: state.permitsExtendedUpload ? "checkmark.shield.fill" : "lock.shield",
          tint: state.permitsExtendedUpload ? StudioPalette.mint : .secondary
        )
      }

      recoverySequence

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

      if case .awaitingExtendedVisualAttestation = state {
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

      Label(
        studioText(
          "이 카드는 Core receipt를 표시할 뿐 자격을 직접 만들지 않습니다. 과거 실기 결과의 수동 import·backfill·일반 bypass는 없습니다.",
          "This card only projects the Core receipt. It cannot create qualification, and there is no manual import, backfill, or generic bypass for an earlier trial.",
          language: language
        ),
        systemImage: "checkmark.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
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

  private var summary: String {
    switch state {
    case .receiptUnavailable:
      studioText(
        "production receipt가 없습니다. 새 build에서 고정 1프레임 실기를 다시 성공시키기 전에는 40프레임이 완전히 잠깁니다.",
        "No production receipt exists. Forty-frame upload stays fully locked until a fresh fixed one-frame trial succeeds under this build.",
        language: language
      )
    case .awaitingVisualAttestation:
      studioText(
        "새 1프레임 host sequence·commit·postflight receipt가 있습니다. 실제 LCD 모서리 표시를 별도로 확인해야 합니다.",
        "A fresh one-frame host-sequence, commit, and postflight receipt exists. The visible LCD corners still require separate confirmation.",
        language: language
      )
    case .awaitingObservedAbsence:
      studioText(
        "육안 확인이 기록됐습니다. 이제 USB-mode cable removal 뒤 실제 장치 부재를 관찰해야 합니다.",
        "Visual confirmation is recorded. Real device absence must now be observed after USB-mode cable removal.",
        language: language
      )
    case .awaitingExactReappearance:
      studioText(
        "실제 장치 부재를 관찰했습니다. 같은 원래 Mac USB 포트에서 동일 exact 4 collection 재등장이 필요합니다.",
        "Real device absence was observed. The same exact four collections must reappear at the original Mac USB port.",
        language: language
      )
    case .awaitingWiredPowerRemovalAttestation:
      studioText(
        "부재와 동일 장치 재등장을 순서대로 관찰했습니다. 실제 cable-removal 전원 제거에 대한 마지막 사용자 확인이 필요합니다.",
        "Absence and exact reappearance were observed in order. One final user attestation is required for actual cable-removal power loss.",
        language: language
      )
    case .qualified(let maximumFrameCount):
      studioText(
        "전체 영속 provenance가 검증됐습니다. 최대 \(maximumFrameCount)프레임의 불변 editor snapshot만 별도 exact-plan 확인 뒤 적용할 수 있습니다.",
        "The complete durable provenance is verified. Only an immutable editor snapshot of at most \(maximumFrameCount) frames may be applied after a separate exact-plan confirmation.",
        language: language
      )
    case .canonicalTransferInProgress:
      studioText(
        "새 고정 1프레임 진단 lease가 다른 process에서 진행 중이거나 중단된 상태로 남았습니다. 새 전송이나 수동 해제는 허용되지 않습니다.",
        "A fresh canonical one-frame lease is active in another process or remains after an interruption. No new transfer or manual clear is allowed.",
        language: language
      )
    case .canonicalVisualMismatchQuarantinePending:
      studioText(
        "고정 진단 화면 오류/확인 불가가 기록됐고 durable quarantine 설정을 마치는 중입니다. 자동 해제·재시도하지 마세요.",
        "A wrong or unverifiable canonical diagnostic result was recorded and durable quarantine is being armed. Do not auto-clear or retry.",
        language: language
      )
    case .extendedTransferInProgress:
      studioText(
        "exact plan lease가 다른 process에서 진행 중이거나 중단된 상태로 남았습니다. 새 전송은 허용되지 않습니다. 실행 중인 process가 없다면 자동 해제하지 말고 quarantine 복구 뒤 새 고정 1프레임 진단부터 진행해야 합니다.",
        "An exact-plan lease is active in another process or remains after an interruption. No new transfer is allowed. If no process is active, do not clear it automatically; complete any quarantine recovery, then restart from a fresh fixed one-frame diagnostic.",
        language: language
      )
    case .interruptedTransferQuarantinePending:
      studioText(
        "중단된 canonical/extended lease가 성공 권한으로 돌아가지 못하도록 receipt가 고정됐습니다. durable quarantine과 자격 폐기를 완료해야 합니다.",
        "The interrupted canonical/extended lease is pinned so it cannot return to positive authority. Durable quarantine and qualification revocation must be completed.",
        language: language
      )
    case .awaitingExtendedVisualAttestation(let digest, let frameCount, let pageCount):
      studioText(
        "\(frameCount)프레임·\(pageCount)페이지 host 전송 뒤 실제 LCD 결과 확인을 기다립니다. SHA-256 \(digest.prefix(8))…\(digest.suffix(6)). 육안 확인 전에는 자격이 다시 열리지 않습니다.",
        "Awaiting visual LCD review after a \(frameCount)-frame, \(pageCount)-page host transfer. SHA-256 \(digest.prefix(8))…\(digest.suffix(6)). Qualification does not reopen before visual review.",
        language: language
      )
    case .extendedVisualMismatchQuarantinePending:
      studioText(
        "화면 오류/확인 불가가 기록됐고 durable quarantine 설정을 마치는 중입니다. 자동 해제·재시도하지 마세요.",
        "A wrong or unverifiable display result was recorded and durable quarantine is being armed. Do not auto-clear or retry.",
        language: language
      )
    case .invalidatedRequiresFreshDiagnostic:
      studioText(
        "제출됐거나 불확실한 확장 전송 실패로 자격이 무효화됐습니다. USB-mode cable recovery 뒤 새 고정 1프레임 실기부터 다시 진행해야 합니다.",
        "A submitted or uncertain extended-transfer failure invalidated qualification. Complete USB-mode cable recovery, then restart with a fresh fixed one-frame trial.",
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
          "새 build에서 고정 1프레임 16/16 + commit + postflight",
          "Fresh fixed one-frame 16/16 + commit + postflight", language: language),
        completed: stepCompletion >= 1
      )
      qualificationStep(
        number: 2,
        text: studioText(
          "네 모서리 색·위치·방향 육안 확인", "Visual corner color, position, and orientation",
          language: language),
        completed: stepCompletion >= 2
      )
      qualificationStep(
        number: 3,
        text: studioText(
          "USB mode 유지 + cable 분리 뒤 real absence 관찰",
          "Keep USB mode + disconnect cable + observe real absence", language: language),
        completed: stepCompletion >= 3
      )
      qualificationStep(
        number: 4,
        text: studioText(
          "같은 원래 USB 포트에서 동일 exact 4 collection 재등장",
          "Same exact four collections at the original USB port", language: language),
        completed: stepCompletion >= 4
      )
      qualificationStep(
        number: 5,
        text: studioText(
          "USB 전원 제거 사용자 attestation", "Wired-power-removal user attestation", language: language),
        completed: stepCompletion >= 5
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
      .extendedVisualMismatchQuarantinePending, .interruptedTransferQuarantinePending,
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
    case .qualified, .awaitingExtendedVisualAttestation:
      5
    case .extendedTransferInProgress:
      0
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
    case .receiptUnavailable, .qualified, .awaitingExtendedVisualAttestation,
      .invalidatedRequiresFreshDiagnostic, .blocked:
      nil
    case .canonicalTransferInProgress, .extendedTransferInProgress,
      .interruptedTransferQuarantinePending:
      Action(
        title: studioText(
          "중단된 lease reconcile…",
          "Reconcile interrupted lease…",
          language: language
        ),
        detail: studioText(
          "다른 process가 실행 중이 아닐 때만 quarantine으로 전환",
          "Move to quarantine only when no other process is active",
          language: language
        ),
        isEnabled: canReconcileInterruptedTransfer,
        isDestructive: true,
        perform: { showsInterruptedTransferReconciliation = true }
      )
    case .canonicalVisualMismatchQuarantinePending:
      Action(
        title: studioText(
          "고정 진단 격리 완료 재시도…",
          "Retry canonical quarantine completion…",
          language: language
        ),
        detail: studioText(
          "성공으로 되돌리지 않고 저장된 mismatch만 처리",
          "Processes only the saved mismatch; never restores success",
          language: language
        ),
        isEnabled: canReportCanonicalVisualMismatch,
        isDestructive: true,
        perform: { showsCanonicalMismatchRetry = true }
      )
    case .extendedVisualMismatchQuarantinePending:
      Action(
        title: studioText(
          "확장 전송 격리 완료 재시도…",
          "Retry extended quarantine completion…",
          language: language
        ),
        detail: studioText(
          "성공 attestation 없이 저장된 mismatch만 처리",
          "Processes only the saved mismatch, without a success attestation",
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
          "host receipt와 별개의 육안 확인", "Visual evidence separate from the host receipt",
          language: language),
        isEnabled: canRecordVisualAttestation || canReportCanonicalVisualMismatch,
        isDestructive: true,
        perform: { showsVisualAttestation = true }
      )
    case .awaitingObservedAbsence:
      Action(
        title: studioText("분리 상태 새로고침", "Refresh while disconnected", language: language),
        detail: studioText(
          "checkbox가 아니라 real IOHID 열거 0개가 필요",
          "Requires real zero-collection IOHID enumeration, not a checkbox", language: language),
        isEnabled: canRefreshHardware,
        isDestructive: false,
        perform: onRefreshHardware
      )
    case .awaitingExactReappearance:
      Action(
        title: studioText("재연결 상태 새로고침", "Refresh after reconnection", language: language),
        detail: studioText(
          "원래 Mac USB 포트와 exact 4 collection 필요",
          "Requires the original Mac USB port and exact four collections", language: language),
        isEnabled: canRefreshHardware,
        isDestructive: false,
        perform: onRefreshHardware
      )
    case .awaitingWiredPowerRemovalAttestation:
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
