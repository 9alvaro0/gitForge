import Testing
@testable import gitForge

/// The sections of the sidebar (U1 Ruling 9): Pull requests is one of them
/// (what the list shows with and without a repository is `SidebarOrder`'s),
/// and Reviews is not a section any more.
@Suite("Workspace sections")
@MainActor
struct WorkspaceSectionTests {
    @Test("Pull requests is one of the workspace items")
    func pullsIsAWorkspaceItem() {
        #expect(WorkspaceSection.workspaceItems.contains(.pulls))
    }

    @Test("The workspace items are every section but Settings, each once")
    func workspaceItemsAreAllButSettings() {
        let items = WorkspaceSection.workspaceItems
        #expect(items.count == 6)
        #expect(Set(items) == Set(WorkspaceSection.allCases).subtracting([.settings]))
    }

    @Test("The View menu entries are Show <section>, in the order of the sidebar")
    func showCommandTitles() {
        #expect(SidebarOrder().sections.map(\.showCommandTitle) == [
            "Show History", "Show Changes", "Show Branches", "Show Pull Requests", "Show Stashes", "Show Conflicts",
        ])
    }

    @Test("No section is called Reviews")
    func noReviews() {
        for section in WorkspaceSection.allCases {
            #expect(section.label != "Reviews")
        }
    }
}
