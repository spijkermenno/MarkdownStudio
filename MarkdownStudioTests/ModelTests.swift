import Foundation
import Testing
@testable import Markdown_Studio

struct TableFormatterTests {
    @Test func alignsColumnsAndKeepsAlignment() throws {
        let text = """
        before

        |a|b|c|
        |:-|:-:|-:|
        |long cell|x|1|

        after
        """
        let edit = try #require(TableFormatter.formatTable(text, at: (text as NSString).range(of: "x").location))
        #expect(edit.replacement == """
        | a         |  b  |   c |
        | :-------- | :-: | --: |
        | long cell |  x  |   1 |
        """)
        #expect(edit.applied(to: text).hasPrefix("before\n\n| a "))
        #expect(edit.applied(to: text).hasSuffix("|\n\nafter"))
    }

    @Test func keepsEscapedPipesAndCodeSpans() {
        #expect(TableFormatter.splitRow("| a \\| b | `x|y` |") == ["a \\| b", "`x|y`"])
    }

    @Test func requiresDelimiterRow() {
        #expect(TableFormatter.formatTable("a | b\nc | d", at: 0) == nil)
    }
}

struct OutlineParserTests {
    @Test func findsAtxAndSetextHeadings() {
        let text = """
        # One
        text
        Two
        ===
        Three
        ---
        ### Four ###
        """
        #expect(OutlineParser.parse(text).map(\.title) == ["One", "Two", "Three", "Four"])
        #expect(OutlineParser.parse(text).map(\.level) == [1, 1, 2, 3])
        #expect(OutlineParser.parse(text).map(\.line) == [0, 2, 4, 6])
    }

    @Test func skipsCodeBlocksAndFrontMatter() {
        let text = """
        ---
        title: x
        ---
        ```
        # not a heading
        ```
        ## Real
        """
        #expect(OutlineParser.parse(text).map(\.title) == ["Real"])
    }

    @Test func cleansInlineMarkdown() {
        #expect(OutlineParser.clean("**Bold** and `code` with [link](x) {#id}") == "Bold and code with link")
    }

    @Test func listItemsFollowedByDashesAreNotSetext() {
        #expect(OutlineParser.parse("- item\n---").isEmpty)
    }
}

struct LineIndexTests {
    @Test func mapsOffsetsToLines() {
        let index = LineIndex("ab\ncd\n\nef")
        #expect(index.lineCount == 4)
        #expect(index.line(containing: 0) == 0)
        #expect(index.line(containing: 3) == 1)
        #expect(index.line(containing: 6) == 2)
        #expect(index.line(containing: 8) == 3)
        #expect(index.range(ofLine: 1) == NSRange(location: 3, length: 3))
    }
}

struct DocumentStatisticsTests {
    @Test func countsWordsAndReadingTime() {
        let stats = DocumentStatistics("# Hello world\n\nThis is **Markdown**.")
        #expect(stats.words == 5)
        #expect(stats.lines == 3)
        #expect(stats.readingMinutes == 1)
        #expect(DocumentStatistics("").readingMinutes == 0)
    }
}

struct DocumentTests {
    @Test func decodesUTF8WithBOMAndLegacyEncodings() throws {
        #expect(try MarkdownDocument.decode(Data([0xEF, 0xBB, 0xBF]) + Data("# Hi".utf8)) == "# Hi")
        #expect(try MarkdownDocument.decode("café".data(using: .windowsCP1252)!) == "café")
    }

    @Test func relativePaths() {
        let doc = URL(filePath: "/Users/me/notes/")
        #expect(MarkdownPaths.relativePath(to: URL(filePath: "/Users/me/notes/img/a b.png"), from: doc) == "img/a%20b.png")
        #expect(MarkdownPaths.relativePath(to: URL(filePath: "/Users/me/pics/x.png"), from: doc) == "../pics/x.png")
        #expect(MarkdownPaths.relativePath(to: URL(filePath: "/tmp/x.png"), from: nil) == "file:///tmp/x.png")
    }
}
