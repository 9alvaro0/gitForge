import Foundation

/// Small least-recently-used cache. Reads and writes both count as a use;
/// inserting past `capacity` evicts the least recently used entry. Linear
/// bookkeeping is fine for the few-hundred-entry caches the app keeps.
nonisolated struct LRUCache<Key: Hashable, Value> {
    let capacity: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache needs room for at least one entry")
        self.capacity = capacity
    }

    var count: Int { storage.count }

    mutating func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        storage[key] = value
        touch(key)
        while order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}
