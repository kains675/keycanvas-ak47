import AK47InspectorCore
import SwiftUI

struct DeviceQuarantineRecoveryCard: View {
  @ObservedObject var model: StudioModel
  @Environment(\.studioLanguage) private var language
  @State private var showsPowerCycleConfirmation = false
  @State private var recoveryError: String?

  var body: some View {
    if model.deviceQuarantineRecoveryState != .notQuarantined {
      VStack(alignment: .leading, spacing: 14) {
        Label(
          studioText(
            "장치 작업 안전 격리 중",
            "Device operations are safety-quarantined",
            language: language
          ),
          systemImage: "exclamationmark.lock.fill"
        )
        .font(.headline)
        .foregroundStyle(StudioPalette.coral)

        Text(recoveryInstruction)
          .font(.callout)

        Text(
          studioText(
            "다른 AK47/키보드 설정 프로그램과 Windows 가상 머신을 모두 종료하세요. 앱 재실행, USB 핸들 닫기, 케이블만 빠르게 다시 꽂거나 selector를 2.4G/Bluetooth로 바꾸는 동작으로는 격리가 해제되지 않습니다.",
            "Quit every other AK47/keyboard utility and Windows VM. Relaunching the app, closing a USB handle, quickly replugging the cable, or moving the selector to 2.4G/Bluetooth does not clear this quarantine.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack {
          if model.deviceQuarantineRecoveryState
            == .awaitingFullPowerCycleAcknowledgement
          {
            Button {
              showsPowerCycleConfirmation = true
            } label: {
              Label(
                studioText(
                  "USB 전원 제거 완료 확인…",
                  "Confirm wired-power removal…",
                  language: language
                ),
                systemImage: "power"
              )
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioPalette.coral)
            .disabled(!model.canAcknowledgeFullPowerCycle)
          } else {
            Button {
              model.refreshInspector()
            } label: {
              Label(
                studioText(
                  "장치 상태 새로고침",
                  "Refresh device state",
                  language: language
                ),
                systemImage: "arrow.clockwise"
              )
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRefreshInspector)
          }
        }

        if let recoveryError {
          Text(recoveryError)
            .font(.caption)
            .foregroundStyle(StudioPalette.coral)
            .textSelection(.enabled)
        }
      }
      .studioPanel()
      .alert(
        studioText(
          "키보드의 USB 전원 제거 복구를 확인할까요?",
          "Confirm the keyboard's wired-power-removal recovery?",
          language: language
        ),
        isPresented: $showsPowerCycleConfirmation
      ) {
        Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
        Button(
          studioText(
            "확인하고 격리 해제",
            "Confirm and clear quarantine",
            language: language
          ),
          role: .destructive
        ) {
          do {
            try model.acknowledgeFullPowerCycle()
            recoveryError = nil
          } catch {
            recoveryError = error.localizedDescription
          }
        }
      } message: {
        Text(
          studioText(
            "다른 키보드 설정 프로그램과 Windows VM을 종료하고, selector를 USB 유선 위치에 둔 채 케이블을 분리해 LCD·LED와 장치가 완전히 꺼진 것을 확인했습니다. 분리 상태의 실제 열거 0개를 새로고침으로 확인한 뒤 같은 원래 Mac USB 포트에 다시 연결해 정상 4개 HID 컬렉션 재등장까지 확인한 경우에만 계속하세요. 2.4G/Bluetooth 전환은 이 확인을 대신하지 않습니다.",
            "Continue only if every other keyboard utility and Windows VM is closed; the selector remained in wired USB mode; the cable was disconnected until the LCD, LEDs, and device fully powered down; a real refresh observed zero matching collections; and the keyboard was reconnected to the same original Mac USB port until all four HID collections returned. Switching to 2.4G/Bluetooth does not satisfy this confirmation.",
            language: language
          )
        )
      }
    }
  }

  private var recoveryInstruction: String {
    switch model.deviceQuarantineRecoveryState {
    case .notQuarantined:
      ""
    case .awaitingObservedAbsence:
      studioText(
        "1단계: selector를 USB 유선 위치에 둔 채 케이블을 분리하고 LCD·LED와 장치가 완전히 꺼졌는지 확인하세요. 분리 상태에서 ‘장치 상태 새로고침’을 눌러 실제 열거가 0개인지 확인해야 합니다. 2.4G/Bluetooth 전환은 복구가 아닙니다.",
        "Step 1: keep the selector in wired USB mode, disconnect the cable, and verify that the LCD, LEDs, and device fully power down. While it remains disconnected, refresh device state so real enumeration observes zero matching collections. Switching to 2.4G/Bluetooth is not recovery.",
        language: language
      )
    case .awaitingExactReappearance:
      studioText(
        "2단계: selector를 USB 위치에 둔 채 키보드를 원래 Mac USB 포트에 다시 연결하세요. 그 다음 새로고침해 동일 장치의 정확한 4개 HID 컬렉션을 확인하세요.",
        "Step 2: with the selector still in USB mode, reconnect the keyboard to the original Mac USB port. Refresh again to verify the same device's exact four HID collections.",
        language: language
      )
    case .awaitingFullPowerCycleAcknowledgement:
      studioText(
        "분리 상태의 실제 열거 0개와 원래 위치에서 동일 장치의 정상 재등장을 모두 관찰했습니다. selector를 USB 위치에 유지한 채 케이블을 분리해 LCD·LED와 장치가 완전히 꺼졌는지 마지막으로 확인해야 합니다.",
        "Real enumeration observed zero matching collections and then the same device's exact reappearance at its original location. One final acknowledgement is required that the selector remained in USB mode and cable removal fully powered down the LCD, LEDs, and device.",
        language: language
      )
    }
  }
}
