import Foundation
import Observation

/// User-level catalog of named git identities. Persists to UserDefaults as
/// JSON; never touches `git config` directly — applying a profile to a repo
/// is the caller's responsibility (typically via `GitCLI.setLocalIdentity`).
///
/// The default profile concept is intentionally absent: a repo's effective
/// identity always comes from git itself (local → global). Profiles only
/// give names + signing keys to identities that already work as bundles.
@Observable
@MainActor
final class ProfileStore {
    static let storageKey = "gitForge.profiles"
    /// Quarantine key for blobs that fail to decode — preserved so a
    /// `defaults read` recovers the bytes instead of them being silently
    /// overwritten on the next save.
    static let corruptedKeyPrefix = "gitForge.profiles.corrupted"
    /// Current schema version. Bump when a non-backward-compatible field
    /// arrives; existing optionals-with-default don't require a bump.
    static let schemaVersion = 1

    private(set) var profiles: [GitProfile] = []

    /// Persisted envelope. Wrapping the array lets us bump the schema
    /// without losing existing data on app upgrade.
    private struct StoredProfiles: Codable {
        let version: Int
        let profiles: [GitProfile]
    }

    init() {
        load()
    }

    /// Idempotent migration: if there are no profiles yet but the global
    /// config has a populated identity, materialise it as a "Personal"
    /// profile so the user lands on a non-empty list after upgrading.
    func seedFromGlobalIfEmpty(_ global: GitGlobalConfig) {
        guard profiles.isEmpty,
              let name = global.identity.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let email = global.identity.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else { return }
        let seeded = GitProfile(
            name: "Personal",
            userName: name,
            userEmail: email,
            signingKey: global.signingKey?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        )
        profiles = [seeded]
        save()
    }

    /// Match by email (case-insensitive). Used to resolve "which profile is
    /// this repo currently using" from a `RepoIdentity`. Returns nil for
    /// custom identities not represented by any profile.
    func match(for identity: RepoIdentity) -> GitProfile? {
        guard let email = identity.email?.lowercased(), !email.isEmpty else { return nil }
        return profiles.first { $0.userEmail.lowercased() == email }
    }

    func add(_ profile: GitProfile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: GitProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func remove(_ id: GitProfile.ID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    // MARK: persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        let decoder = JSONDecoder()
        // v1 envelope first; fall back to the bare-array legacy format so
        // users upgrading from a pre-versioned build don't lose profiles.
        if let stored = try? decoder.decode(StoredProfiles.self, from: data) {
            if stored.version > Self.schemaVersion {
                quarantineCorruptedBlob(data, reason: "schema_v\(stored.version)")
                return
            }
            profiles = stored.profiles
            return
        }
        if let legacy = try? decoder.decode([GitProfile].self, from: data) {
            profiles = legacy
            return
        }
        // Neither shape decoded — preserve the bytes for diagnosis instead
        // of silently dropping them on the next save().
        quarantineCorruptedBlob(data, reason: "decode_failure")
    }

    private func save() {
        let envelope = StoredProfiles(version: Self.schemaVersion, profiles: profiles)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Copies the unparseable bytes to a timestamped key (and removes the
    /// primary one) so the next save doesn't overwrite the diagnostic
    /// evidence and the user can recover via `defaults read`.
    private func quarantineCorruptedBlob(_ data: Data, reason: String) {
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let key = "\(Self.corruptedKeyPrefix).\(reason).\(stamp)"
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}

private extension String {
    /// Returns nil for empty strings — keeps optional collapsing tidy
    /// without sprinkling ternaries everywhere.
    var nonEmpty: String? { isEmpty ? nil : self }
}
