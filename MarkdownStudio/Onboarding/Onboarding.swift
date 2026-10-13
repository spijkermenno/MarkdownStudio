import AppKit
import Foundation

/// First-run onboarding: a short setup window followed by a guided tour.
/// `hasCompletedOnboarding` is stored in UserDefaults and only becomes true
/// when the last step of the tour is finished.
enum Onboarding {
    static let windowID = "onboarding"
    static let completedKey = "hasCompletedOnboarding"

    /// Where the flag is stored; tests swap in their own suite.
    static var defaults = UserDefaults.standard

    static var isCompleted: Bool {
        defaults.bool(forKey: completedKey)
    }

    static func markCompleted() {
        defaults.set(true, forKey: completedKey)
    }

    /// Prevents showing it twice when both the Welcome window and a document window appear at launch.
    private static var presentedThisLaunch = false

    /// Unit tests launch the app as their host; don't pop up onboarding there.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// True once per launch when onboarding hasn't been completed yet.
    static func shouldPresentAutomatically() -> Bool {
        guard !isCompleted, !presentedThisLaunch, !isRunningTests else { return false }
        presentedThisLaunch = true
        return true
    }

    /// The sample document used by the tour.
    static let tourText = """
    # Welcome to Markdown Studio

    This is a sample document for the tour. Edit it freely: it isn't saved anywhere unless you choose File → Save.

    ## Writing

    Markdown uses plain characters for formatting: **bold**, *italic*, `code` and [links](https://www.markdownguide.org).

    - Lists continue when you press Return
    - Tab indents, Shift-Tab outdents
    - [ ] Click this checkbox in the preview
    - [x] Already done

    ## Code and tables

    ```swift
    print("Hello, Markdown")
    ```

    | Shortcut | Action |
    | :-- | :-- |
    | ⌘1 ⌘2 ⌘3 | Editor, split, preview |
    | ⌘B ⌘I | Bold, italic |
    | ⌘P | Quick Open |

    ## Next steps

    1. Open one of your own files with ⌘O
    2. Or open a whole folder with ⌥⌘O
    3. Find the full syntax under Help → Markdown Cheat Sheet

    """
}
