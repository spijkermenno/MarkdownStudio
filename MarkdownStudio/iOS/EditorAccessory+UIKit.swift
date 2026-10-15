#if os(iOS)
import Observation
import SwiftUI
import UIKit

/// What the bar above the keyboard shows: formatting buttons, or completion
/// suggestions while there are some.
@Observable
final class EditorAccessoryModel {
    var suggestions: [CompletionItem] = []
    var selection = 0
    @ObservationIgnored var onFormat: ((FormatCommand) -> Void)?
    @ObservationIgnored var onPick: ((Int) -> Void)?
    @ObservationIgnored var onDismissKeyboard: (() -> Void)?
}

/// The bar above the keyboard (or at the bottom of the screen with a hardware keyboard).
final class EditorAccessoryView: UIInputView {
    init(model: EditorAccessoryModel) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        let host = UIHostingController(rootView: EditorAccessoryBar(model: model))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private struct EditorAccessoryBar: View {
    let model: EditorAccessoryModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        if model.suggestions.isEmpty {
                            formattingButtons
                        } else {
                            suggestionButtons
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selection) { _, selection in
                    withAnimation(.unlessReduceMotion(.easeOut(duration: 0.15))) { proxy.scrollTo(selection) }
                }
            }
            Divider().frame(height: 24)
            Button {
                model.onDismissKeyboard?()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Hide Keyboard")
        }
        .frame(height: 48)
        .buttonStyle(.borderless)
        .tint(.primary)
    }

    private var formattingButtons: some View {
        ForEach(FormattingBar.groups.indices, id: \.self) { index in
            if index > 0 {
                Divider().frame(height: 22).padding(.horizontal, 4)
            }
            ForEach(FormattingBar.groups[index]) { item in
                Button {
                    model.onFormat?(item.command)
                } label: {
                    // 44 × 44 points: the minimum touch target.
                    Image(systemName: item.symbol)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(item.title)
            }
        }
    }

    private var suggestionButtons: some View {
        ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, item in
            let isSelected = index == model.selection
            Button {
                model.onPick?(index)
            } label: {
                HStack(spacing: 6) {
                    switch item.icon {
                    case .emoji(let character): Text(character)
                    case .symbol(let name): Image(systemName: name).foregroundStyle(.secondary)
                    }
                    Text(item.title).lineLimit(1)
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                // A tint plus an outline stays readable with every accent color.
                .background(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), in: Capsule())
                .overlay {
                    if isSelected { Capsule().strokeBorder(Color.accentColor, lineWidth: 1) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .id(index)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint("Inserts the suggestion")
        }
    }
}

/// Completion suggestions for the editor, shown in the bar above the keyboard.
final class AutocompleteController {
    private weak var textView: MarkdownTextView?
    private let model: EditorAccessoryModel
    private var context: CompletionContext?
    var documentDirectory: URL?
    var isEnabled = true
    /// Kept for parity with the Mac, where the list follows the editor font.
    var fontSize: CGFloat = 12
    /// Called when the list opens or closes, so the editor can update the keyboard bar.
    var onVisibilityChange: (() -> Void)?

    var isVisible: Bool { !model.suggestions.isEmpty }

    init(textView: MarkdownTextView, model: EditorAccessoryModel) {
        self.textView = textView
        self.model = model
        model.onPick = { [weak self] index in
            self?.model.selection = index
            self?.accept()
        }
        textView.onSuggestionKey = { [weak self] key in self?.handle(key) ?? false }
    }

    /// Re-evaluates after typing. Shows, updates or hides the list.
    func update() {
        guard isEnabled, let textView, textView.markedTextRange == nil, textView.selectedRange.length == 0,
              let context = CompletionEngine.context(in: textView.text, caret: textView.selectedRange.location)
        else { return hide() }
        let items = CompletionEngine.items(for: context, text: textView.text, documentDirectory: documentDirectory)
        guard !items.isEmpty else { return hide() }
        let wasVisible = isVisible
        let previousItems = model.suggestions
        self.context = context
        model.suggestions = items
        model.selection = 0
        if !wasVisible { setVisible(true) }
        if !wasVisible || previousItems != items { announceSelection(includeCount: true) }
    }

    func hide() {
        guard isVisible else { return }
        model.suggestions = []
        context = nil
        setVisible(false)
    }

    private func setVisible(_ visible: Bool) {
        textView?.isShowingSuggestions = visible
        onVisibilityChange?()
    }

    private func announceSelection(includeCount: Bool) {
        guard AccessibilitySupport.isVoiceOverRunning, model.suggestions.indices.contains(model.selection) else { return }
        AccessibilitySupport.announce(AccessibilitySupport.suggestionAnnouncement(
            count: model.suggestions.count, selected: model.selection,
            title: model.suggestions[model.selection].title, includeCount: includeCount))
    }

    private func handle(_ key: MarkdownTextView.SuggestionKey) -> Bool {
        guard isVisible else { return false }
        switch key {
        case .down:
            model.selection = (model.selection + 1) % model.suggestions.count
            announceSelection(includeCount: false)
        case .up:
            model.selection = (model.selection - 1 + model.suggestions.count) % model.suggestions.count
            announceSelection(includeCount: false)
        case .accept:
            accept()
        case .cancel:
            hide()
        }
        return true
    }

    private func accept() {
        guard let textView, let context, model.suggestions.indices.contains(model.selection) else { return hide() }
        let item = model.suggestions[model.selection]
        let ns = textView.text as NSString
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
#endif
