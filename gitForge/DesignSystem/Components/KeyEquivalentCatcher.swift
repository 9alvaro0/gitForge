import SwiftUI
import AppKit

/// ⌘-key presses for a SwiftUI view. AppKit hands key equivalents to the
/// menu bar and the window's shortcuts, never to `onKeyPress`, so a view that
/// wants its own ⌘A or ⌘⌫ catches them here first: a local event monitor that
/// only looks at presses in this view's window, and lets them through while
/// text is being edited there, so text fields keep their ⌘A. It decides from
/// AppKit's state at the moment of the press: SwiftUI's focus state reaches
/// an `NSViewRepresentable` too late to gate on.
///
/// Put it in the view's `.background`; it's live while the view is on screen.
/// `handler` gets the key without modifiers, lowercased, and returns `true`
/// to consume the press; anything else goes on to the menu bar as usual.
struct KeyEquivalentCatcher: NSViewRepresentable {
    var handler: (_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var handler: ((String, NSEvent.ModifierFlags) -> Bool)?
        private var monitor: Any?

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Local monitors run on the main thread.
                let consumed = MainActor.assumeIsolated { self?.consume(event) ?? false }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func consume(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers.contains(.command),
                  let window = view?.window, event.window === window,
                  !(window.firstResponder is NSText),
                  let characters = event.charactersIgnoringModifiers,
                  let handler else { return false }
            return handler(characters.lowercased(), modifiers)
        }
    }
}
