import SwiftUI

@main
struct MarkdownStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            AppCommands()
            SidebarCommands()
            TextEditingCommands()
        }
        // Applies app-wide: the editor, the preview (via prefers-color-scheme) and all windows.
        .onChange(of: appearance, initial: true) { _, mode in
            NSApp.appearance = mode.appearance
        }

        Window("Welcome to Markdown Studio", id: WelcomeWindow.id) {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .commandsRemoved()

        Settings {
            SettingsView()
        }

        Window("Markdown Cheat Sheet", id: "cheatsheet") {
            CheatSheetView()
        }
        .defaultSize(width: 640, height: 720)
        .windowResizability(.contentMinSize)
    }
}
