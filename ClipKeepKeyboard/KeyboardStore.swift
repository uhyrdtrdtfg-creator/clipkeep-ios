import Foundation
import ClipKeepCore

final class KeyboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    func reload() {
        items = ClipStore.shared.load()
    }
}
