#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The area above the document browser on iPhone and iPad: a soft mesh with
/// a few Markdown snippets floating above the title.
struct LaunchBackground: View {
    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.6, 0.4], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            .launch(0.80, 0.88, 1.00, dark: 0.10, 0.16, 0.32), .launch(0.86, 0.83, 1.00, dark: 0.17, 0.13, 0.33), .launch(0.78, 0.93, 0.97, dark: 0.07, 0.20, 0.27),
            .launch(0.90, 0.92, 1.00, dark: 0.11, 0.13, 0.24), .launch(0.97, 0.97, 1.00, dark: 0.09, 0.10, 0.16), .launch(0.88, 0.86, 1.00, dark: 0.14, 0.11, 0.26),
            .launch(0.96, 0.96, 0.99, dark: 0.07, 0.07, 0.10), .launch(0.95, 0.96, 1.00, dark: 0.07, 0.08, 0.11), .launch(0.94, 0.95, 0.99, dark: 0.07, 0.07, 0.10),
        ])
        .ignoresSafeArea()
    }
}

/// Little cards of Markdown, scattered between the top of the screen and the title.
struct LaunchSnippets: View {
    let geometry: DocumentLaunchGeometryProxy

    private struct Snippet: Identifiable {
        let id: Int
        let syntax: String
        let text: String
        /// Position as a fraction of the band above the title.
        let x: CGFloat
        let y: CGFloat
        let angle: Double
    }

    private let snippets = [
        Snippet(id: 0, syntax: "# ", text: "Ideas", x: 0.24, y: 0.12, angle: -7),
        Snippet(id: 1, syntax: "**", text: "bold move**", x: 0.74, y: 0.05, angle: 5),
        Snippet(id: 2, syntax: "- [x] ", text: "Ship it", x: 0.55, y: 0.42, angle: -3),
        Snippet(id: 3, syntax: "> ", text: "Stay curious", x: 0.22, y: 0.78, angle: 4),
        Snippet(id: 4, syntax: "`", text: "code`", x: 0.80, y: 0.80, angle: -6),
    ]

    var body: some View {
        // The band starts below the status bar and ends just above the title,
        // which sits lower on taller screens. On iPad the cards stay about as
        // wide as the title instead of spreading across the screen.
        let top = geometry.titleViewFrame.minY + 22
        let band = geometry.frame.height * 0.09
        let span = min(geometry.frame.width, 600)
        ZStack {
            ForEach(snippets) { snippet in
                card(snippet)
                    .rotationEffect(.degrees(snippet.angle))
                    .position(x: geometry.frame.midX + span * (snippet.x - 0.5),
                              y: top + band * snippet.y)
            }
        }
        .frame(width: geometry.frame.width, height: geometry.frame.height)
        .accessibilityHidden(true)
    }

    private func card(_ snippet: Snippet) -> some View {
        (Text(snippet.syntax).foregroundStyle(Color.launchSyntax) + Text(snippet.text).foregroundStyle(.primary))
            .font(.system(.subheadline, design: .monospaced).weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

private extension Color {
    /// The arrow in the app icon.
    static let launchSyntax = Color(red: 0.18, green: 0.55, blue: 0.95)

    static func launch(_ r: Double, _ g: Double, _ b: Double, dark dr: Double, _ dg: Double, _ db: Double) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: 1)
                : UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

/// The launch screen as a plain view, so the preview shows the real document browser.
private struct LaunchScreenPreview: View {
    var body: some View {
        DocumentLaunchView("Markdown Studio", for: [.markdownDocument]) {
            NewDocumentButton("New Document")
        } onDocumentOpen: { url in
            Text(url.lastPathComponent)
        } background: {
            LaunchBackground()
        } overlayAccessoryView: { geometry in
            LaunchSnippets(geometry: geometry)
        }
    }
}

#Preview("Light") { LaunchScreenPreview() }
#Preview("Dark") { LaunchScreenPreview().preferredColorScheme(.dark) }
#endif
