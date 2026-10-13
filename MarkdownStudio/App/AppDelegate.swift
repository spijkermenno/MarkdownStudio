import AppKit
import SwiftUI

/// Replaces the automatic untitled document at launch with the Welcome window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// Like Android Studio: save edited documents when you switch to another app,
    /// so other tools always see the latest text. (Documents also autosave a
    /// few seconds after you stop typing, and when closed.)
    func applicationDidResignActive(_ notification: Notification) {
        for document in NSDocumentController.shared.documents where document.fileURL != nil && document.isDocumentEdited {
            document.autosave(withImplicitCancellability: false) { _ in }
        }
    }

    /// Clicking the Dock icon with no windows open shows the Welcome window again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { WelcomeWindow.show() }
        return true
    }
}

enum WelcomeWindow {
    static let id = "welcome"
    /// Captured from the SwiftUI environment so AppKit code can open the window.
    static var openWindow: OpenWindowAction?

    static func show() {
        openWindow?(id: id)
    }
}
