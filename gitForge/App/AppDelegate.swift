import AppKit

/// Forces `isMovableByWindowBackground = false` on every window the app
/// becomes key on. SwiftUI re-applies its window defaults asynchronously
/// (after focus changes, fullscreen toggles, etc.), so a one-shot fix from
/// `viewDidMoveToWindow` gets clobbered. Listening to `didBecomeKeyNotification`
/// guarantees we win the last write.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyWindowObserver: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sweep any windows that exist at launch (the WindowGroup's first
        // window is already created by this point).
        for window in NSApp.windows {
            Self.disableBackgroundDrag(window)
        }
        keyWindowObserver = Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: NSWindow.didBecomeKeyNotification) {
                if let window = notification.object as? NSWindow {
                    Self.disableBackgroundDrag(window)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyWindowObserver?.cancel()
        keyWindowObserver = nil
    }

    deinit {
        keyWindowObserver?.cancel()
    }

    /// Without this, macOS treats every non-interactive region as a window-
    /// drag handle, stealing events from internal resize handles (split panes,
    /// columns) and from any background area the user clicks on.
    @MainActor
    private static func disableBackgroundDrag(_ window: NSWindow) {
        window.isMovableByWindowBackground = false
    }
}
