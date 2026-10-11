import Foundation

extension AccountStore {
    /// "Link to profile" (`nil` unlinks).
    func linkAccount(_ accountId: UUID, toProfile profileId: UUID?) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.linkedProfileId = profileId
        updateAccount(account)
    }
}
