import AppKit

/// The menu a click on a History row's author opens (#65). An `NSMenu` built
/// on click rather than a SwiftUI `Menu` in every row: the table builds rows
/// while scrolling, and a plain button costs less than a menu button.
@MainActor
enum AuthorMenu {
    static func show(for author: CommitAuthor, onlyCommitsBy: @escaping (CommitAuthor) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(String(localized: "Only commits by \(author.displayName)")) {
            onlyCommitsBy(author)
        })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Copy author name")) { copy(author.name) })
        if !author.email.isEmpty {
            menu.addItem(item(String(localized: "Copy author email")) { copy(author.email) })
        }
        // No view: the point is in screen coordinates, under the pointer that clicked.
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// A plain `NSMenuItem` that runs `handler`. Not a subclass: `NSMenuItem`'s
    /// initializers are nonisolated, and overriding them from this main-actor
    /// target doesn't compile. `target` is weak, so the item keeps its
    /// `MenuAction` alive through `representedObject`.
    private static func item(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// The target of an `AuthorMenu` item: runs its closure when chosen.
private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        handler()
    }
}
