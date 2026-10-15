import Foundation
import PDFKit
import Testing
@testable import Markdown_Studio

struct CompletionTests {
    private func context(_ marked: String) -> (String, CompletionContext?) {
        let ns = marked as NSString
        let caret = ns.range(of: "|").location
        let text = ns.replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
        return (text, CompletionEngine.context(in: text, caret: caret))
    }

    @Test func detectsTriggers() {
        #expect(context("Hello :ta|").1?.kind == .emoji)
        #expect(context("Hello :ta|").1?.query == "ta")
        #expect(context("time 10:30|").1 == nil)                // not after a space
        #expect(context("See [x](#ins|)").1?.kind == .anchor)
        #expect(context("![a](img/da|)").1?.kind == .path(imagesOnly: true, directory: "img/"))
        #expect(context("[a](https://x|)").1 == nil)
        #expect(context("Note[^fo|]").1?.kind == .footnote)
        #expect(context("```\n:smi|\n```").1 == nil)          // inside a code block
    }

    @Test func suggestsEmojiHeadingsAndFootnotes() throws {
        let emoji = [(name: "tada", character: "🎉"), (name: "smile", character: "😄"), (name: "metadata", character: "x")]
        let (text, ctx) = context("Party :tad|")
        let items = CompletionEngine.items(for: try #require(ctx), text: text, documentDirectory: nil, emoji: emoji)
        #expect(items.first?.insertion == ":tada:")

        let (doc, anchorContext) = context("## Installation\n## Usage\n[go](#ins|)")
        let headings = CompletionEngine.items(for: try #require(anchorContext), text: doc, documentDirectory: nil)
        #expect(headings.map(\.insertion) == ["installation"])

        let (notes, footnoteContext) = context("A[^one] B[^two]\n\nC[^t|")
        #expect(CompletionEngine.items(for: try #require(footnoteContext), text: notes, documentDirectory: nil).map(\.insertion) == ["two"])
    }

    @Test func suggestsFilesForImagesOnlyImages() throws {
        let (text, ctx) = context("![x](|)")
        let listing: (URL) -> [(name: String, isDirectory: Bool)] = { _ in
            [("photo.png", false), ("notes.md", false), ("assets", true), (".hidden.png", false)]
        }
        let items = CompletionEngine.items(for: try #require(ctx), text: text, documentDirectory: URL(filePath: "/tmp/"),
                                           listDirectory: listing)
        #expect(Set(items.map(\.insertion)) == ["photo.png", "assets/"])
    }
}

struct FuzzyMatcherTests {
    @Test func ranksFileNamesAndWordStarts() {
        let a = FuzzyMatcher.score("rel pl", in: "projects/release-plan.md", fileName: "release-plan.md")
        let b = FuzzyMatcher.score("rel pl", in: "journal/really-plain.md", fileName: "really-plain.md")
        #expect(a != nil && b != nil)
        #expect(a! > b!)
        #expect(FuzzyMatcher.score("xyz", in: "notes.md", fileName: "notes.md") == nil)
    }
}

struct WorkspaceScanTests {
    @Test func scansMarkdownAndSearches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("notes/deep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try "# Ideas\nShip the release plan".write(to: root.appendingPathComponent("ideas.md"), atomically: true, encoding: .utf8)
        try "Release notes".write(to: root.appendingPathComponent("notes/deep/release.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: root.appendingPathComponent("node_modules/pkg.md"), atomically: true, encoding: .utf8)
        try "image".write(to: root.appendingPathComponent("photo.png"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: root) }

        let (tree, files) = Workspace.scan(root)
        #expect(tree.map(\.name) == ["notes", "ideas.md"])            // folders first, empty and skipped folders hidden
        #expect(files.count == 2)
        let results = Workspace.search("release", in: files)
        #expect(results.count == 2)
        #expect(results.contains { $0.url.lastPathComponent == "ideas.md" && $0.line == 1 })
    }
}

    /// Opening a file as a tab expands the folders above it in the shared tree.
    @Test func findsFoldersToExpandForAFile() {
        let root = URL(filePath: "/tmp/notes", directoryHint: .isDirectory)
        let file = root.appendingPathComponent("a/b/c.md")
        #expect(Workspace.folders(above: file, in: root).map(\.path) == ["/tmp/notes/a/b", "/tmp/notes/a"])
        #expect(Workspace.folders(above: root.appendingPathComponent("top.md"), in: root).isEmpty)
        #expect(Workspace.folders(above: URL(filePath: "/elsewhere/x.md"), in: root).isEmpty)
    }

@MainActor
struct WebViewTests {
    @Test func convertsClipboardHTMLToMarkdown() async throws {
        let preview = PreviewController()
        let html = """
        <meta charset="utf-8"><h2>Release notes</h2><p>The new version adds <b>sync</b> and \
        <a href="https://example.com/offline">offline mode</a>.</p><ul><li>Faster startup</li><li><del>Old</del> bugs</li></ul>
        <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
        <p><span style="font-weight:700">Docs bold</span></p><script>alert(1)</script>
        """
        let markdown = try #require(await preview.markdown(fromHTML: html))
        #expect(markdown.contains("## Release notes"))
        #expect(markdown.contains("**sync**"))
        #expect(markdown.contains("[offline mode](https://example.com/offline)"))
        #expect(markdown.contains("-   Faster startup") || markdown.contains("- Faster startup"))
        #expect(markdown.contains("~~Old~~"))
        #expect(markdown.contains("| A | B |"))
        #expect(markdown.contains("**Docs bold**"))
        #expect(!markdown.contains("alert"))
    }

    @Test func detectsRichHTML() {
        #expect(MarkdownTextView.isRichHTML("<p>Hello <b>you</b></p>"))
        #expect(!MarkdownTextView.isRichHTML("<div><span style='color:red'>let x = 1</span><br></div>"))
    }

    @Test func exportsOnePDFPagePerSlide() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slides-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let markdown = """
        ---
        title: Deck
        ---
        # Talk title

        ---

        ## First point
        Some text <!-- notes: say hello -->

        ---

        ## Second point
        - a
        - b
        """
        let count = await PresentationController.renderPDF(markdown: markdown, to: url, documentURL: nil,
                                                           configuration: PreviewConfiguration(), separator: .automatic,
                                                           hostWindow: nil)
        #expect(count == 3)
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount == 3)
        let page = try #require(pdf.page(at: 0))
        let size = page.bounds(for: .mediaBox).size
        #expect(abs(size.width / size.height - 16.0 / 9.0) < 0.05)
        #expect(pdf.page(at: 1)?.string?.contains("First point") == true)
    }
}
