import Foundation

public final class ClipStore: @unchecked Sendable {
    public static let shared = ClipStore()

    private let defaults: UserDefaults
    private let key = "clip_items"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Callbacks are dispatched on the main queue.
    public var onChange: (() -> Void)?

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    // MARK: - Read

    public func load() -> [ClipItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? decoder.decode([ClipItem].self, from: data) else {
            return []
        }
        return items
    }

    // MARK: - Write

    /// Insert or update an item. Returns true when the store was mutated.
    @discardableResult
    public func add(_ content: String) -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var items = load()
        let hash = ClipItem.hash(content)

        if let idx = items.firstIndex(where: { $0.contentHash == hash }) {
            // Same content – refresh timestamp only.
            items[idx].touch()
            save(items)
            return true
        }

        var item = ClipItem(content: content)
        items.insert(item, at: 0)
        trim(&items)
        save(items)
        return true
    }

    public func delete(id: UUID) {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
    }

    public func togglePin(id: UUID) {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        save(items)
    }

    public func clearAll() {
        save([])
    }

    public func clearUnpinned() {
        let items = load().filter { $0.isPinned }
        save(items)
    }

    // MARK: - Capacity

    private var maxCount: Int {
        defaults.integer(forKey: "max_clip_count").nonzero ?? 200
    }

    public func setMaxCount(_ count: Int) {
        defaults.set(count, forKey: "max_clip_count")
        var items = load()
        trim(&items)
        save(items)
    }

    public func getMaxCount() -> Int { maxCount }

    // MARK: - Helpers

    private func trim(_ items: inout [ClipItem]) {
        let pinned = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }
        let limit = max(0, maxCount - pinned.count)
        if unpinned.count > limit {
            unpinned = Array(unpinned.prefix(limit))
        }
        items = pinned + unpinned
    }

    private func save(_ items: [ClipItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: key)
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}
