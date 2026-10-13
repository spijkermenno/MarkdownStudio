import AppKit
import UniformTypeIdentifiers

/// Registers Markdown Studio as the default app for Markdown files.
enum DefaultAppHandler {
    /// The types Finder may assign to .md files (the declared one and whatever
    /// Launch Services resolves the extensions to).
    static var markdownTypes: [UTType] {
        var types: [UTType] = [.markdownDocument]
        for ext in ["md", "markdown"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        return types
    }

    /// True when .md files open in Markdown Studio, including another copy of it
    /// (for example a build run from Xcode next to the one in /Applications).
    static var isDefault: Bool {
        markdownTypes.allSatisfy { type in
            guard let url = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
            return url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
                || Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    static var currentDefaultName: String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: .markdownDocument) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func makeDefault() async throws {
        for type in markdownTypes {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        }
    }
}
