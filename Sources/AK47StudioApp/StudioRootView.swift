import SwiftUI

struct StudioRootView: View {
  @ObservedObject var model: StudioModel
  @AppStorage("inspectorRefreshesAtLaunch") private var inspectorRefreshesAtLaunch = true

  var body: some View {
    NavigationSplitView {
      List(StudioSection.allCases, selection: $model.selection) { section in
        NavigationLink(value: section) {
          SidebarRow(section: section, language: model.language)
        }
      }
      .navigationTitle("KeyCanvas")
      .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 290)
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 10) {
          Divider()
          DemoNotice(compact: true)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
      }
    } detail: {
      detailView
        .environment(\.studioLanguage, model.language)
        .background {
          LinearGradient(
            colors: [
              StudioPalette.blue.opacity(0.035),
              Color.clear,
              StudioPalette.mint.opacity(0.025),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .ignoresSafeArea()
        }
        .toolbar {
          ToolbarItem {
            ProfileToolbarMenu(store: model.profileStore, language: model.language)
          }
          ToolbarItem(placement: .primaryAction) {
            StatusPill(
              label: model.connectionLabel(in: model.language),
              symbol: model.isConnected ? "checkmark.circle.fill" : "circle.dashed",
              tint: model.isConnected ? StudioPalette.mint : StudioPalette.muted
            )
          }
        }
    }
    .task {
      if inspectorRefreshesAtLaunch, model.inspectorState == .idle {
        model.refreshInspector()
      }
    }
    .onChange(of: model.selection) { selection in
      UserDefaults.standard.set(selection.rawValue, forKey: "lastStudioSection")
    }
    .onChange(of: model.language) { language in
      UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
    }
  }

  @ViewBuilder
  private var detailView: some View {
    switch model.selection {
    case .dashboard:
      DashboardView(model: model)
    case .keymap:
      KeymapView(profileStore: model.profileStore)
    case .lighting:
      LightingView(profileStore: model.profileStore)
    case .macros:
      MacrosView(profileStore: model.profileStore)
    case .display:
      DisplayComposerView(profileStore: model.profileStore)
    case .settings:
      SettingsView(model: model)
    case .deviceInspector:
      DeviceInspectorView(model: model)
    }
  }
}

private struct ProfileToolbarMenu: View {
  @ObservedObject var store: LocalProfileStore
  let language: AppLanguage

  var body: some View {
    Menu {
      Picker(
        studioText("활성 프로필", "Active profile", language: language), selection: $store.selectedID
      ) {
        ForEach(Array(store.profiles.enumerated()), id: \.offset) { _, profile in
          Text(profile.name).tag(profile.identifier)
        }
      }

      Divider()

      Button(studioText("새 로컬 프로필", "New local profile", language: language), systemImage: "plus") {
        store.newProfile()
      }
      Button(
        studioText("로컬에 저장", "Save locally", language: language),
        systemImage: "square.and.arrow.down"
      ) {
        store.saveSelected()
      }
      Button(
        studioText("JSON 가져오기…", "Import JSON…", language: language),
        systemImage: "square.and.arrow.down.on.square"
      ) {
        store.presentImportPanel()
      }
      Button(
        studioText("JSON 내보내기…", "Export JSON…", language: language),
        systemImage: "square.and.arrow.up"
      ) {
        store.presentExportPanel()
      }
    } label: {
      Label(store.selectedProfile.name, systemImage: "folder")
    }
    .help(store.statusLabel)
  }
}

private struct SidebarRow: View {
  let section: StudioSection
  let language: AppLanguage

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: section.symbol)
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text(section.title(in: language))
          .font(.callout.weight(.medium))
        Text(section.subtitle(in: language))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 3)
  }
}

#Preview("Connected") {
  StudioRootView(model: StudioModel(provider: PreviewHIDCollectionProvider()))
    .frame(width: 1180, height: 760)
}
