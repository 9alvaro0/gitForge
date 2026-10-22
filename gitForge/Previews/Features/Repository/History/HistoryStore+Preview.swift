import Foundation

/// Hooks for previews and tests. They lay the graph out on the caller's
/// actor, which the loaders never do (`publish(_:then:)` goes off the main
/// actor), so they live here, outside the production sources.
extension HistoryStore {
    /// Swaps in a fresh first page and its graph, laid out on the caller's
    /// actor. For tests and previews; the loaders `publish` instead, so the
    /// layout never runs on the main actor.
    func replaceLog(with page: [Commit]) {
        let staged = stageFirstPage(page)
        install(staged, CommitGraphEngine.layout(staged.input), from: staged.input)
    }

    /// Appends the next page and publishes the graph with it, laid out on the
    /// caller's actor. For tests and previews, as `replaceLog(with:)`.
    func appendPage(_ page: [Commit]) {
        let staged = stageNextPage(page)
        install(staged, CommitGraphEngine.layout(staged.input), from: staged.input)
    }

    /// Lays the published log out again, synchronously on the caller's actor.
    /// For SwiftUI previews and tests that need the graph populated before
    /// the next instruction; production code uses `recomputeGraph()`, which
    /// keeps the main actor free.
    func recomputeGraphSync() {
        graphLayoutGen &+= 1
        let input = graphInput()
        apply(CommitGraphEngine.layout(input), from: input)
    }
}
