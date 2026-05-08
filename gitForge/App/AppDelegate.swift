//
//  AppDelegate.swift
//  gitForge
//
//  Created by Alvaro Guerra Freitas on 8/5/26.
//

import AppKit

/// Forces `isMovableByWindowBackground = false` on every window the app
/// becomes key on. SwiftUI re-applies its window defaults asynchronously
/// (after focus changes, fullscreen toggles, etc.), so a one-shot fix from
/// `viewDidMoveToWindow` gets clobbered. Listening to `didBecomeKeyNotification`
/// guarantees we win the last write.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sweep any windows that exist at launch (the WindowGroup's first
        // window is already created by this point).
        for window in NSApp.windows {
            Self.disableBackgroundDrag(window)
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                Self.disableBackgroundDrag(window)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = keyWindowObserver {
            NotificationCenter.default.removeObserver(token)
            keyWindowObserver = nil
        }
    }

    deinit {
        if let token = keyWindowObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Without this, macOS treats every non-interactive region as a window-
    /// drag handle, stealing events from internal resize handles (split panes,
    /// columns) and from any background area the user clicks on.
    private static func disableBackgroundDrag(_ window: NSWindow) {
        window.isMovableByWindowBackground = false
    }
}
