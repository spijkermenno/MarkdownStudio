#if os(macOS)
import AppKit
import Observation
import SwiftUI

@Observable
final class CompletionModel {
    var items: [CompletionItem] = []
    var selection = 0
    /// Follows the editor's font size and zoom.
    var fontSize: CGFloat = 12
    var rowHeight: CGFloat { (fontSize * 2.1).rounded() }
    var width: CGFloat { (280 * fontSize / 12).rounded() }
    @ObservationIgnored var onPick: ((Int) -> Void)?
}

/// Shows completion suggestions in a small panel under the caret.
final class AutocompleteController {
    private weak var textView: MarkdownTextView?
    private let model = CompletionModel()
    private var context: CompletionContext?
    private lazy var panel: NSPanel = makePanel()
    var documentDirectory: URL?
    var isEnabled = true
    /// The editor's font size (including zoom); the list scales with it.
    var fontSize: CGFloat {
        get { model.fontSize }
        set { model.fontSize = max(12, min(newValue, 48)) }
    }
    nonisolated(unsafe) private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel.isVisible }

    init(textView: MarkdownTextView) {
        self.textView = textView
        model.onPick = { [weak self] index in
            self?.model.selection = index
            self?.accept()
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: CompletionListView(model: model))
        return panel
    }

    /// Re-evaluates after typing. Shows, updates or hides the list.
    func update() {
        guard isEnabled, let textView, !textView.hasMarkedText(), textView.selectedRange().length == 0,
              let context = CompletionEngine.context(in: textView.string, caret: textView.selectedRange().location)
        else { return hide() }
        let items = CompletionEngine.items(for: context, text: textView.string, documentDirectory: documentDirectory)
        guard !items.isEmpty else { return hide() }
        let wasVisible = isVisible
        let previousItems = model.items
        self.context = context
        model.items = items
        model.selection = 0
        show(at: context.replaceRange.location)
        // The list is a separate panel VoiceOver never focuses, so speak it.
        if !wasVisible || previousItems != items { announceSelection(includeCount: true) }
    }

    private func announceSelection(includeCount: Bool) {
        guard AccessibilitySupport.isVoiceOverRunning, model.items.indices.contains(model.selection) else { return }
        AccessibilitySupport.announce(AccessibilitySupport.suggestionAnnouncement(
            count: model.items.count, selected: model.selection,
            title: model.items[model.selection].title, includeCount: includeCount))
    }

    private func show(at location: Int) {
        guard let textView, let window = textView.window else { return }
        let caretRect = textView.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        let height = CGFloat(model.items.count) * model.rowHeight + 10
        panel.setContentSize(NSSize(width: model.width, height: height))
        var origin = NSPoint(x: caretRect.minX - 8, y: caretRect.minY - height - 4)
        if let screen = window.screen, origin.y < screen.visibleFrame.minY {
            origin.y = caretRect.maxY + 4   // no room below: show above the line
        }
        panel.setFrameOrigin(origin)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        context = nil
    }

    /// Handles navigation keys while the list is open.
    func handle(_ selector: Selector) -> Bool {
        guard isVisible else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            model.selection = (model.selection + 1) % model.items.count
            announceSelection(includeCount: false)
        case #selector(NSResponder.moveUp(_:)):
            model.selection = (model.selection - 1 + model.items.count) % model.items.count
            announceSelection(includeCount: false)
        case #selector(NSResponder.insertNewline(_:)) where AccessibilitySupport.isVoiceOverRunning:
            // With VoiceOver, Return always starts a new line; Tab inserts the suggestion.
            hide()
            return false
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            accept()
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
        default:
            return false
        }
        return true
    }

    private func accept() {
        guard let textView, let context, model.items.indices.contains(model.selection) else { return hide() }
        let item = model.items[model.selection]
        let ns = textView.string as NSString
        var replacement = item.insertion
        let end = NSMaxRange(context.replaceRange)
        if let closer = context.closer, !(end < ns.length && ns.substring(with: NSRange(location: end, length: 1)) == closer) {
            replacement += closer
        }
        let caret = context.replaceRange.location + item.insertion.utf16Length + (context.closer != nil ? 1 : 0)
        hide()
        textView.apply(TextEdit(range: context.replaceRange, replacement: replacement,
                                selection: NSRange(location: caret, length: 0)))
        if item.keepsOpen { update() }
    }
}

private struct CompletionListView: View {
    let model: CompletionModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                let isSelected = index == model.selection
                HStack(spacing: 8) {
                    switch item.icon {
                    case .emoji(let character): Text(character).frame(width: 18)
                    case .symbol(let name): Image(systemName: name).frame(width: 18).foregroundStyle(.secondary)
                    }
                    Text(item.title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.system(size: model.fontSize))
                .padding(.horizontal, 8)
                .frame(height: model.rowHeight)
                // A tint of the accent color keeps normal text readable with every
                // accent color (white on a yellow accent is 1.5:1); the outline marks
                // the row without relying on color alone.
                .foregroundStyle(Color.primary)
                .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if isSelected { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.onPick?(index) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.onPick?(index) }
            }
        }
        .padding(5)
        .frame(width: model.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
#endif
