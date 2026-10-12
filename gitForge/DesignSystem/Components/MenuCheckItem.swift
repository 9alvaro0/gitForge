import SwiftUI

/// A menu item with the system's own checkmark: aligned with its siblings
/// and announced as selected by VoiceOver, unlike a `Label` with a
/// "checkmark" symbol. Choosing it runs `action` (it never unchecks itself).
struct MenuCheckItem: View {
    let title: String
    /// Shown under the title by the system menu.
    var subtitle: String?
    let isChecked: Bool
    let action: () -> Void

    init(_ title: String, subtitle: String? = nil, isChecked: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isChecked = isChecked
        self.action = action
    }

    var body: some View {
        Toggle(isOn: Binding(get: { isChecked }, set: { _ in action() })) {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }
}
