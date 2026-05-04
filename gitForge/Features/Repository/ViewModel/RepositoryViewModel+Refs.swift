import Foundation

extension RepositoryViewModel {
    func loadRefs() async {
        async let refsTask: [GitRef]? = try? cli.refs()
        async let currentTask: String? = cli.currentBranchName()
        async let stashTask: [Stash]? = try? cli.stashes()
        if let refs = await refsTask {
            self.refs = refs
        }
        if let current = await currentTask {
            self.currentBranchName = current
        }
        if let stashes = await stashTask {
            self.stashes = stashes
        }
        await loadAheadBehind()
    }
}
