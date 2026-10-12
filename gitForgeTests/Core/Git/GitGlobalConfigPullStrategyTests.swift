import Testing
@testable import gitForge

@Suite("Global config — pull strategy")
struct GitGlobalConfigPullStrategyTests {
    @Test("Every rebasing value shows as rebase", arguments: ["true", "merges", "interactive", "i", "m", "yes", "on", "1", "True"])
    func rebase(value: String) {
        #expect(GitGlobalConfigReader.pullStrategy(rebase: value, ff: nil) == "rebase")
    }

    @Test("git's false spellings show as merge", arguments: ["false", "no", "off", "0"])
    func merge(value: String) {
        #expect(GitGlobalConfigReader.pullStrategy(rebase: value, ff: nil) == "merge")
    }

    @Test("ff only, nothing set, or a value git doesn't know")
    func others() {
        #expect(GitGlobalConfigReader.pullStrategy(rebase: nil, ff: "only") == "ff-only")
        #expect(GitGlobalConfigReader.pullStrategy(rebase: "", ff: nil) == nil)
        #expect(GitGlobalConfigReader.pullStrategy(rebase: "sometimes", ff: nil) == nil)
    }
}
