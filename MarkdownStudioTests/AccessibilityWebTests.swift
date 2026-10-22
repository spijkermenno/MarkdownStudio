import Foundation
import JavaScriptCore
import Testing
@testable import Markdown_Studio

/// Accessibility of the rendered preview: task labels, document language and
/// diagram names (render.js in JavaScriptCore), plus the exported HTML.
struct AccessibilityWebTests {
    private static func makeContext() throws -> JSContext {
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
        return context
    }

    private static func render(_ markdown: String) throws -> JSValue {
        let context = try makeContext()
        let renderer = try #require(context.evaluateScript("MDStudio.createRenderer({})"))
        return try #require(renderer.invokeMethod("render", withArguments: [markdown]))
    }

    @Test func taskCheckboxIsLabelledByItsText() throws {
        let html = try #require(Self.render("- [x] Ship it\n- [ ] Write **notes**").forProperty("html")?.toString())
        #expect(html.contains("<label class=\"task-list-item-label\"><input type=\"checkbox\" class=\"task-list-item-checkbox\" data-task-line=\"0\" checked> Ship it</label>"))
        #expect(html.contains("data-task-line=\"1\"> Write <strong>notes</strong></label>"))
    }

    @Test func nestedTaskListStaysOutsideTheLabel() throws {
        let html = try #require(Self.render("- [ ] Parent\n  - [ ] Child").forProperty("html")?.toString())
        let parentLabel = try #require(html.range(of: "Parent</label>"))
        let childList = try #require(html.range(of: "<ul", range: parentLabel.upperBound..<html.endIndex))
        #expect(html[parentLabel.upperBound..<childList.lowerBound].contains("Child") == false)
    }

    @Test(arguments: [
        ("---\nlang: nl\n---\n# Hallo", "nl"),
        ("---\ntitle: Notes\nlanguage: \"en-GB\"\n---\nText", "en-GB"),
        ("---\nlang: zh_Hant_TW\n---\nText", "zh-Hant-TW"),
    ])
    func languageComesFromFrontMatter(markdown: String, expected: String) throws {
        #expect(try Self.render(markdown).forProperty("lang")?.toString() == expected)
    }

    @Test(arguments: ["# No front matter", "---\nlang: \"><script>\n---\nText", "---\nlang: english language\n---\nText"])
    func invalidOrMissingLanguageIsIgnored(markdown: String) throws {
        #expect(try Self.render(markdown).forProperty("lang")?.isNull == true)
    }

    @Test func diagramLabelUsesAccessibleTitleAndDescription() throws {
        let context = try Self.makeContext()
        func label(_ source: String) -> String? {
            context.objectForKeyedSubscript("MDStudio")?.invokeMethod("diagramLabel", withArguments: [source])?.toString()
        }
        #expect(label("graph LR\nA-->B") == "Diagram")
        #expect(label("graph LR\naccTitle: Login flow\nA-->B") == "Login flow")
        #expect(label("graph LR\naccTitle: Login flow\naccDescr: User signs in\nA-->B") == "Login flow. User signs in")
        #expect(label("graph LR\naccDescr {\n  Two steps,\n  then done\n}\nA-->B") == "Two steps, then done")
    }

    @Test func themeOverridesLowContrastCodeColors() throws {
        let css = try String(contentsOf: PreviewSchemeHandler.webRoot.appending(path: "themes/base.css"), encoding: .utf8)
        #expect(css.contains(".hljs-built_in, .markdown-body .hljs-symbol { color: #b35900; }"))
        #expect(css.contains(".markdown-body .hljs-section { color: #58a6ff; }"))
        #expect(css.contains("prefers-reduced-motion"))
    }
}

/// Exported HTML runs the real preview in a web view.
@MainActor
struct AccessibilityExportTests {
    private func source(_ markdown: String) -> ExportService.Source {
        ExportService.Source(markdown: markdown, title: "Notes", documentURL: nil,
                             configuration: PreviewConfiguration(), window: nil)
    }

    @Test func exportedHTMLUsesFrontMatterLanguage() async {
        let html = await ExportService.standaloneHTML(source("---\nlang: nl\n---\n- [ ] Boodschappen"))
        #expect(html.contains("<html lang=\"nl\">"))
        #expect(html.contains("<label class=\"task-list-item-label\">"))
    }

    @Test func exportedHTMLFallsBackToPreferredLanguage() async {
        let html = await ExportService.standaloneHTML(source("# Plain"))
        let expected = MDLanguage.preferred
        #expect(html.contains("<html lang=\"\(expected)\">"))
    }
}

/// The tag the preview uses when the document doesn't name a language.
private enum MDLanguage {
    static var preferred: String {
        let tag = PreviewController.defaultLanguage.replacingOccurrences(of: "_", with: "-")
        return tag.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil ? tag : "en"
    }
}
