import Foundation
import Testing
@testable import gitForge

@Suite("WorkingCopyFile.Status — spoken name")
struct WorkingCopyStatusSpokenNameTests {

    @Test("Every porcelain status has a non-empty spoken form for VoiceOver")
    func everyStatusHasASpokenName() {
        // No exhaustive enum iteration in Swift without CaseIterable, so the
        // list is maintained alongside the type. If a new status is added,
        // this test forces the spokenName to be filled in too.
        let all: [WorkingCopyFile.Status] = [
            .unmodified, .modified, .added, .deleted, .renamed,
            .copied, .typeChanged, .untracked, .ignored, .unmerged,
        ]
        for status in all {
            #expect(!status.spokenName.isEmpty, "missing spoken name for \(status)")
            #expect(status.spokenName.count > 1, "single-letter spoken name for \(status) defeats the purpose")
        }
    }

    @Test("Spoken names are lowercase English words (screen reader friendly)")
    func spokenNamesAreLowercaseWords() {
        // displayLetter ("M", "A", "?") works on screen but reads as single
        // characters by VoiceOver. The whole point of spokenName is the
        // word form — assert it.
        #expect(WorkingCopyFile.Status.modified.spokenName == "modified")
        #expect(WorkingCopyFile.Status.added.spokenName == "added")
        #expect(WorkingCopyFile.Status.untracked.spokenName == "untracked")
        #expect(WorkingCopyFile.Status.unmerged.spokenName == "unmerged")
        #expect(WorkingCopyFile.Status.typeChanged.spokenName == "type changed")
    }
}
