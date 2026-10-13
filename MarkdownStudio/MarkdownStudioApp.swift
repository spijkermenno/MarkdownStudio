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

        Window("Set Up Markdown Studio", id: Onboarding.windowID) {
            OnboardingView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .defaultWindowPlacement { content, context in
            let size = content.sizeThatFits(.unspecified)
            let frame = context.defaultDisplay.visibleRect
            return WindowPlacement(CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), size: size)
        }
        .commandsRemoved()

        Window("Quick Open", id: QuickOpen.id) {
            QuickOpenView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .windowLevel(.floating)
        .defaultWindowPlacement { content, context in
            let size = content.sizeThatFits(.unspecified)
            let frame = context.defaultDisplay.visibleRect
            return WindowPlacement(CGPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.22), size: size)
        }
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
