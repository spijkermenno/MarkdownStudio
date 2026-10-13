import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Editor", systemImage: "square.and.pencil") { EditorSettings() }
            Tab("Preview", systemImage: "eye") { PreviewSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system
    @AppStorage(SettingsKey.defaultViewMode) private var defaultViewMode = ViewMode.split
    @AppStorage(SettingsKey.defaultSplitOrientation) private var defaultOrientation = SplitOrientation.horizontal
    @AppStorage(SettingsKey.syncScroll) private var syncScroll = true
    @AppStorage(SettingsKey.showStatusBar) private var showStatusBar = true
    @AppStorage(SettingsKey.showFormattingBar) private var showFormattingBar = false

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("New windows open in", selection: $defaultViewMode) {
                ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Split layout", selection: $defaultOrientation) {
                ForEach(SplitOrientation.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Sync scrolling between editor and preview", isOn: $syncScroll)
            Toggle("Show status bar", isOn: $showStatusBar)
            Toggle("Show formatting bar", isOn: $showFormattingBar)
            Section("Markdown Files") {
                DefaultAppRow()
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shows whether .md files open in Markdown Studio and offers to change it.
private struct DefaultAppRow: View {
    @State private var isDefault = DefaultAppHandler.isDefault
    @State private var error: String?

    var body: some View {
        LabeledContent {
            if isDefault {
                Label("Default app", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Make Default") {
                    Task {
                        do {
                            try await DefaultAppHandler.makeDefault()
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                        isDefault = DefaultAppHandler.isDefault
                    }
                }
            }
        } label: {
            Text("Open .md files with Markdown Studio")
            if let error {
                Text(error).foregroundStyle(.red)
            } else if !isDefault, let current = DefaultAppHandler.currentDefaultName {
                Text("Currently opens in \(current)")
            }
        }
        .onAppear { isDefault = DefaultAppHandler.isDefault }
    }
}

private struct EditorSettings: View {
    @AppStorage(SettingsKey.editorFontName) private var fontName = ""
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.syntaxHighlighting) private var syntaxHighlighting = true
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = false
    @AppStorage(SettingsKey.highlightCurrentLine) private var highlightCurrentLine = true
    @AppStorage(SettingsKey.typewriterScrolling) private var typewriterScrolling = false
    @AppStorage(SettingsKey.focusMode) private var focusMode = false
    @AppStorage(SettingsKey.autoPairing) private var autoPairing = true
    @AppStorage(SettingsKey.smartLists) private var smartLists = true
    @AppStorage(SettingsKey.spellCheck) private var spellCheck = true

    private static let monospacedFamilies: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch || manager.traits(of: font).contains(.fixedPitchFontMask)
        }
    }()

    private static let otherFamilies: [String] = {
        let monospaced = Set(monospacedFamilies)
        return NSFontManager.shared.availableFontFamilies.filter { !monospaced.contains($0) && !$0.hasPrefix(".") }
    }()

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font", selection: $fontName) {
                    Text("System Monospaced (SF Mono)").tag("")
                    Divider()
                    ForEach(Self.monospacedFamilies, id: \.self) { Text($0).tag($0) }
                    Divider()
                    ForEach(Self.otherFamilies, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $fontSize, in: 9...36, step: 1) {
                    LabeledContent("Size", value: "\(Int(fontSize)) pt")
                }
            }
            Section("Display") {
                Toggle("Syntax highlighting", isOn: $syntaxHighlighting)
                Toggle("Line numbers", isOn: $showLineNumbers)
                Toggle("Highlight current line", isOn: $highlightCurrentLine)
                Toggle("Typewriter scrolling", isOn: $typewriterScrolling)
                Toggle("Focus mode (dim other paragraphs)", isOn: $focusMode)
            }
            Section("Typing") {
                Toggle("Continue lists and quotes on Return", isOn: $smartLists)
                Toggle("Auto-pair brackets and backticks", isOn: $autoPairing)
                Toggle("Check spelling while typing", isOn: $spellCheck)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PreviewSettings: View {
    @AppStorage(SettingsKey.previewTheme) private var theme = PreviewTheme.github
    @AppStorage(SettingsKey.customCSS) private var customCSS = ""
    @AppStorage(SettingsKey.renderMath) private var renderMath = true
    @AppStorage(SettingsKey.renderMermaid) private var renderMermaid = true
    @AppStorage(SettingsKey.frontMatterStyle) private var frontMatter = FrontMatterStyle.table

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(PreviewTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("YAML front matter", selection: $frontMatter) {
                    ForEach(FrontMatterStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Extras") {
                Toggle("Render math ($…$ and $$…$$) with KaTeX", isOn: $renderMath)
                Toggle("Render ```mermaid diagrams", isOn: $renderMermaid)
            }
            Section {
                TextEditor(text: $customCSS)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Custom CSS")
            } footer: {
                Text("Applied after the theme, e.g. `.markdown-body { font-size: 18px; }`")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("Markdown Studio").font(.title2.bold())
                    Text(version).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Section("Developers") {
                LabeledContent("Menno Spijker", value: "Developer")
                LabeledContent("Claude (Anthropic)", value: "AI pair programmer")
            }
            Section("Disclaimer") {
                Text("""
                Markdown Studio was developed by Menno Spijker together with Claude, an AI model made by \
                Anthropic. Parts of the code were written by AI and reviewed by a human developer.

                The app is provided “as is”, without warranty of any kind. Keep backups of important \
                documents. Markdown syntax follows markdownguide.org; this app is not affiliated with \
                or endorsed by Markdown Guide or Anthropic.
                """)
                .fixedSize(horizontal: false, vertical: true)
                Text("Includes markdown-it, highlight.js, KaTeX, Mermaid and DOMPurify, each under its own open-source license (see Web/vendor in the app bundle).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
