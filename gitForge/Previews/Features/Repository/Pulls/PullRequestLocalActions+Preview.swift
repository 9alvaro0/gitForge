import Foundation

extension PullRequestLocalActions {
    /// A repository that integrates cleanly and checks out `feature`.
    static var preview: PullRequestLocalActions {
        .repository(integrate: { .clean }, checkout: { .done("Checked out feature") })
    }
}
