import SwiftUI

@main
struct KeyCanvasApp: App {
  @NSApplicationDelegateAdaptor(KeyCanvasApplicationDelegate.self) private var applicationDelegate
  @StateObject private var model = StudioModel()

  var body: some Scene {
    WindowGroup("KeyCanvas") {
      StudioRootView(model: model)
        .frame(minWidth: 980, minHeight: 680)
    }
    .defaultSize(width: 1180, height: 760)
    .windowToolbarStyle(.unified)
    .commands {
      CommandMenu("Profile") {
        Button("New Local Profile") {
          model.profileStore.newProfile()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Button("Save Local Profile") {
          model.profileStore.saveSelected()
        }
        .keyboardShortcut("s", modifiers: .command)

        Divider()

        Button("Import Profile…") {
          model.profileStore.presentImportPanel()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Button("Export Profile…") {
          model.profileStore.presentExportPanel()
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
      }

      CommandGroup(after: .sidebar) {
        Button("Refresh Device Inspector") {
          model.refreshInspector()
        }
        .keyboardShortcut("r", modifiers: .command)
      }
    }
  }
}
