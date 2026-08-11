import SwiftUI

struct DashboardView: View {
  @Environment(\.studioLanguage) private var language
  @ObservedObject var model: StudioModel
  @ObservedObject private var profileStore: LocalProfileStore

  init(model: StudioModel) {
    self.model = model
    self._profileStore = ObservedObject(wrappedValue: model.profileStore)
  }

  private let columns = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        StudioSectionHeader(
          eyebrow: studioText("작업 공간", "Workspace", language: language),
          title: studioText(
            "나에게 맞는 키보드를 그려 보세요.", "Make the keyboard feel like yours.", language: language),
          detail: studioText(
            "키 배치, 색상, 매크로, 화면 아이디어를 안전한 로컬 초안으로 살펴봅니다.",
            "Explore layouts, color, macros, and display ideas in a safe local draft.",
            language: language
          )
        )

        deviceHero

        LazyVGrid(columns: columns, spacing: 14) {
          MetricTile(
            title: studioText("HID 컬렉션", "HID collections", language: language),
            value: "\(model.collections.count)",
            symbol: "square.stack.3d.up",
            tint: StudioPalette.blue
          )
          MetricTile(
            title: studioText("초안 프로필", "Draft profiles", language: language),
            value: "\(profileStore.profiles.count)",
            symbol: "square.on.square",
            tint: StudioPalette.violet
          )
          MetricTile(
            title: studioText("장치 적용", "Device apply", language: language),
            value: studioText("개별 확인", "Confirm each", language: language),
            symbol: "hand.raised",
            tint: StudioPalette.coral
          )
        }

        Text(studioText("이어서 만들기", "Jump back in", language: language))
          .font(.title3.weight(.semibold))

        HStack(spacing: 14) {
          WorkspaceCard(
            title: studioText("집중 키맵", "Focus layout", language: language),
            detail: studioText(
              "글쓰기와 탐색에 맞춘 간결한 레이어입니다.", "A compact layer for writing and navigation.",
              language: language),
            symbol: "keyboard",
            tint: StudioPalette.blue
          ) {
            model.selection = .keymap
          }
          WorkspaceCard(
            title: studioText("오로라 워시", "Aurora wash", language: language),
            detail: studioText(
              "민트에서 보라로 흐르는 차분한 조명 시안입니다.", "A calm mint-to-violet lighting study.",
              language: language),
            symbol: "lightbulb",
            tint: StudioPalette.violet
          ) {
            model.selection = .lighting
          }
          WorkspaceCard(
            title: studioText("상태 캔버스", "Status canvas", language: language),
            detail: studioText(
              "시계와 배터리를 담은 미니멀 화면 시안입니다.", "A minimal clock and battery concept.",
              language: language),
            symbol: "display",
            tint: StudioPalette.coral
          ) {
            model.selection = .display
          }
        }

        DemoNotice()
      }
      .padding(28)
      .frame(maxWidth: 1120, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  private var deviceHero: some View {
    HStack(spacing: 22) {
      KeyCanvasMark(size: 72)

      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          Text(model.deviceName)
            .font(.title2.weight(.bold))
          StatusPill(
            label: model.connectionLabel(in: language),
            symbol: model.isConnected ? "checkmark.circle.fill" : "circle.dashed",
            tint: model.isConnected ? StudioPalette.mint : StudioPalette.muted
          )
        }
        Text("USB  ·  VID 0C45  ·  PID 800A")
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
        Text(
          studioText(
            "기본 검사는 읽기 전용입니다. 시계와 제한된 조명은 정확한 유선 장치에서 작업별 확인 후 적용됩니다. 기본값 계획과 LCD 파일 내보내기는 로컬 전용이며, LCD 장치 적용은 Display의 고정 bootstrap 또는 fresh 영속 자격을 마친 exact editor snapshot으로만 제한됩니다.",
            "Normal inspection is read only. Clock and bounded lighting apply only after per-operation confirmation on the exact wired device. Default plans and LCD file export stay local; LCD device Apply is limited to Display's fixed bootstrap or an exact editor snapshot with complete fresh durable qualification.",
            language: language
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        model.selection = .deviceInspector
      } label: {
        Label(studioText("검사하기", "Inspect", language: language), systemImage: "arrow.right")
      }
      .buttonStyle(.bordered)
    }
    .studioPanel(padding: 22)
  }
}

private struct WorkspaceCard: View {
  let title: String
  let detail: String
  let symbol: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        Image(systemName: symbol)
          .font(.title2.weight(.semibold))
          .foregroundStyle(tint)
          .frame(width: 42, height: 42)
          .background(
            tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
      .studioPanel(padding: 16)
    }
    .buttonStyle(.plain)
  }
}
