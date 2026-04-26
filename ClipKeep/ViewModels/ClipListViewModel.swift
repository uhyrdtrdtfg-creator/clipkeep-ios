import Foundation
import UIKit
import ClipKeepCore

@MainActor
final class ClipListViewModel: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var searchText = ""
    @Published var showOnboarding = false

    private let store: ClipStore
    private let reader: PasteboardReader
    private let defaults: UserDefaults

    var displayedItems: [ClipItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        let base = items
        guard !q.isEmpty else { return base }
        return base.filter { $0.searchableText.localizedCaseInsensitiveContains(q) }
    }

    init(store: ClipStore = .shared, defaults: UserDefaults = AppGroup.defaults) {
        self.store = store
        self.defaults = defaults
        self.reader = PasteboardReader(defaults: defaults, readsInitialValue: true)
        reload()
        store.onChange = { [weak self] in
            Task { @MainActor in self?.reload() }
        }

        if !defaults.bool(forKey: "onboarding_done") {
            showOnboarding = true
        }
        capturePasteboardIfNeeded()
    }

    func onForeground() {
        capturePasteboardIfNeeded()
    }

    @discardableResult
    func copy(_ item: ClipItem) -> Bool {
        let copied = store.copyToPasteboard(item)
        if copied {
            reader.markCurrentChangeCountSeen()
        }
        return copied
    }

    func delete(_ item: ClipItem) {
        store.delete(id: item.id)
    }

    func togglePin(_ item: ClipItem) {
        store.togglePin(id: item.id)
    }

    func dismissOnboarding() {
        defaults.set(true, forKey: "onboarding_done")
        showOnboarding = false
    }

    private func capturePasteboardIfNeeded() {
        if let clip = reader.readClipIfChanged() {
            store.add(clip)
        }
        reload()
    }

    private func reload() {
        items = store.load()
    }
}
