import AppKit

/// The menu a click on a History row's author opens (#65). An `NSMenu` built
/// on click rather than a SwiftUI `Menu` in every row: the table builds rows
/// while scrolling, and a plain button costs less than a menu button.
@MainActor
enum AuthorMenu {
    static func show(for author: CommitAuthor, onlyCommitsBy: @escaping (CommitAuthor) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: String(localized: "Only commits by \(author.displayName)")) {
            onlyCommitsBy(author)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: String(localized: "Copy author name")) { copy(author.name) })
        if !author.email.isEmpty {
            menu.addItem(ActionMenuItem(title: String(localized: "Copy author email")) { copy(author.email) })
        }
        // No view: the point is in screen coordinates, under the pointer that clicked.
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// A menu item that runs a closure. It is its own target; the menu keeps it
/// alive while it's open.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}
