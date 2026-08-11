import AK47InspectorCore
import SwiftUI

struct DeviceInspectorView: View {
  @ObservedObject var model: StudioModel
  @Environment(\.studioLanguage) private var language
  @State private var showsRGBQueryConfirmation = false
  @State private var showsClockSyncConfirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          StudioSectionHeader(
            eyebrow: studioText("HID 진단", "HID diagnostics", language: language),
            title: studioText("장치 검사기", "Device Inspector", language: language),
            detail: studioText(
              "기본 진단은 HID 속성과 직접 GetReport만 읽습니다. 시계 동기화와 키별 F5 조회는 각각 별도 확인 뒤 정확한 유선 장치에서 한 번 실행됩니다. 조명 적용은 조명 화면에서 별도로 확인하며 펌웨어 작업은 수행하지 않습니다.",
              "Normal diagnostics read HID properties and direct GetReport data only. Clock sync and the per-key F5 query each run once after separate confirmation on the exact wired device. Lighting apply is confirmed separately in Lighting, and no firmware operation occurs.",
              language: language
            )
          )

          Button {
            model.refreshInspector()
          } label: {
            Label(studioText("새로고침", "Refresh", language: language), systemImage: "arrow.clockwise")
          }
          .buttonStyle(.bordered)
          .disabled(!model.canRefreshInspector)
        }

        safetyBanner
        DeviceQuarantineRecoveryCard(model: model)

        if case .scanning = model.inspectorState {
          HStack(spacing: 12) {
            ProgressView()
            Text(
              studioText(
                "IOHID 레지스트리 속성을 확인하는 중…", "Reading IOHID registry properties…", language: language)
            )
          }
          .frame(maxWidth: .infinity, minHeight: 160)
          .studioPanel()
        } else if case .failed(let message) = model.inspectorState {
          inspectorError(message)
        } else if model.collections.isEmpty {
          emptyState
        } else {
          summary
          clockSyncPanel
          readOnlyReportProbe
          experimentalRGBQuery
          collectionList
        }
      }
      .padding(28)
      .frame(maxWidth: 1060)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .alert(
      studioText("키보드 시계를 동기화할까요?", "Synchronize the keyboard clock?", language: language),
      isPresented: $showsClockSyncConfirmation
    ) {
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
      Button(studioText("지금 동기화", "Sync now", language: language)) {
        model.synchronizeClockNow()
      }
    } message: {
      Text(
        studioText(
          "제조사 유틸리티·Windows VM·다른 HID 도구를 모두 종료한 뒤 진행하세요. 현재 Mac의 로컬 날짜와 시각을 첫 번째 화면 슬롯에 한 번 전송합니다. ACK가 정의된 단계의 byte 3을 확인하며 자동 재시도하지 않습니다. 현재 장치 시각을 읽거나 이전 값으로 되돌리는 기능은 없습니다.",
          "Quit the vendor utility, every Windows VM, and other HID tools before continuing. This sends the Mac's current local date and time once to the first display slot. ACK-required stages validate byte 3 and never retry automatically. The current device time cannot be read back or restored.",
          language: language
        )
      )
    }
  }

  private var clockSyncPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          Label(
            studioText("시계 동기화", "Clock synchronization", language: language),
            systemImage: "clock.arrow.circlepath"
          )
          .font(.headline)
          Text(
            studioText(
              "확인된 시계 Feature 순서로 로컬 시각을 한 번 전송합니다. 각 명령과 필요한 ACK 사이에 35ms 간격을 두고 비동기 작업마다 360ms에서 중단하며, 펌웨어나 다른 설정 영역에는 접근하지 않습니다.",
              "Sends local time once through the verified clock Feature sequence. It uses 35 ms pacing between commands and required ACKs, limits each asynchronous operation to 360 ms, and does not access firmware or other settings regions.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          showsClockSyncConfirmation = true
        } label: {
          Label(
            studioText("시계 동기화…", "Sync clock…", language: language),
            systemImage: "clock"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.coral)
        .disabled(!model.canSynchronizeClock)
      }

      switch model.deviceWriteState {
      case .writing(.clockSync):
        HStack(spacing: 10) {
          ProgressView()
          Text(studioText("ACK를 확인하며 전송 중…", "Sending with ACK validation…", language: language))
        }
        .font(.callout)
      case .succeeded(.clockSync, let date):
        Label(
          studioText(
            "시계 동기화 완료 · \(date.formatted(date: .omitted, time: .standard))",
            "Clock synchronized · \(date.formatted(date: .omitted, time: .standard))",
            language: language
          ),
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(StudioPalette.mint)
      case .failed(.clockSync, let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      default:
        Label(
          studioText(
            "명시적으로 누를 때만 한 번 실행됩니다.",
            "Runs once only after an explicit click.",
            language: language
          ),
          systemImage: "hand.tap"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .studioPanel()
  }

  private var safetyBanner: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "lock.shield.fill")
        .font(.title3)
        .foregroundStyle(StudioPalette.mint)
      VStack(alignment: .leading, spacing: 4) {
        Text(
          studioText(
            "기본 진단은 읽기 전용입니다",
            "Normal diagnostics are read only",
            language: language
          )
        )
        .font(.headline)
        Text(
          studioText(
            "읽기 전용 report 진단은 GetReport만 호출합니다. F5 RGB 조회와 시계·조명 적용은 서로 다른 확인이 필요합니다. Display의 고정 1프레임 LCD bootstrap과 fresh 영속 자격을 마친 현재 editor의 불변 1…40프레임 plan은 각각 동일한 단일 실험 기능 위험 확인 뒤 한 번만 적용할 수 있습니다. 기본값 계획은 Settings dry-run이고 raw LCD payload·키맵·매크로·펌웨어·부트로더 live 작업은 없습니다.",
            "The read-only report probe calls GetReport only. F5 RGB and clock or lighting apply require distinct confirmations. Display's fixed one-frame LCD bootstrap and an immutable 1...40-frame current-editor plan with fresh durable qualification may each be applied once after the same single experimental-feature risk acknowledgement. Default-plan inspection is a Settings dry run, and there is no raw LCD payload, keymap, macro, firmware, or bootloader live operation.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Text("VID 0C45 · PID 800A")
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
    .studioPanel(padding: 16)
  }

  private var experimentalRGBQuery: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          Label(
            studioText(
              "실험적 키별 RGB 1회 조회",
              "Experimental one-shot per-key RGB query",
              language: language
            ),
            systemImage: "lightbulb.2"
          )
          .font(.headline)

          Text(
            studioText(
              "유선 revision 0x0115의 FF13 설정 채널에 검증된 조회 명령을 한 번 보내고 64바이트 응답 9개를 읽습니다. 결과는 메모리에만 표시하며 프로필이나 파일에 저장하지 않습니다.",
              "Sends the verified query once to the wired revision 0x0115 FF13 command channel and reads nine 64-byte responses. Results stay in memory and are not saved to a profile or file.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          showsRGBQueryConfirmation = true
        } label: {
          Label(
            studioText("1회 조회…", "Query once…", language: language),
            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.coral)
        .disabled(!model.canRunPerKeyRGBQuery)
      }

      switch model.perKeyRGBQueryState {
      case .idle:
        Label(
          studioText(
            "자동으로 실행되지 않습니다. 실행 전 현재 조명 상태를 눈으로 확인해 두세요.",
            "This never runs automatically. Note the current lighting before continuing.",
            language: language
          ),
          systemImage: "hand.raised"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      case .reading:
        HStack(spacing: 10) {
          ProgressView()
          Text(
            studioText(
              "조회 1회와 종료 응답을 확인하는 중…",
              "Running one query and validating its finish response…",
              language: language
            )
          )
        }
        .font(.callout)
      case .failed(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption.monospaced())
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      case .ready(let snapshot):
        rgbQueryResult(snapshot)
      }
    }
    .studioPanel()
    .alert(
      studioText("실험적 장치 질의", "Experimental device query", language: language),
      isPresented: $showsRGBQueryConfirmation
    ) {
      Button(studioText("취소", "Cancel", language: language), role: .cancel) {}
      Button(
        studioText("정확히 1회 실행", "Run exactly once", language: language),
        role: .destructive
      ) {
        model.runPerKeyRGBQueryOnce()
      }
    } message: {
      Text(
        studioText(
          "제조사 유틸리티·Windows VM·다른 HID 도구를 모두 종료한 뒤 진행하세요. 이 동작은 키별 색상 조회용 Feature 명령과 정상 종료 명령을 전송합니다. Windows 앱에서는 조회 경로이지만 설정이 전혀 바뀌지 않는지는 실제 장치에서 아직 확인되지 않았습니다. 실패하면 selector를 USB 위치에 유지하고 케이블을 분리해 LCD·LED가 완전히 꺼지고 실제 열거가 0이 되는지 확인하는 안전 격리 절차를 수행해야 합니다. 2.4G/Bluetooth 전환은 복구가 아닙니다.",
          "Quit the vendor utility, every Windows VM, and other HID tools before continuing. This sends a Feature command for per-key color readback and a normal finish command. The Windows app uses it as a read path, but unchanged device state has not yet been confirmed on hardware. A failure requires the safety-quarantine flow: keep the selector in USB mode, disconnect the cable, verify that the LCD and LEDs fully power down, and refresh until real enumeration reaches zero. Switching to 2.4G/Bluetooth is not recovery.",
          language: language
        )
      )
    }
  }

  private func rgbQueryResult(_ snapshot: AK47PerKeyRGBSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        studioText(
          "종료 응답까지 확인했습니다.",
          "The finish response was validated.",
          language: language
        ),
        systemImage: "checkmark.seal.fill"
      )
      .foregroundStyle(StudioPalette.mint)

      HStack(spacing: 20) {
        InspectorFact(
          label: studioText("읽은 키", "Keys read", language: language),
          value: "\(snapshot.values.count)"
        )
        InspectorFact(
          label: studioText("0이 아닌 색", "Nonzero colors", language: language),
          value: "\(snapshot.nonzeroColorCount)"
        )
        InspectorFact(
          label: studioText("서로 다른 색", "Distinct colors", language: language),
          value: "\(snapshot.distinctColorCount)"
        )
      }

      LazyVGrid(
        columns: Array(repeating: GridItem(.fixed(16), spacing: 5), count: 14),
        alignment: .leading,
        spacing: 5
      ) {
        ForEach(snapshot.values, id: \.lightIndex) { value in
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
              Color(
                red: Double(value.color.red) / 255,
                green: Double(value.color.green) / 255,
                blue: Double(value.color.blue) / 255
              )
            )
            .overlay(
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
            )
            .frame(width: 16, height: 16)
            .help(
              "#\(value.lightIndex) · RGB \(value.color.red), \(value.color.green), \(value.color.blue)"
            )
        }
      }

      Text(
        studioText(
          "이 결과는 조회 시점에 밝기가 적용된 84키 RGB 출력 프레임입니다. 저장된 원본 색상표나 내장 효과 설정의 백업으로 사용할 수 없습니다.",
          "This is the brightness-adjusted 84-key RGB output frame observed at query time. It is not a backup of the stored source colors or onboard-effect settings.",
          language: language
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var summary: some View {
    let record = model.collections[0]
    return VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            record.product ?? studioText("이름 없는 HID 장치", "Unnamed HID device", language: language)
          )
          .font(.title3.weight(.bold))
          Text([record.manufacturer, record.transport].compactMap { $0 }.joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        StatusPill(
          label: studioText("감지됨", "Detected", language: language), symbol: "checkmark.circle.fill")
      }

      HStack(spacing: 20) {
        InspectorFact(label: "Vendor ID", value: hex(record.vendorID, width: 4))
        InspectorFact(label: "Product ID", value: hex(record.productID, width: 4))
        InspectorFact(
          label: studioText("컬렉션", "Collections", language: language),
          value: "\(model.collections.count)")
        InspectorFact(
          label: "Location ID", value: record.locationID.map { hex($0, width: 8) } ?? "—")
        InspectorFact(
          label: "bcdDevice",
          value: record.versionNumber.map { hex($0, width: 4) } ?? "—")
      }

      Label(
        studioText(
          "bcdDevice는 USB 장치 descriptor의 release 번호입니다. 이 값만으로 설치된 펌웨어 버전이나 MCU 종류를 확정할 수 없습니다.",
          "bcdDevice is the USB device descriptor release number. It does not by itself identify the installed firmware version or MCU.",
          language: language
        ),
        systemImage: "info.circle"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .studioPanel()
  }

  private var readOnlyReportProbe: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          Text(studioText("읽기 전용 report 진단", "Read-only report probe", language: language))
            .font(.headline)
          Text(
            studioText(
              "현재 설정을 요청하는 명령은 보내지 않습니다. feature 64B와 LCD output 4096B를 직접 읽을 수 있는지만 확인합니다.",
              "No current-settings query is sent. This only checks whether the 64-byte feature and 4096-byte LCD output reports can be read directly.",
              language: language
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          model.runReadOnlyReportProbe()
        } label: {
          Label(
            studioText("지금 읽기", "Read now", language: language),
            systemImage: "arrow.down.doc"
          )
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioPalette.blue)
        .disabled(!model.canRunReadOnlyReportProbe)
      }

      switch model.deviceReadProbeState {
      case .idle:
        Label(
          studioText(
            "자동으로 실행되지 않으며 원시 report를 파일에 저장하지 않습니다.",
            "It never runs automatically and does not save raw reports to a file.",
            language: language
          ),
          systemImage: "hand.tap"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      case .reading:
        HStack(spacing: 10) {
          ProgressView()
          Text(studioText("두 collection을 읽는 중…", "Reading two collections…", language: language))
        }
        .font(.callout)
      case .failed(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption.monospaced())
          .foregroundStyle(StudioPalette.coral)
          .textSelection(.enabled)
      case .ready(let snapshot):
        probeResult(snapshot)
      }
    }
    .studioPanel()
  }

  private func probeResult(_ snapshot: DeviceReadProbeSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(
          systemName: snapshot.featureNonzeroByteCount == 0
            ? "checkmark.circle"
            : "info.circle"
        )
        .foregroundStyle(StudioPalette.mint)
        Text(
          studioText(
            "Feature GET: \(snapshot.featureLength)B 성공 · 0이 아닌 byte \(snapshot.featureNonzeroByteCount)개",
            "Feature GET: \(snapshot.featureLength) B · \(snapshot.featureNonzeroByteCount) nonzero bytes",
            language: language
          )
        )
        .font(.callout.monospacedDigit())
      }

      switch snapshot.bulkOutputResult {
      case .read(let length, let nonzeroByteCount):
        Label(
          studioText(
            "LCD output GET: \(length)B 성공 · 0이 아닌 byte \(nonzeroByteCount)개",
            "LCD output GET: \(length) B · \(nonzeroByteCount) nonzero bytes",
            language: language
          ),
          systemImage: "checkmark.circle"
        )
        .font(.callout.monospacedDigit())
      case .unavailable(let message):
        VStack(alignment: .leading, spacing: 3) {
          Label(
            studioText(
              "LCD output GET은 장치가 제공하지 않습니다.",
              "The device does not expose LCD output through GET_REPORT.",
              language: language
            ),
            systemImage: "xmark.circle"
          )
          .font(.callout)
          Text(message)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }

      if snapshot.featureNonzeroByteCount == 0 {
        Text(
          studioText(
            "직접 GET은 0으로 채워진 report만 반환했습니다. 현재 키맵·내장 모드 파라미터·일반 설정 백업에는 별도의 조회 명령이 필요하지만, 이 읽기 전용 진단은 selector 명령을 보내지 않습니다. 별도 F5 조회는 84키 RGB만 읽습니다.",
            "A direct GET returned only zero-filled data. Backing up the current keymap, onboard-mode parameters, or general settings would require a separate query command, but this read-only probe sends no selector. The separate F5 query reads only the 84-key RGB buffer.",
            language: language
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var collectionList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(studioText("HID 컬렉션", "HID collections", language: language))
          .font(.headline)
        Spacer()
        if let lastScan = model.lastScan {
          Text(lastScan, style: .time)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      ForEach(Array(model.collections.enumerated()), id: \.offset) { index, record in
        CollectionRow(index: index + 1, record: record, language: language)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 14) {
      Image(systemName: "keyboard.badge.ellipsis")
        .font(.system(size: 38))
        .foregroundStyle(.secondary)
      Text(studioText("일치하는 키보드를 찾지 못했습니다", "No matching keyboard found", language: language))
        .font(.title3.weight(.semibold))
      Text(
        studioText(
          "USB 케이블 연결 상태를 확인한 뒤 다시 검사하세요. 다른 VID/PID 장치는 표시하지 않습니다.",
          "Check the USB cable and refresh. Devices with other VID/PID values are intentionally hidden.",
          language: language
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      Button(studioText("다시 검사", "Scan again", language: language)) {
        model.refreshInspector()
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.blue)
    }
    .frame(maxWidth: .infinity, minHeight: 280)
    .studioPanel()
  }

  private func inspectorError(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(
        studioText("검사할 수 없습니다", "Inspection unavailable", language: language),
        systemImage: "exclamationmark.triangle"
      )
      .font(.headline)
      .foregroundStyle(StudioPalette.coral)
      Text(message)
        .font(.callout.monospaced())
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studioPanel()
  }

  private func hex(_ value: UInt64, width: Int) -> String {
    "0x" + String(value, radix: 16, uppercase: true).leftPadded(to: width, with: "0")
  }
}

private struct CollectionRow: View {
  let index: Int
  let record: HIDCollectionRecord
  let language: AppLanguage

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: roleSymbol)
        .font(.title3.weight(.semibold))
        .foregroundStyle(roleTint)
        .frame(width: 42, height: 42)
        .background(
          roleTint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text("#\(index) · \(roleLabel)")
            .font(.headline)
          Text(record.role.rawValue)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        Text("Usage \(hex(record.usagePage))/\(hex(record.usage))")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }

      Spacer()

      ReportMetric(label: "IN", value: record.maxInputReportSize)
      ReportMetric(label: "OUT", value: record.maxOutputReportSize)
      ReportMetric(label: "FEATURE", value: record.maxFeatureReportSize)
    }
    .studioPanel(padding: 14)
  }

  private var roleLabel: String {
    switch record.role {
    case .keyboard: studioText("키보드", "Keyboard", language: language)
    case .consumer: studioText("미디어 제어", "Consumer controls", language: language)
    case .vendorFeature64: studioText("Vendor feature", "Vendor feature", language: language)
    case .vendorOutput4096: studioText("Vendor output", "Vendor output", language: language)
    case .unknown: studioText("알 수 없음", "Unknown", language: language)
    }
  }

  private var roleSymbol: String {
    switch record.role {
    case .keyboard: "keyboard"
    case .consumer: "play.circle"
    case .vendorFeature64: "slider.horizontal.3"
    case .vendorOutput4096: "arrow.up.square"
    case .unknown: "questionmark.square.dashed"
    }
  }

  private var roleTint: Color {
    switch record.role {
    case .keyboard: StudioPalette.blue
    case .consumer: StudioPalette.mint
    case .vendorFeature64: StudioPalette.violet
    case .vendorOutput4096: StudioPalette.coral
    case .unknown: StudioPalette.muted
    }
  }

  private func hex(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    return "0x" + String(value, radix: 16, uppercase: true).leftPadded(to: 4, with: "0")
  }
}

private struct ReportMetric: View {
  let label: String
  let value: UInt64?

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value.map { "\($0) B" } ?? "—")
        .font(.caption.monospacedDigit())
    }
    .frame(width: 58, alignment: .trailing)
  }
}

private struct InspectorFact: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout.weight(.semibold).monospaced())
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension String {
  fileprivate func leftPadded(to length: Int, with character: Character) -> String {
    String(repeating: String(character), count: max(0, length - count)) + self
  }
}
