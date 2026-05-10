import Foundation

extension Error {
    /// User-facing message: `LocalizedError.errorDescription` when the error
    /// implements it, falling back to `localizedDescription`. Replaces the
    /// `(self as? LocalizedError)?.errorDescription ?? localizedDescription`
    /// dance that was duplicated across every view-model catch block.
    var userMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
