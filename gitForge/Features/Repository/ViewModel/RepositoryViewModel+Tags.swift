import Foundation
import os

/// Tag operations on top of `RepositoryViewModel`. All methods return a
/// `Result` so the caller can route success/failure to the toast pipeline.
extension RepositoryViewModel {
    func createTag(name: String, at sha: String? = nil, message: String? = nil) async -> Result<Void, Error> {
        do {
            try await cli.createTag(name: name, at: sha, message: message)
            await loadRefs()
            return .success(())
        } catch {
            Self.logger.error("Create tag \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func deleteTag(_ ref: GitRef) async -> Result<Void, Error> {
        do {
            try await cli.deleteTag(name: ref.name)
            await loadRefs()
            return .success(())
        } catch {
            Self.logger.error("Delete tag \(ref.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func pushTag(_ ref: GitRef) async -> Result<Void, Error> {
        guard remoteOperation == nil else { return .failure(GitError.busy) }
        remoteOperation = .pushing
        defer { remoteOperation = nil }
        do {
            try await cli.pushTag(name: ref.name)
            return .success(())
        } catch {
            remoteFailure = RemoteFailure.from(error)
            return .failure(error)
        }
    }

    /// Removes a tag from the remote. Local copy is left alone — call
    /// `deleteTag(_:)` separately if you also want to drop it locally.
    func pushDeleteTag(_ ref: GitRef) async -> Result<Void, Error> {
        guard remoteOperation == nil else { return .failure(GitError.busy) }
        remoteOperation = .pushing
        defer { remoteOperation = nil }
        do {
            try await cli.pushDeleteTag(name: ref.name)
            return .success(())
        } catch {
            remoteFailure = RemoteFailure.from(error)
            return .failure(error)
        }
    }

    func pushAllTags() async -> Result<Void, Error> {
        guard remoteOperation == nil else { return .failure(GitError.busy) }
        remoteOperation = .pushing
        defer { remoteOperation = nil }
        do {
            try await cli.pushAllTags()
            return .success(())
        } catch {
            remoteFailure = RemoteFailure.from(error)
            return .failure(error)
        }
    }
}
