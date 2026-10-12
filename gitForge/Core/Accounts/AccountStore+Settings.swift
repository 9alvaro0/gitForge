import Foundation

extension AccountStore {
    /// "Link to profile" (`nil` unlinks).
    func linkAccount(_ accountId: UUID, toProfile profileId: UUID?) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.linkedProfileId = profileId
        updateAccount(account)
    }

    /// A deleted profile: accounts linked to it stop pointing at it.
    func unlinkProfile(_ profileId: UUID) {
        for account in accounts where account.linkedProfileId == profileId {
            linkAccount(account.id, toProfile: nil)
        }
    }
}
