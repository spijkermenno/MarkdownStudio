import SwiftUI

/// Parts of the window the tour points at.
enum TourTarget {
    case none, viewModes, editor, preview, sidebar, statusBar, shareButtons
}

struct TourStep {
    /// The window currently running the tour, so it can be brought forward instead of started twice.
    static weak var activeSession: DocumentSession?

    var title: String
    var message: String
    var systemImage: String
    var target: TourTarget
    /// Puts the window in the state this step talks about.
    var prepare: (DocumentSession) -> Void = { _ in }

    static let all: [TourStep] = [
        TourStep(title: "Let's take a quick tour",
                 message: "Six short stops show you the essentials. Everything here is a real, working window, so feel free to try things as you go.",
                 systemImage: "sparkles", target: .none,
                 prepare: { $0.viewMode = .split }),
        TourStep(title: "Three ways to view a document",
                 message: "Switch between the editor, editor and preview side by side, or the preview alone. Shortcuts: ⌘1, ⌘2 and ⌘3. ⌘4 flips the split between side by side and top and bottom.",
                 systemImage: "rectangle.split.2x1", target: .viewModes,
                 prepare: { $0.viewMode = .split }),
        TourStep(title: "Write in the editor",
                 message: "Type Markdown here. Lists continue when you press Return, ⌘B and ⌘I add bold and italic, and typing :, ]( or ](# suggests emoji, files and headings. All formatting commands are in the Format menu.",
                 systemImage: "square.and.pencil", target: .editor,
                 prepare: { $0.viewMode = .split }),
        TourStep(title: "See the result live",
                 message: "The preview updates as you type and scrolls along with the editor. ⌘-click anything to jump to its source line, and click a checkbox to tick it in the text.",
                 systemImage: "eye", target: .preview,
                 prepare: { $0.viewMode = .split }),
        TourStep(title: "Find your way around",
                 message: "The sidebar shows the document's outline. Open a folder with ⌥⌘O to browse and search all your notes here, and jump to any file with ⌘P.",
                 systemImage: "sidebar.left", target: .sidebar,
                 prepare: { $0.showSidebar(.outline) }),
        TourStep(title: "Keep an eye on the details",
                 message: "The status bar counts words and reading time. Click the word count to set a writing goal. The warning counter shows broken links and other problems the document check found.",
                 systemImage: "chart.bar", target: .statusBar),
        TourStep(title: "Share your work",
                 message: "Present the document as slides, or export it as HTML or PDF. Copy as HTML and Copy as Rich Text are in the Edit menu.",
                 systemImage: "square.and.arrow.up", target: .shareButtons),
        TourStep(title: "You're all set",
                 message: "That's the tour. You can change any setting in Settings (⌘,), and restart the onboarding and tour there under General at any time.",
                 systemImage: "checkmark.seal", target: .none),
    ]
}

/// The floating card that walks through the tour steps.
struct TourCard: View {
    let session: DocumentSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Moves VoiceOver to the card on every step; keyboard focus stays where it is.
    @AccessibilityFocusState private var isCardFocused: Bool

    var body: some View {
        if let index = session.tourStep {
            let step = TourStep.all[index]
            let isLast = index == TourStep.all.count - 1
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.systemImage)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title).font(.headline)
                        Text(step.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        session.endTour(completed: false)
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("End the tour. It starts again next time until you finish it.")
                    .accessibilityLabel("End tour")
                    .accessibilityHint("The tour starts again next time until you finish it")
                }
                HStack {
                    HStack(spacing: 5) {
                        ForEach(TourStep.all.indices, id: \.self) { i in
                            Circle()
                                .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityLabel("Step \(index + 1) of \(TourStep.all.count)")
                    Spacer()
                    if index > 0 {
                        Button("Back") { session.moveTour(by: -1) }
                    }
                    Button(isLast ? "Finish" : (index == 0 ? "Start" : "Next")) {
                        if isLast { session.endTour(completed: true) } else { session.moveTour(by: 1) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tour, step \(index + 1) of \(TourStep.all.count)")
            .accessibilityFocused($isCardFocused)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            .id(index)
            .onAppear {
                // The card is recreated for every step (`.id`), so this runs on each change.
                AccessibilitySupport.announce(Self.announcement(for: index), highPriority: true)
                isCardFocused = true
            }
        }
    }
}

extension TourCard {
    /// What VoiceOver says when a step appears, e.g. "Tour, step 2 of 8. Three ways to view a document. …".
    static func announcement(for index: Int) -> String {
        let step = TourStep.all[index]
        return "Tour, step \(index + 1) of \(TourStep.all.count). \(step.title). \(step.message)"
    }
}

/// An accent ring around the part of the window the current tour step is about.
/// It pulses three times to draw the eye, then stays still (or never moves with Reduce Motion).
struct TourHighlight: ViewModifier {
    let active: Bool
    var inset: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(inset)
                    .opacity(pulse ? 0.45 : 1)
                    .task {
                        guard !reduceMotion else { return }
                        for _ in 0..<3 {
                            withAnimation(.easeInOut(duration: 0.9)) { pulse = true }
                            try? await Task.sleep(for: .seconds(0.9))
                            withAnimation(.easeInOut(duration: 0.9)) { pulse = false }
                            try? await Task.sleep(for: .seconds(0.9))
                        }
                    }
                    .onDisappear { pulse = false }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func tourHighlight(_ active: Bool, inset: CGFloat = 3) -> some View {
        modifier(TourHighlight(active: active, inset: inset))
    }
}
