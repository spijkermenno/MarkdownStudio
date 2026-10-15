import AppKit
import Foundation
import Testing
@testable import Markdown_Studio

/// Regression tests for the accessibility sweep's app-side findings.
@MainActor
struct AccessibilityTests {
    /// WCAG contrast ratio between two colors resolved in `appearance`.
    private func contrast(_ foreground: NSColor, on background: NSColor, in appearance: NSAppearance) -> Double {
        var result = 0.0
        appearance.performAsCurrentDrawingAppearance {
            func luminance(_ color: NSColor) -> Double {
                let c = color.usingColorSpace(.sRGB)!
                func channel(_ v: CGFloat) -> Double {
                    let v = Double(v)
                    return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                }
                return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
            }
            // Composite the foreground over the background in case it has alpha.
            let bg = background.usingColorSpace(.sRGB)!
            let fg = foreground.usingColorSpace(.sRGB)!
            let a = fg.alphaComponent
            let blended = NSColor(srgbRed: fg.redComponent * a + bg.redComponent * (1 - a),
                                  green: fg.greenComponent * a + bg.greenComponent * (1 - a),
                                  blue: fg.blueComponent * a + bg.blueComponent * (1 - a), alpha: 1)
            let l1 = luminance(blended), l2 = luminance(bg)
            result = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        return result
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
    func editorColorsMeetContrastMinimum(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        typealias C = MarkdownHighlighter.Colors
        let colors: [(String, NSColor)] = [("syntax", C.syntax), ("secondary", C.secondary), ("code", C.code),
                                           ("listMarker", C.listMarker), ("html", C.html), ("math", C.math),
                                           ("lineNumber", C.lineNumber)]
        for (label, color) in colors {
            let ratio = contrast(color, on: .textBackgroundColor, in: appearance)
            #expect(ratio >= 4.5, "\(label) is \(ratio):1 in \(name.rawValue)")
        }
        // Code also sits on its own shaded background.
        var codeBackground = NSColor.textBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            codeBackground = NSColor.textBackgroundColor.usingColorSpace(.sRGB)!
                .blended(withFraction: C.codeBackground.usingColorSpace(.sRGB)!.alphaComponent,
                         of: C.codeBackground.withAlphaComponent(1).usingColorSpace(.sRGB)!)!
        }
        #expect(contrast(C.code, on: codeBackground, in: appearance) >= 4.5)
    }

    @Test func increaseContrastUsesStrongerColors() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        func color(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        for (label, swatch) in MarkdownHighlighter.Colors.Swatch.all {
            for isDark in [false, true] {
                let appearance = isDark ? dark : light
                let normal = contrast(color(swatch.value(dark: isDark, highContrast: false)), on: .textBackgroundColor, in: appearance)
                let high = contrast(color(swatch.value(dark: isDark, highContrast: true)), on: .textBackgroundColor, in: appearance)
                #expect(normal >= 4.5, "\(label) \(isDark ? "dark" : "light")")
                #expect(high >= 7, "\(label) \(isDark ? "dark" : "light") with Increase Contrast is \(high):1")
                #expect(high > normal)
            }
        }
    }

    @Test func suggestionAnnouncementNamesCountAndChoice() {
        #expect(AccessibilitySupport.suggestionAnnouncement(count: 4, selected: 0, title: "tada", includeCount: true)
                == "4 suggestions. tada, 1 of 4. Press Tab to insert.")
        #expect(AccessibilitySupport.suggestionAnnouncement(count: 1, selected: 0, title: "notes.md", includeCount: true)
                == "1 suggestion. notes.md, 1 of 1. Press Tab to insert.")
        #expect(AccessibilitySupport.suggestionAnnouncement(count: 4, selected: 2, title: "smile", includeCount: false)
                == "smile, 3 of 4")
    }

    @Test func problemCounterHasSpokenSummary() {
        #expect(StatusBarView.problemSummary(warnings: 3, notes: 0) == "3 warnings, 0 notes")
        #expect(StatusBarView.problemSummary(warnings: 1, notes: 1) == "1 warning, 1 note")
    }

    @Test func tourStepsAreAnnounced() {
        let first = TourCard.announcement(for: 0)
        #expect(first.hasPrefix("Tour, step 1 of \(TourStep.all.count). Let's take a quick tour."))
        let last = TourCard.announcement(for: TourStep.all.count - 1)
        #expect(last.contains("step \(TourStep.all.count) of \(TourStep.all.count)"))
    }

    @Test func moveToOffersOtherFoldersOnly() {
        let root = URL(filePath: "/notes", directoryHint: .isDirectory)
        let drafts = root.appendingPathComponent("drafts", isDirectory: true)
        let old = drafts.appendingPathComponent("old", isDirectory: true)
        let ideas = root.appendingPathComponent("ideas", isDirectory: true)
        let tree = [
            FileNode(url: drafts, name: "drafts", isDirectory: true, children: [
                FileNode(url: old, name: "old", isDirectory: true, children: []),
                FileNode(url: drafts.appendingPathComponent("a.md"), name: "a.md", isDirectory: false),
            ]),
            FileNode(url: ideas, name: "ideas", isDirectory: true, children: []),
            FileNode(url: root.appendingPathComponent("readme.md"), name: "readme.md", isDirectory: false),
        ]
        // A file in drafts: anywhere except drafts itself.
        let fileTargets = Workspace.moveTargets(for: drafts.appendingPathComponent("a.md"), root: root, tree: tree)
        #expect(fileTargets.map(\.lastPathComponent) == ["notes", "old", "ideas"])
        // The drafts folder: not into itself or its subfolder, and not where it already is.
        let folderTargets = Workspace.moveTargets(for: drafts, root: root, tree: tree)
        #expect(folderTargets.map(\.lastPathComponent) == ["ideas"])
    }

    @Test func autocompleteScalesWithEditorFont() {
        let controller = AutocompleteController(textView: MarkdownTextView())
        controller.fontSize = 28
        #expect(controller.fontSize == 28)
        controller.fontSize = 8
        #expect(controller.fontSize == 12)
    }
}
