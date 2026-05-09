import Foundation

extension MoveBranchRequest {
    static let previewSample = MoveBranchRequest(
        branch: GitRef.previewSamples[0],
        targetSha: "abc1234abcdef5678",
        targetShortSha: "abc1234"
    )
}

extension ResetHeadRequest {
    static let previewSample = ResetHeadRequest(
        branchName: "main",
        targetSha: "abc1234abcdef5678",
        targetShortSha: "abc1234"
    )
}

extension MergeRebaseRequest {
    static let previewSample = MergeRebaseRequest(
        source: GitRef.previewSamples[0],
        target: GitRef.previewSamples[1]
    )
}
