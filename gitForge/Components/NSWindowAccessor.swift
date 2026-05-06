import SwiftUI
import AppKit

/// Bridges into the underlying `NSWindow` so we can fine-tune chrome
/// (transparent titlebar, fullSizeContentView) without losing native behavior.
struct NSWindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

extension View {
    func configureWindow(_ block: @escaping (NSWindow) -> Void) -> some View {
        background(NSWindowAccessor(configure: block))
    }
}
