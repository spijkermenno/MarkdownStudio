#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Small helpers for VoiceOver announcements and the system accessibility settings.
enum AccessibilitySupport {
    #if os(macOS)
    static var isVoiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Speaks `message` with VoiceOver (and other assistive apps) without moving focus.
    static func announce(_ message: String, highPriority: Bool = false) {
        guard !message.isEmpty else { return }
        let element: Any = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp as Any
        let priority: NSAccessibilityPriorityLevel = highPriority ? .high : .medium
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: priority.rawValue])
    }
    #else
    static var isVoiceOverRunning: Bool { UIAccessibility.isVoiceOverRunning }

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Speaks `message` with VoiceOver without moving focus.
    static func announce(_ message: String, highPriority: Bool = false) {
        guard !message.isEmpty else { return }
        let announcement = NSAttributedString(string: message, attributes: [
            .accessibilitySpeechAnnouncementPriority: highPriority ? UIAccessibilityPriority.high : .default,
        ])
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
    #endif

    /// The text VoiceOver reads for a suggestion list, for example
    /// "4 suggestions. tada, 1 of 4. Press Tab to insert."
    nonisolated static func suggestionAnnouncement(count: Int, selected: Int, title: String, includeCount: Bool) -> String {
        let position = "\(title), \(selected + 1) of \(count)"
        guard includeCount else { return position }
        let noun = count == 1 ? "suggestion" : "suggestions"
        return "\(count) \(noun). \(position). Press Tab to insert."
    }
}

extension Animation {
    /// `animation`, or nil (no animation) when Reduce Motion is on.
    static func unlessReduceMotion(_ animation: Animation) -> Animation? {
        AccessibilitySupport.reduceMotion ? nil : animation
    }
}

/// The rounded card buttons on the Welcome window and in the setup. Plain buttons
/// with a custom background don't show a clear keyboard focus ring, so this one
/// draws its own when Full Keyboard Access moves focus to it.
struct CardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    /// Draw the grey card background (the Welcome actions) or leave it to the label.
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        CardButton(configuration: configuration, cornerRadius: cornerRadius, filled: filled)
    }

    private struct CardButton: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        let filled: Bool
        @Environment(\.isFocused) private var isFocused
        #if os(macOS)
        private static let focusRingColor = Color(nsColor: .keyboardFocusIndicatorColor)
        #else
        private static let focusRingColor = Color.accentColor
        #endif

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            configuration.label
                .background(filled ? AnyShapeStyle(.quaternary.opacity(configuration.isPressed ? 1 : 0.6)) : AnyShapeStyle(.clear), in: shape)
                .overlay {
                    if isFocused { shape.strokeBorder(Self.focusRingColor, lineWidth: 3) }
                }
                .opacity(!filled && configuration.isPressed ? 0.8 : 1)
        }
    }
}
