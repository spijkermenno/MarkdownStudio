import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.session) private var session

    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = false
    @AppStorage(SettingsKey.highlightCurrentLine) private var highlightCurrentLine = true
    @AppStorage(SettingsKey.typewriterScrolling) private var typewriterScrolling = false
    @AppStorage(SettingsKey.focusMode) private var focusMode = false
    @AppStorage(SettingsKey.syncScroll) private var syncScroll = true
    @AppStorage(SettingsKey.showStatusBar) private var showStatusBar = true
    @AppStorage(SettingsKey.showFormattingBar) private var showFormattingBar = false
    @AppStorage(SettingsKey.showProblems) private var showProblems = false
    @AppStorage(SettingsKey.slideSeparator) private var slideSeparator = SlideSeparator.automatic

    private var canEdit: Bool { session != nil }

    var body: some Commands {
        // File
        #if os(macOS)
        CommandGroup(after: .newItem) {
            TemplateMenu()
            Divider()
            FolderMenuItems()
        }
        #endif
        CommandGroup(after: .importExport) {
            Menu("Export") {
                Button("HTML…") { session?.exportHTML() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("PDF…") { session?.exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("Slides as PDF…") { session?.exportSlidesPDF(separator: slideSeparator) }
            }
            .disabled(!canEdit)
        }
        CommandGroup(replacing: .printItem) {
            // ⌘P is Quick Open (as in code editors), so Print uses ⇧⌘P.
            Button("Print…") { session?.printDocument() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!canEdit)
        }

        // Edit
        CommandGroup(after: .pasteboard) {
            #if os(macOS)
            // iPadOS has Edit → Paste and Match Style on the same keys.
            Button("Paste as Plain Text") { session?.editor.textView.pasteAsPlainText(nil) }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
                .disabled(!canEdit)
            Divider()
            #endif
            Button("Copy as HTML") { session?.copyHTML() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(!canEdit)
            Button("Copy as Rich Text") { session?.copyRichText() }
                .disabled(!canEdit)
            Divider()
            Button("Go to Line…") {
                session?.isShowingGoToLine = true
            }
            .keyboardShortcut("l")
            .disabled(!canEdit)
            #if os(macOS)
            Button("Find in Folder…") { session?.showSidebar(.search) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!(session?.isInWorkspace ?? false))
            #endif
        }

        // Format (replaces the rich-text Font/Text items)
        CommandGroup(replacing: .textFormatting) {
            formatButton("Bold", .bold, "b")
            formatButton("Italic", .italic, "i")
            formatButton("Strikethrough", .strikethrough, "x", [.command, .shift])
            formatButton("Highlight", .highlight, "h", [.command, .shift])
            formatButton("Inline Code", .inlineCode, "k", [.command, .shift])
            Divider()
            formatButton("Link", .link, "k")
            formatButton("Image", .image, "i", [.command, .shift])
            Divider()
            Menu("Heading") {
                formatButton("Paragraph", .heading(0), "0", [.command, .option])
                ForEach(1...6, id: \.self) { level in
                    formatButton("Heading \(level)", .heading(level), KeyEquivalent(Character("\(level)")), [.command, .option])
                }
            }
            formatButton("Cycle Heading Level", .cycleHeading, "/")
            formatButton("Blockquote", .blockquote, "'")
            Divider()
            formatButton("Bulleted List", .bulletList, "8", [.command, .shift])
            formatButton("Numbered List", .numberedList, "7", [.command, .shift])
            formatButton("Task List", .taskList, "9", [.command, .shift])
            formatButton("Indent", .indent, "]")
            formatButton("Outdent", .outdent, "[")
            Divider()
            formatButton("Code Block", .codeBlock, "k", [.command, .option])
            formatButton("Horizontal Rule", .horizontalRule, nil)
            formatButton("Insert Table", .table, nil)
            formatButton("Format Table", .formatTable, "t", [.command, .option, .shift])
            formatButton("Insert Table of Contents", .tableOfContents, nil)
            Divider()
            formatButton("Move Line Up", .moveLinesUp, .upArrow, .option)
            formatButton("Move Line Down", .moveLinesDown, .downArrow, .option)
            formatButton("Duplicate Line", .duplicateLines, "d", [.command, .shift])
            formatButton("Renumber List", .renumberList, nil)
        }

        // View
        CommandGroup(before: .sidebar) {
            viewModeToggle(.editor, "1")
            viewModeToggle(.split, "2")
            viewModeToggle(.preview, "3")
            Button(session?.splitOrientation == .vertical ? "Split Side by Side" : "Split Top and Bottom") {
                guard let session else { return }
                session.splitOrientation = session.splitOrientation == .horizontal ? .vertical : .horizontal
                if session.viewMode != .split { session.viewMode = .split }
            }
            .keyboardShortcut("4")
            .disabled(!canEdit)
            Toggle("Sync Scrolling", isOn: $syncScroll)
            Divider()
            Button("Zoom In") { session?.zoomIn() }.keyboardShortcut("+").disabled(!canEdit)
            Button("Zoom Out") { session?.zoomOut() }.keyboardShortcut("-").disabled(!canEdit)
            Button("Actual Size") { session?.resetZoom() }.keyboardShortcut("0").disabled(!canEdit)
            Divider()
            Toggle("Line Numbers", isOn: $showLineNumbers)
            Toggle("Highlight Current Line", isOn: $highlightCurrentLine)
            Toggle("Typewriter Scrolling", isOn: $typewriterScrolling)
            Toggle("Focus Mode", isOn: $focusMode)
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            #if os(macOS)
            Button(session?.distractionFree == true ? "Exit Distraction-Free Mode" : "Distraction-Free Mode") {
                session?.toggleDistractionFree()
            }
            .keyboardShortcut("d", modifiers: [.command, .control, .shift])
            .disabled(!canEdit)
            #endif
            Divider()
            Button("Show Outline") { session?.showSidebar(.outline) }.disabled(!canEdit)
            #if os(macOS)
            Button("Show Files") { session?.showSidebar(.files) }.disabled(!(session?.isInWorkspace ?? false))
            #endif
            Toggle("Show Problems", isOn: $showProblems)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Start Presentation") { session?.startPresentation(separator: slideSeparator) }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!canEdit)
            Divider()
            Toggle("Show Formatting Bar", isOn: $showFormattingBar)
            Toggle("Show Status Bar", isOn: $showStatusBar)
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            Divider()
        }

        #if os(macOS)
        // Window
        CommandGroup(before: .windowList) {
            WelcomeMenuItem()
            Divider()
        }

        // Help
        CommandGroup(replacing: .help) {
            HelpMenuItems()
        }
        #endif
    }

    private func formatButton(_ title: String, _ command: FormatCommand, _ key: KeyEquivalent?,
                              _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { session?.perform(command) }
            .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: modifiers) })
            .disabled(!canEdit)
    }

    private func viewModeToggle(_ mode: ViewMode, _ key: KeyEquivalent) -> some View {
        Toggle(mode.title, isOn: Binding(
            get: { session?.viewMode == mode },
            set: { _ in session?.viewMode = mode }
        ))
        .keyboardShortcut(key)
        .disabled(!canEdit)
    }
}

