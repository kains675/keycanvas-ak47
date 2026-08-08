import AK47InspectorCore
import SwiftUI

struct DeviceInspectorView: View {
  @ObservedObject var model: StudioModel
  @Environment(\.studioLanguage) private var language

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 20) {
          StudioSectionHeader(
            eyebrow: studioText("속성 전용", "Properties only", language: language),
            title: studioText("장치 검사기", "Device Inspector", language: language),
            detail: studioText(
              "일치하는 HID 컬렉션의 레지스트리 속성을 엽니다. 장치 open, report 전송, 펌웨어 작업은 수행하지 않습니다.",
              "View registry properties for matching HID collections. The device is not opened; no reports or firmware operations occur.",
              language: language
            )
          )

          Button {
            model.refreshInspector()
          } label: {
            Label(studioText("새로고침", "Refresh", language: language), systemImage: "arrow.clockwise")
          }
          .buttonStyle(.bordered)
          .disabled(model.inspectorState == .scanning)
        }

        safetyBanner

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
          collectionList
        }
      }
      .padding(28)
      .frame(maxWidth: 1060)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  private var safetyBanner: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "lock.shield.fill")
        .font(.title3)
        .foregroundStyle(StudioPalette.mint)
      VStack(alignment: .leading, spacing: 4) {
        Text(studioText("읽기 전용 경계가 적용됩니다", "Read-only boundary enforced", language: language))
          .font(.headline)
        Text(
          studioText(
            "현재 앱 target에는 HID 쓰기, feature report, output report, 부트로더 진입 API가 없습니다.",
            "This app target contains no HID write, feature report, output report, or bootloader-entry API.",
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
      }
    }
    .studioPanel()
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
