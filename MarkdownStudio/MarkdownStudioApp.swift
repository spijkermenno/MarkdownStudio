import SwiftUI

@main
struct MarkdownStudioApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system

    init() {
        PlatformDefaults.register()
    }

    #if os(macOS)
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
        }
        // Without this, documents open at their minimum size. Most of the screen,
        // capped so large displays don't get wall-to-wall windows. Only the size is
        // set, so macOS still cascades each new window.
        .defaultWindowPlacement { _, context in
            let screen = context.defaultDisplay.visibleRect.size
            return WindowPlacement(size: CGSize(width: min(screen.width * 0.85, 1600),
                                                height: min(screen.height * 0.88, 1100)))
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
    #else
    var body: some Scene {
        // The document browser, with the app's name and a New Document button.
        DocumentGroupLaunchScene("Markdown Studio") {
            NewDocumentButton("New Document")
        } background: {
            LinearGradient(colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }

        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            AppCommands()
        }
        .onChange(of: appearance, initial: true) { _, mode in
            Platform.apply(mode)
        }
    }
    #endif
}