#if os(macOS)
/// File → New from Template.
struct TemplateMenu: View {
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        Menu("New from Template") {
            let templates = TemplateLibrary.all
            ForEach(templates) { template in
                Button(template.name) {
                    let text = template.filled()
                    newDocument { MarkdownDocument(text: text) }
                }
            }
            Divider()
            Button("Open Templates Folder…") { TemplateLibrary.revealUserTemplatesFolder() }
        }
    }
}

private struct FolderMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Folder…") {
            Workspace.shared.chooseFolder()
        }
        .keyboardShortcut("o", modifiers: [.command, .option])
        Button("Quick Open…") { openWindow(id: QuickOpen.id) }
            .keyboardShortcut("p")
    }
}

private struct WelcomeMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Welcome to Markdown Studio") { openWindow(id: WelcomeWindow.id) }
            .keyboardShortcut("1", modifiers: [.command, .shift])
    }
}

private struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        Button("Markdown Cheat Sheet") { openWindow(id: "cheatsheet") }
            .keyboardShortcut("?", modifiers: [.command, .option])
        Button("Open Showcase Document") {
            newDocument { MarkdownDocument(text: Showcase.text) }
        }
        Button("Onboarding & Tour…") {
            if let session = TourStep.activeSession, session.tourStep != nil {
                session.window?.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: Onboarding.windowID)
            }
        }
        Divider()
        Link("Markdown Guide Website", destination: URL(string: "https://www.markdownguide.org/")!)
    }
}
#endif

nonisolated enum Showcase {
    static var text: String {
        guard let url = Bundle.main.url(forResource: "Showcase", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "# Showcase\n" }
        return text
    }
}
