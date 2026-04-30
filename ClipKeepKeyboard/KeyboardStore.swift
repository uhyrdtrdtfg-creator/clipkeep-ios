import Foundation
import ClipKeepCore

final class KeyboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var canUndoInsertion = false

    /// Sorted list of all distinct pinned categories.
    var pinnedCategories: [String] {
        items
            .filter { $0.isPinned }
            .compactMap { $0.pinnedCategory }
            .reduce(into: [String]()) { r, c in if !r.contains(c) { r.append(c) } }
            .sorted()
    }

    func reload() {
        items = ClipStore.shared.load()
    }

    func setCanUndoInsertion(_ canUndo: Bool) {
        canUndoInsertion = canUndo
    }
}
