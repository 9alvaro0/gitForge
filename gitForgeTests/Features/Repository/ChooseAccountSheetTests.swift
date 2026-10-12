import Foundation
import Testing
@testable import gitForge

@Suite("Choose an account — summary text")
struct ChooseAccountSheetTests {
    @Test("Names the provider and gets the count right")
    func summary() {
        #expect(ChooseAccountSheet.summary(count: 2, provider: "GitLab", host: "gitlab.com", ownerRepo: "group/app")
                    .hasPrefix("2 GitLab accounts could be used for group/app."))
        #expect(ChooseAccountSheet.summary(count: 1, provider: "GitHub", host: "github.com", ownerRepo: "octo/app")
                    .hasPrefix("One GitHub account could be used"))
        #expect(ChooseAccountSheet.summary(count: 3, provider: nil, host: "git.example.test", ownerRepo: "x/y")
                    .hasPrefix("3 accounts on git.example.test could be used"))
    }
}
