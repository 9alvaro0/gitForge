import Foundation
import Testing
@testable import gitForge

@Suite("AppLanguageStore")
struct AppLanguageStoreTests {

    @Test("Follows the system until a language is picked")
    func defaultsToSystem() {
        TestDefaults.with { suite in
            let store = AppLanguageStore(defaults: suite.defaults, domain: suite.suiteName)
            #expect(store.override == nil)
        }
    }

    @Test("Picking a language writes it as the app's AppleLanguages")
    func setsOverride() {
        TestDefaults.with { suite in
            let store = AppLanguageStore(defaults: suite.defaults, domain: suite.suiteName)
            store.setOverride(.portuguese)
            #expect(store.override == .portuguese)
            #expect(suite.defaults.persistentDomain(forName: suite.suiteName)?["AppleLanguages"] as? [String] == ["pt-PT"])
        }
    }

    @Test("Going back to the system default removes the override")
    func clearsOverride() {
        TestDefaults.with { suite in
            let store = AppLanguageStore(defaults: suite.defaults, domain: suite.suiteName)
            store.setOverride(.spanish)
            store.setOverride(nil)
            #expect(store.override == nil)
        }
    }

    @Test("An unsupported language in the domain reads as the system default")
    func unknownCode() {
        TestDefaults.with { suite in
            suite.defaults.set(["fr"], forKey: "AppleLanguages")
            let store = AppLanguageStore(defaults: suite.defaults, domain: suite.suiteName)
            #expect(store.override == nil)
        }
    }
}
