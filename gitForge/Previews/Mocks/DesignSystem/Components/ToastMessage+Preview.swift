import Foundation

extension ToastMessage {
    static let previewOk    = ToastMessage(message: "Pushed 7 commits to origin/main", kind: .ok)
    static let previewInfo  = ToastMessage(message: "Fetching…", kind: .info)
    static let previewWarn  = ToastMessage(message: "Stash conflict — review", kind: .warn)
    static let previewError = ToastMessage(message: "Push rejected (non fast-forward)", kind: .error)
}
