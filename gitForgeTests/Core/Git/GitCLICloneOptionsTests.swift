import Foundation
import Testing
@testable import gitForge

@Suite("Clone options and new repository", .serialized)
struct GitCLICloneOptionsTests {

    @Test("CloneOptions map to git clone flags")
    func arguments() {
        #expect(CloneOptions().arguments.isEmpty)
        #expect(CloneOptions(shallow: true).arguments == ["--depth", "1"])
        #expect(CloneOptions(submodules: true).arguments == ["--recurse-submodules"])
        #expect(CloneOptions(shallow: true, submodules: true).arguments
                == ["--depth", "1", "--recurse-submodules", "--shallow-submodules"])
    }

    @Test("initRepository creates the folder and the repo, once")
    func initRepository() async throws {
        let parent = TemporaryDirectories.make("gitForge-init")
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("new project")

        #expect(try await GitCLI.initRepository(at: folder))
        #expect(await GitCLI.resolveRepositoryRoot(at: folder) != nil)
        #expect(try await GitCLI.initRepository(at: folder) == false)
    }
}
