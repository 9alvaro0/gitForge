import SwiftUI

extension View {
    /// The context menu and accessibility actions that move `section`
    /// (pulls-unified §4.7, Ruling 7), for whoever doesn't drag: keyboard,
    /// VoiceOver, a trackpad that is awkward to drag with.
    func sectionReordering(_ section: WorkspaceSection, in order: SidebarOrder,
                           onEdit: @escaping (SidebarOrder.Edit) -> Void) -> some View {
        modifier(SidebarSectionReordering(section: section, order: order, onEdit: onEdit))
    }
}

/// "Move Up", "Move Down" and "Reset Order" for one sidebar section.
///
/// The menu always lists the three and greys out the ones that would do
/// nothing; VoiceOver doesn't show a disabled action, so the accessibility
/// actions offer only the ones that would do something.
private struct SidebarSectionReordering: ViewModifier {
    let section: WorkspaceSection
    let order: SidebarOrder
    let onEdit: (SidebarOrder.Edit) -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Move Up") { onEdit(.moveUp(section)) }
                    .disabled(!order.canMoveUp(section))
                Button("Move Down") { onEdit(.moveDown(section)) }
                    .disabled(!order.canMoveDown(section))
                Divider()
                Button("Reset Order") { onEdit(.reset) }
                    .disabled(order.isDefault)
            }
            .accessibilityActions {
                if order.canMoveUp(section) {
                    Button("Move Up") { onEdit(.moveUp(section)) }
                }
                if order.canMoveDown(section) {
                    Button("Move Down") { onEdit(.moveDown(section)) }
                }
                if !order.isDefault {
                    Button("Reset Order") { onEdit(.reset) }
                }
            }
    }
}
