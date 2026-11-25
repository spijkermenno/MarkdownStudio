import AppKit
import Foundation
import Testing
@testable import Markdown_Studio

/// Regression tests for the bug-hunt findings in the original code.
@MainActor
struct BugHuntFixTests {
    @Test func parentFolderPathsResolveCorrectly() throws {
        let handler = PreviewSchemeHandler()
        handler.documentDirectory = URL(filePath: "/Users/me/notes/drafts/", directoryHint: .isDirectory)
        // What preview.js sends for ![](../img/my pic.png) and [x](../../guide.md#setup)
        let image = try #require(URL(string: "mdstudio://doc/?p=..%2Fimg%2Fmy%2520pic.png"))
        #expect(handler.resolve(image)?.path == "/Users/me/notes/img/my pic.png")
        let link = try #require(URL(string: "mdstudio://doc/?p=..%2F..%2Fguide.md%23setup"))
        #expect(handler.fileURL(for: link)?.path == "/Users/me/guide.md")
        #expect(PreviewSchemeHandler.fragment(in: link) == "setup")
    }

    @Test func workspaceContainsFilesThroughSymlinks() throws {
        let fm = FileManager.default
        let real = fm.temporaryDirectory.appendingPathComponent("ws-real-\(UUID().uuidString)")
        let link = fm.temporaryDirectory.appendingPathComponent("ws-link-\(UUID().uuidString)")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? fm.removeItem(at: link); try? fm.removeItem(at: real) }

        #expect(Workspace.isPath(real.appendingPathComponent("note.md"), inside: link))
        #expect(Workspace.isPath(link.appendingPathComponent("note.md"), inside: real))
        #expect(!Workspace.isPath(fm.temporaryDirectory.appendingPathComponent("other.md"), inside: link))
    }

    @Test func reclosingACodeFenceRestoresHighlighting() {
        let highlighter = MarkdownHighlighter()
        highlighter.configure(EditorConfiguration())
        let storage = NSTextStorage(string: "```\ncode\n\nAfter the block")
        highlighter.highlightAll(storage)            // unclosed fence: everything after is code
        let insert = NSRange(location: 8, length: 0)
        storage.replaceCharacters(in: insert, with: "\n```")
        highlighter.highlightEdit(storage, editedRange: NSRange(location: 8, length: 4))
        let afterIndex = (storage.string as NSString).range(of: "After").location
        let color = storage.attribute(.foregroundColor, at: afterIndex, effectiveRange: nil) as? NSColor
        #expect(color != MarkdownHighlighter.Colors.code)
    }

    @Test(arguments: [false, true])
    func editorScrollSyncRoundTrips(typewriter: Bool) {
        let text = (1...200).map { "Line \($0) with some words to fill it" }.joined(separator: "\n")
        let editor = EditorController(text: text)
        editor.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        var configuration = EditorConfiguration()
        configuration.typewriterScrolling = typewriter
        editor.configure(configuration)
        editor.textView.layoutManager?.ensureLayout(for: editor.textView.textContainer!)
        for target in [10.0, 57.5, 120.25] {
            editor.scroll(toLine: target, atBottom: false)
            #expect(abs(editor.topVisibleLine() - target) < 0.05, "typewriter: \(typewriter), line \(target)")
        }
    }
}
