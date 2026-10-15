#if os(iOS)
import SwiftUI
import UIKit

/// Hosts a session-owned UIKit view. The same view is reused across
/// view-mode changes (so it keeps text, selection, undo and scroll state);
/// whichever container most recently entered a window claims it.
final class ReparentingContainer: UIView {
    let hosted: UIView

    init(hosted: UIView) {
        self.hosted = hosted
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { attach() }
    }

    func attach() {
        guard hosted.superview !== self else { return }
        hosted.removeFromSuperview()
        hosted.frame = bounds
        hosted.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(hosted)
    }
}

struct EditorHost: UIViewRepresentable {
    let controller: EditorController

    func makeUIView(context: Context) -> ReparentingContainer {
        ReparentingContainer(hosted: controller.textView)
    }

    func updateUIView(_ container: ReparentingContainer, context: Context) {
        if container.window != nil { container.attach() }
    }
}

struct PreviewHost: UIViewRepresentable {
    let controller: PreviewController

    func makeUIView(context: Context) -> ReparentingContainer {
        ReparentingContainer(hosted: controller.webView)
    }

    func updateUIView(_ container: ReparentingContainer, context: Context) {
        if container.window != nil { container.attach() }
    }
}

/// Two panes with a divider that can be dragged (or adjusted with VoiceOver).
/// iPadOS has no HSplitView/VSplitView, so this stands in for them.
struct SplitPane<First: View, Second: View>: View {
    var axis: Axis
    var minimum: CGFloat
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @SceneStorage("splitFraction") private var fraction = 0.5
    @GestureState private var dragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let total = axis == .horizontal ? geometry.size.width : geometry.size.height
            let size = firstSize(in: total)
            let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                first
                    .frame(width: axis == .horizontal ? size : nil, height: axis == .vertical ? size : nil)
                divider(total: total)
                second
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func firstSize(in total: CGFloat) -> CGFloat {
        let available = max(0, total - 1)
        guard available > minimum * 2 else { return available / 2 }
        return min(max(available * fraction, minimum), available - minimum)
    }

    private func divider(total: CGFloat) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            // A wider invisible grip than the hairline, for fingers and the pointer.
            .overlay {
                Color.clear
                    .frame(width: axis == .horizontal ? 24 : nil, height: axis == .vertical ? 24 : nil)
                    .contentShape(Rectangle())
                    .hoverEffect(.highlight)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .updating($dragStart) { _, start, _ in
                                if start == nil { start = fraction }
                            }
                            .onChanged { value in
                                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                                let start = dragStart ?? fraction
                                fraction = min(max(start + delta / max(total, 1), 0.1), 0.9)
                            }
                    )
            }
            .zIndex(1)
            .accessibilityElement()
            .accessibilityLabel("Divider between editor and preview")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent editor")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fraction = min(fraction + 0.1, 0.9)
                case .decrement: fraction = max(fraction - 0.1, 0.1)
                @unknown default: break
                }
            }
    }
}

/// The system share sheet for an exported file: Save to Files, AirDrop, Mail, …
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// An exported file waiting to be shared.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

extension Platform {
    /// Light, dark or system, for every window of the app.
    static func apply(_ appearance: AppearanceMode) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = appearance.interfaceStyle
            }
        }
    }
}
#endif
