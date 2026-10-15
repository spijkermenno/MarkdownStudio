import SwiftUI

/// The first-run setup window. Every choice is applied immediately; the last
/// step opens a sample document and starts the guided tour.
struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.newDocument) private var newDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Int
    private let initialStep: Int

    init(initialStep: Int = 0) {
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
    }

    private enum Step: Int, CaseIterable {
        case welcome, appearance, layout, theme, editor, files, tour
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch Step(rawValue: step) ?? .welcome {
                case .welcome: WelcomeStep()
                case .appearance: AppearanceStep()
                case .layout: LayoutStep()
                case .theme: ThemeStep()
                case .editor: EditorStep()
                case .files: FilesStep()
                case .tour: TourIntroStep(start: startTour)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                              removal: .opacity))

            Divider()
            HStack {
                Button("Skip for Now") { skip() }
                    .buttonStyle(.link)
                    .help("Close the setup. It opens again at the next launch until you finish the tour.")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.rawValue) { s in
                        Capsule()
                            .fill(s.rawValue == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: s.rawValue == step ? 16 : 6, height: 6)
                    }
                }
                .accessibilityLabel("Step \(step + 1) of \(Step.allCases.count)")
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation(.unlessReduceMotion(.easeOut(duration: 0.2))) { step -= 1 } }
                }
                if step < Step.allCases.count - 1 {
                    Button(step == 0 ? "Get Started" : "Continue") {
                        withAnimation(.unlessReduceMotion(.easeOut(duration: 0.2))) { step += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start the Tour", action: startTour)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 660, height: 540)
        .onAppear { step = initialStep }
    }

    private func startTour() {
        let document = MarkdownDocument(text: Onboarding.tourText)
        document.isTour = true
        dismissWindow(id: Onboarding.windowID)
        dismissWindow(id: WelcomeWindow.id)
        newDocument { document }
    }

    private func skip() {
        dismissWindow(id: Onboarding.windowID)
        if NSDocumentController.shared.documents.isEmpty { openWindow(id: WelcomeWindow.id) }
    }
}

// MARK: - Steps

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A selectable card used by the choice steps.
private struct ChoiceTile<Preview: View>: View {
    let title: String
    /// What the preview shows, for VoiceOver (which skips the drawing itself).
    var description: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(title).fontWeight(isSelected ? .semibold : .regular)
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(cornerRadius: 12, filled: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(description ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            // The artwork fills the whole image (no margin like the system icon), so it's drawn a bit smaller.
            Image(.appIcon)
                .resizable()
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            Text("Welcome to Markdown Studio").font(.largeTitle.bold())
            Text("Let's set up a few things and then take a short tour. It takes about a minute, and you can change everything later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            VStack(alignment: .leading, spacing: 12) {
                feature("rectangle.split.2x1", "Write and preview side by side", "Everything from markdownguide.org, plus math and diagrams.")
                feature("arrow.triangle.2.circlepath", "Your files stay in sync", "Saves automatically and reloads changes made in other apps.")
                feature("folder", "Work with whole folders", "Browse, search and jump between all your notes.")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppearanceStep: View {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system

    var body: some View {
        VStack(spacing: 28) {
            StepHeader(title: "Choose an appearance",
                       subtitle: "This applies to the editor, the preview and every window. System follows your Mac's setting.")
            HStack(spacing: 14) {
                ForEach(AppearanceMode.allCases) { mode in
                    ChoiceTile(title: mode.title, isSelected: appearance == mode, action: { appearance = mode }) {
                        switch mode {
                        case .light: WindowSketch(dark: false)
                        case .dark: WindowSketch(dark: true)
                        case .system:
                            HStack(spacing: 0) {
                                WindowSketch(dark: false)
                                WindowSketch(dark: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A tiny drawing of an editor window, used to preview appearances and layouts.
private struct WindowSketch: View {
    var dark: Bool
    var mode: ViewMode = .split
    var vertical = false

    var body: some View {
        let background = dark ? Color(white: 0.14) : Color.white
        let line = dark ? Color.white.opacity(0.25) : Color.black.opacity(0.15)
        let heading = dark ? Color.white.opacity(0.7) : Color.black.opacity(0.55)
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 5, height: 5) }
                Spacer()
            }
            .padding(6)
            .background(dark ? Color(white: 0.2) : Color(white: 0.94))
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                if mode != .preview {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.orange.opacity(0.8)).frame(width: 18, height: 4)
                        ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 1).fill(line).frame(width: CGFloat(34 - i * 5), height: 3) }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if mode == .split {
                    Rectangle().fill(line).frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
                }
                if mode != .editor {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(heading).frame(width: 30, height: 6)
                        ForEach(0..<3, id: \.self) { i in RoundedRectangle(cornerRadius: 1).fill(line).frame(width: CGFloat(40 - i * 6), height: 3) }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(background)
    }
}

private struct LayoutStep: View {
    @AppStorage(SettingsKey.defaultViewMode) private var viewMode = ViewMode.split
    @AppStorage(SettingsKey.defaultSplitOrientation) private var orientation = SplitOrientation.horizontal

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "How should new windows open?",
                       subtitle: "You can always switch with ⌘1, ⌘2 and ⌘3. This only sets where new windows start.")
            HStack(spacing: 14) {
                ForEach(ViewMode.allCases) { mode in
                    ChoiceTile(title: mode.title, isSelected: viewMode == mode, action: { viewMode = mode }) {
                        WindowSketch(dark: false, mode: mode, vertical: mode == .split && orientation == .vertical)
                    }
                }
            }
            Picker("Split layout", selection: $orientation) {
                ForEach(SplitOrientation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .disabled(viewMode != .split)
        }
    }
}

private struct ThemeStep: View {
    @AppStorage(SettingsKey.previewTheme) private var theme = PreviewTheme.github

    var body: some View {
        VStack(spacing: 28) {
            StepHeader(title: "Pick a preview style",
                       subtitle: "How the rendered document looks in the preview and in exported HTML and PDF.")
            HStack(spacing: 14) {
                ForEach(PreviewTheme.allCases) { option in
                    ChoiceTile(title: option.title, description: option.sampleDescription,
                               isSelected: theme == option, action: { theme = option }) {
                        ThemeSample(theme: option)
                    }
                }
            }
        }
    }
}

private struct ThemeSample: View {
    let theme: PreviewTheme

    var body: some View {
        VStack(alignment: theme == .academic ? .center : .leading, spacing: 6) {
            switch theme {
            case .github:
                Text("Release notes").font(.system(size: 15, weight: .semibold))
                Divider()
                Text("Adds **sync** and [offline mode]().").font(.system(size: 10))
                Text("let x = 1").font(.system(size: 9, design: .monospaced))
                    .padding(4).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            case .academic:
                Text("Release Notes").font(.system(size: 15, design: .serif))
                Text("Adds *sync* and offline mode to every edition of the app.")
                    .font(.system(size: 10, design: .serif))
                    .multilineTextAlignment(.center)
                Text("⁂").font(.system(size: 10, design: .serif)).foregroundStyle(.secondary)
            case .minimal:
                Text("Release notes").font(.system(size: 16, weight: .bold))
                Text("Adds sync and offline mode.").font(.system(size: 10, weight: .light))
                HStack(spacing: 6) {
                    Rectangle().fill(Color.accentColor).frame(width: 2)
                    Text("Quiet and airy.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(height: 14)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct EditorStep: View {
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = false
    @AppStorage(SettingsKey.smartLists) private var smartLists = true
    @AppStorage(SettingsKey.autoPairing) private var autoPairing = true
    @AppStorage(SettingsKey.spellCheck) private var spellCheck = true
    @AppStorage(SettingsKey.autocomplete) private var autocomplete = true

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "Set up the editor", subtitle: "A comfortable text size and the typing helpers you like.")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        if showLineNumbers {
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(1...4, id: \.self) { Text("\($0)") }
                            }
                            .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("# Shopping list").bold()
                            Text("- Coffee")
                            Text("- **Fresh** bread")
                            Text("- [ ] Call home")
                        }
                    }
                    .font(.system(size: fontSize, design: .monospaced))
                    .lineLimit(1)
                }
                .padding(14)
                .frame(width: 260, height: 150, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .clipped()
                // One short description instead of reading the sample list line by line.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sample text at \(Int(fontSize)) points\(showLineNumbers ? ", with line numbers" : "")")

                Form {
                    LabeledContent("Text size") {
                        HStack {
                            Slider(value: $fontSize, in: 11...22, step: 1).frame(width: 120)
                            Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                    Toggle("Line numbers", isOn: $showLineNumbers)
                    Toggle("Continue lists on Return", isOn: $smartLists)
                    Toggle("Auto-pair brackets and backticks", isOn: $autoPairing)
                    Toggle("Suggestions while typing", isOn: $autocomplete)
                    Toggle("Check spelling", isOn: $spellCheck)
                }
                .formStyle(.columns)
            }
        }
    }
}

private struct FilesStep: View {
    @State private var isDefault = DefaultAppHandler.isDefault
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Open .md files with Markdown Studio",
                       subtitle: "Make Markdown Studio the app that opens when you double-click a Markdown file in Finder. You can also do this later in Settings → General.")
            VStack(spacing: 14) {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "doc.text.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(isDefault ? Color.green : Color.accentColor)
                if isDefault {
                    Text("Markdown files open in Markdown Studio.").font(.headline)
                } else {
                    if let current = DefaultAppHandler.currentDefaultName {
                        Text("They currently open in \(current).").foregroundStyle(.secondary)
                    }
                    Button("Make Markdown Studio the Default") {
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
                    .controlSize(.large)
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Text("Optional. Continue to skip this.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
        .onAppear { isDefault = DefaultAppHandler.isDefault }
    }
}

private struct TourIntroStep: View {
    let start: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "Ready for a quick tour?",
                       subtitle: "A sample document opens and a small card walks you through the editor, the preview, the sidebar and more, one step at a time.")
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 20)
            Text("The setup is finished once you complete the tour. You can restart both at any time in Settings → General.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}

private extension PreviewTheme {
    /// Read by VoiceOver in place of the drawn sample.
    var sampleDescription: String {
        switch self {
        case .github: "Sans-serif text with ruled headings and shaded code"
        case .academic: "Serif text with centered titles, like a paper"
        case .minimal: "Light, airy text with plenty of space"
        }
    }
}
