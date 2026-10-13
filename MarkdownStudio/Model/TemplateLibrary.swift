import AppKit
import Foundation

/// Built-in and user templates for new documents. Placeholders such as
/// `{{date}}` are filled in when a document is created.
nonisolated struct DocumentTemplate: Identifiable, Hashable, Sendable {
    var name: String
    var text: String
    var isBuiltIn: Bool
    var id: String { (isBuiltIn ? "builtin:" : "user:") + name }

    /// The template with `{{date}}`, `{{time}}`, `{{year}}` and `{{weekday}}` filled in.
    func filled(now: Date = Date()) -> String {
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter.string(from: now)
        }
        let values = [
            "date": format("yyyy-MM-dd"),
            "time": format("HH:mm"),
            "year": format("yyyy"),
            "weekday": format("EEEE"),
            "title": name,
        ]
        var result = text
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        // Start with the table of contents filled in.
        if let edit = TableOfContents.update(result) { result = edit.applied(to: result) }
        return result
    }
}

nonisolated enum TemplateLibrary {
    /// ~/Library/Application Support/Markdown Studio/Templates
    static var userTemplatesFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Markdown Studio/Templates", isDirectory: true)
    }

    static var all: [DocumentTemplate] { builtIn + user }

    static var user: [DocumentTemplate] {
        let folder = userTemplatesFolder
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let text = try? MarkdownDocument.decode(data) else { return nil }
                return DocumentTemplate(name: url.deletingPathExtension().lastPathComponent, text: text, isBuiltIn: false)
            }
    }

    /// Creates the folder (with a short read-me) and shows it in Finder.
    @MainActor
    static func revealUserTemplatesFolder() {
        let folder = userTemplatesFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appendingPathComponent("Example Template.md")
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty ?? true {
            try? Data("""
            # {{title}}

            Created on {{weekday}} {{date}} at {{time}}.

            Every .md file in this folder appears under File → New from Template.
            Placeholders: {{date}}, {{time}}, {{year}}, {{weekday}}, {{title}}.

            """.utf8).write(to: readme)
        }
        NSWorkspace.shared.activateFileViewerSelecting([readme])
    }

    static let builtIn: [DocumentTemplate] = [
        DocumentTemplate(name: "README", text: """
        # Project Name

        One or two sentences about what this project does and who it is for.

        <!-- toc -->
        <!-- /toc -->

        ## Installation

        ```bash
        git clone https://github.com/you/project.git
        cd project
        ```

        ## Usage

        Explain the most common way to use the project.

        ## Contributing

        Pull requests are welcome. Open an issue first to discuss larger changes.

        ## License

        MIT © {{year}}

        """, isBuiltIn: true),
        DocumentTemplate(name: "Meeting Notes", text: """
        ---
        title: Meeting notes
        date: {{date}}
        attendees:
        ---

        # Meeting notes – {{weekday}} {{date}}

        ## Agenda

        1. 
        2. 

        ## Notes

        ## Decisions

        - 

        ## Action items

        - [ ] Owner: task (due date)

        """, isBuiltIn: true),
        DocumentTemplate(name: "Blog Post", text: """
        ---
        title: Post title
        date: {{date}}
        tags: []
        draft: true
        goal: 800
        ---

        # Post title

        Hook the reader in the first paragraph.

        ## The problem

        ## The solution

        ## Wrapping up

        """, isBuiltIn: true),
        DocumentTemplate(name: "Changelog", text: """
        # Changelog

        All notable changes to this project are documented in this file.
        The format follows [Keep a Changelog](https://keepachangelog.com/).

        ## [Unreleased]

        ### Added

        ### Changed

        ### Fixed

        ## [1.0.0] - {{date}}

        ### Added

        - First release.

        """, isBuiltIn: true),
    ]
}
