#if os(macOS)
import AppKit

typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit

typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Clipboard and "open elsewhere" helpers shared by the editor, preview and export.
enum Platform {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    static var clipboardString: String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }

    /// Opens a web link or a file in the app that handles it.
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    #if os(iOS)
    /// The window in front, for presenting UIKit sheets and hosting offscreen web views.
    static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        return (active + scenes).lazy.compactMap(\.keyWindow).first
            ?? scenes.flatMap(\.windows).first
    }
    #endif
}
