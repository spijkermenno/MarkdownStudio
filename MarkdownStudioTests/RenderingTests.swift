import Foundation
import JavaScriptCore
import Testing
@testable import Markdown_Studio

/// Runs the preview's render pipeline (markdown-it + plugins + render.js) in
/// JavaScriptCore and checks every markdownguide.org element.
struct RenderingTests {
    private static func makeRenderer(_ options: String = "{}") throws -> JSValue {
        let context = try #require(JSContext())
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let web = PreviewSchemeHandler.webRoot
        for file in ["vendor/markdown-it.min.js", "vendor/markdown-it-footnote.min.js", "vendor/markdown-it-deflist.min.js",
                     "vendor/markdown-it-mark.min.js", "vendor/markdown-it-sub.min.js", "vendor/markdown-it-sup.min.js",
                     "vendor/markdown-it-emoji.min.js", "vendor/highlight/highlight.min.js", "render.js"] {
            let source = try String(contentsOf: web.appending(path: file), encoding: .utf8)
            context.evaluateScript(source, withSourceURL: URL(string: file))
            #expect(exception == nil, "\(file): \(exception ?? "")")
        }
        return try #require(context.evaluateScript("MDStudio.createRenderer(\(options))"))
    }

    private static func render(_ markdown: String, options: String = "{}") throws -> String {
        let renderer = try makeRenderer(options)
        return try #require(renderer.invokeMethod("render", withArguments: [markdown])?.forProperty("html")?.toString())
    }

    @Test(arguments: [
        ("# H1\n## H2\n###### H6", ["<h1 id=\"h1\"", "<h2 id=\"h2\"", "<h6 id=\"h6\""]),
        ("Alt H1\n======\n\nAlt H2\n------", ["<h1 id=\"alt-h1\"", "<h2 id=\"alt-h2\""]),
        ("line one  \nline two", ["line one<br>"]),
        ("**bold** __bold__ *it* _it_ ***both***", ["<strong>bold</strong>", "<em>it</em>", "<em><strong>both</strong></em>"]),
        ("> quote\n>\n>> nested", ["<blockquote", "<blockquote"]),
        ("1. one\n2. two\n    1. nested", ["<ol", "<li"]),
        ("- a\n* b\n+ c", ["<ul"]),
        ("``Use `code` here``", ["<code>Use `code` here</code>"]),
        ("    indented code", ["<pre", "<code>indented code"]),
        ("***\n\n---\n\n___", ["<hr"]),
        ("[Duck](https://duckduckgo.com \"title\")", ["<a href=\"https://duckduckgo.com\" title=\"title\">Duck</a>"]),
        ("<https://example.com> <fake@example.com>", ["href=\"https://example.com\"", "href=\"mailto:fake@example.com\""]),
        ("[hobbit][1]\n\n[1]: https://example.com \"T\"", ["<a href=\"https://example.com\" title=\"T\">hobbit</a>"]),
        ("![alt](img.png \"t\")", ["<img src=\"img.png\" alt=\"alt\" title=\"t\">"]),
        ("\\* not a list", ["<p data-line=\"0\" data-line-end=\"1\">* not a list</p>"]),
        ("<kbd>K</kbd>", ["<kbd>K</kbd>"]),
        ("| a | b |\n| :- | -: |\n| 1 | 2 |", ["<table", "style=\"text-align:left\"", "style=\"text-align:right\""]),
        ("```json\n{\"a\": 1}\n```", ["class=\"hljs language-json\"", "hljs-attr"]),
        ("Text[^1]\n\n[^1]: Note", ["footnote-ref", "class=\"footnotes\""]),
        ("### Heading {#custom-id}", ["<h3 id=\"custom-id\"", ">Heading</h3>"]),
        ("Term\n: Definition", ["<dl", "<dt", "<dd"]),
        ("~~flat~~", ["<s>flat</s>"]),
        ("- [x] done\n- [ ] todo", ["contains-task-list", "data-task-line=\"0\" checked", "data-task-line=\"1\">"]),
        (":tent: :joy:", ["⛺", "😂"]),
        ("==important==", ["<mark>important</mark>"]),
        ("H~2~O X^2^", ["H<sub>2</sub>O", "X<sup>2</sup>"]),
        ("https://www.markdownguide.org", ["<a href=\"https://www.markdownguide.org\">"]),
        ("`https://www.example.com`", ["<code>https://www.example.com</code>"]),
        ("Inline $x^2$ and\n\n$$\n\\int x\n$$", ["math math-inline", "math math-block"]),
        ("$5 and $10", ["$5 and $10"]),
        ("```mermaid\ngraph LR; A-->B\n```", ["<pre class=\"mermaid\">"]),
    ] as [(String, [String])])
    func rendersMarkdownGuideSyntax(markdown: String, expected: [String]) throws {
        let html = try Self.render(markdown)
        for fragment in expected {
            #expect(html.contains(fragment), "Missing \(fragment) in \(html)")
        }
    }

    @Test func frontMatterIsRenderedAsTableAndLinesAreOffset() throws {
        let html = try Self.render("---\ntitle: Hello\n---\n# Heading")
        #expect(html.contains("<table class=\"front-matter\""))
        #expect(html.contains("<th>title</th><td>Hello</td>"))
        #expect(html.contains("<h1 id=\"heading\" data-line=\"3\""))
        #expect(try !Self.render("---\ntitle: Hello\n---\nx", options: "{frontMatter: 'hide'}").contains("front-matter"))
    }

    @Test func extrasCanBeDisabled() throws {
        let html = try Self.render("$x$\n\n```mermaid\nA\n```", options: "{math: false, mermaid: false}")
        #expect(!html.contains("math-inline"))
        #expect(!html.contains("class=\"mermaid\""))
    }

    @Test func duplicateHeadingsGetUniqueIds() throws {
        let html = try Self.render("# Intro\n# Intro")
        #expect(html.contains("id=\"intro\""))
        #expect(html.contains("id=\"intro-1\""))
    }

    @Test func showcaseRenders() throws {
        let html = try Self.render(Showcase.text)
        #expect(html.contains("<h1 id=\"markdown-studio-showcase\""))
        #expect(html.contains("id=\"custom-id\""))
    }
}
