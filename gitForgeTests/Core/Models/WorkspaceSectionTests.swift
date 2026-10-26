import Testing
@testable import gitForge

/// The sections of the sidebar (U1 Ruling 9): Pull requests is the only one
/// there when no repository is open, and Reviews is not a section any more.
@Suite("Workspace sections")
@MainActor
struct WorkspaceSectionTests {
    @Test("With a repository open the sidebar lists every workspace item")
    func withRepository() {
        #expect(WorkspaceSection.sidebarItems(hasRepository: true) == WorkspaceSection.workspaceItems)
    }

    @Test("Without a repository the sidebar lists Pull requests alone")
    func withoutRepository() {
        #expect(WorkspaceSection.sidebarItems(hasRepository: false) == [.pulls])
    }

    @Test("Pull requests is one of the workspace items")
    func pullsIsAWorkspaceItem() {
        #expect(WorkspaceSection.workspaceItems.contains(.pulls))
    }

    @Test("No section is called Reviews")
    func noReviews() {
        for section in WorkspaceSection.allCases {
            #expect(section.label != "Reviews")
        }
    }
}
