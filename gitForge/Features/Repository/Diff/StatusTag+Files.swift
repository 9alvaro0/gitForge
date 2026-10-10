import Foundation

/// Maps each file-change model to the A/M/D badge, so every list and the
/// diff header show the same letter for the same change.
extension StatusTag.Kind {
    /// `.unmodified` collapses to `.modified` so partially-staged files
    /// (where one side is unmodified) still render a badge.
    init(workingFile: WorkingCopyFile.Status) {
        switch workingFile {
        case .modified, .typeChanged: self = .modified
        case .added:                  self = .added
        case .deleted:                self = .deleted
        case .renamed:                self = .renamed
        case .copied:                 self = .copied
        case .untracked:              self = .untracked
        case .unmerged:               self = .unmerged
        case .ignored:                self = .ignored
        case .unmodified:             self = .modified
        }
    }

    init(commitFile: CommitFileChange.Status) {
        switch commitFile {
        case .added:                   self = .added
        case .modified, .typeChanged:  self = .modified
        case .deleted:                 self = .deleted
        case .renamed:                 self = .renamed
        case .copied:                  self = .copied
        case .unmerged:                self = .unmerged
        case .unknown:                 self = .modified
        }
    }

    init(stashFile: StashFileChange.Status) {
        switch stashFile {
        case .added:                   self = .added
        case .modified, .typeChanged:  self = .modified
        case .deleted:                 self = .deleted
        case .renamed:                 self = .renamed
        case .copied:                  self = .copied
        case .untracked:               self = .untracked
        case .other:                   self = .modified
        }
    }

    init(pullRequestFile: PullRequestFileChange.Status) {
        switch pullRequestFile {
        case .added:    self = .added
        case .modified: self = .modified
        case .deleted:  self = .deleted
        case .renamed:  self = .renamed
        case .copied:   self = .copied
        case .other:    self = .modified
        }
    }
}
