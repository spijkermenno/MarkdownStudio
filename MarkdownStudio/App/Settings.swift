import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case editor, split, preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editor: "Editor"
        case .split: "Split"
        case .preview: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .editor: "square.and.pencil"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }

    var showsEditor: Bool { self != .preview }
    var showsPreview: Bool { self != .editor }
}

enum SplitOrientation: String, CaseIterable, Identifiable {
    case horizontal, vertical
    var id: Self { self }
    var title: String { self == .horizontal ? "Side by Side" : "Top and Bottom" }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the system setting.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum PreviewTheme: String, CaseIterable, Identifiable {
    case github, academic, minimal
    var id: Self { self }
    var title: String {
        switch self {
        case .github: "GitHub"
        case .academic: "Academic"
        case .minimal: "Minimal"
        }
    }
}

enum FrontMatterStyle: String, CaseIterable, Identifiable {
    case table, code, hide
    var id: Self { self }
    var title: String {
        switch self {
        case .table: "Table"
        case .code: "YAML Code Block"
        case .hide: "Hidden"
        }
    }
}

/// UserDefaults keys and defaults, shared by `@AppStorage` and non-view code.
enum SettingsKey {
    static let appearance = "appearance"
    static let editorFontName = "editorFontName"
    static let editorFontSize = "editorFontSize"
    static let showLineNumbers = "showLineNumbers"
    static let highlightCurrentLine = "highlightCurrentLine"
    static let typewriterScrolling = "typewriterScrolling"
    static let focusMode = "focusMode"
    static let autoPairing = "autoPairing"
    static let smartLists = "smartLists"
    static let spellCheck = "spellCheck"
    static let syntaxHighlighting = "syntaxHighlighting"
    static let previewTheme = "previewTheme"
    static let customCSS = "customCSS"
    static let renderMath = "renderMath"
    static let renderMermaid = "renderMermaid"
    static let frontMatterStyle = "frontMatterStyle"
    static let defaultViewMode = "defaultViewMode"
    static let defaultSplitOrientation = "defaultSplitOrientation"
    static let syncScroll = "syncScroll"
    static let showStatusBar = "showStatusBar"
    static let showFormattingBar = "showFormattingBar"
}

/// Editor options passed from SwiftUI settings to the text view.
struct EditorConfiguration: Equatable {
    var fontName = ""
    var fontSize: Double = 14
    var zoom: Double = 1
    var showLineNumbers = false
    var highlightCurrentLine = true
    var typewriterScrolling = false
    var focusMode = false
    var autoPairing = true
    var smartLists = true
    var spellCheck = true
    var syntaxHighlighting = true

    var font: NSFont {
        let size = CGFloat(fontSize * zoom)
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// Preview options passed to the web view.
struct PreviewConfiguration: Equatable {
    var theme: PreviewTheme = .github
    var customCSS = ""
    var math = true
    var mermaid = true
    var frontMatter: FrontMatterStyle = .table

    var javaScriptValue: [String: Any] {
        ["theme": theme.rawValue, "customCSS": customCSS, "math": math, "mermaid": mermaid, "frontMatter": frontMatter.rawValue]
    }
}
