import Testing
@testable import gitForge

@Suite("LRUCache")
struct LRUCacheTests {

    @Test("Evicts the least recently used entry past capacity")
    func evictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        _ = cache.value(for: "a")          // "b" is now the oldest
        cache.insert(3, for: "c")
        #expect(cache.count == 2)
        #expect(cache.value(for: "b") == nil)
        #expect(cache.value(for: "a") == 1)
        #expect(cache.value(for: "c") == 3)
    }

    @Test("Re-inserting a key refreshes it without growing the cache")
    func reinsertRefreshes() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.insert(10, for: "a")
        cache.insert(3, for: "c")
        #expect(cache.count == 2)
        #expect(cache.value(for: "a") == 10)
        #expect(cache.value(for: "b") == nil)
    }
}
