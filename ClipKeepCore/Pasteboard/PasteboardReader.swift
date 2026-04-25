import UIKit

public protocol PasteboardProtocol {
    var changeCount: Int { get }
    var hasStrings: Bool { get }
    var string: String? { get }
}

extension UIPasteboard: PasteboardProtocol {}

/// Reads the pasteboard only when changeCount advances, avoiding the "Pasted" banner.
public final class PasteboardReader {
    private var lastChangeCount: Int?
    private let pasteboard: PasteboardProtocol
    private let defaults: UserDefaults?
    private let changeCountKey: String

    public init(
        pasteboard: PasteboardProtocol = UIPasteboard.general,
        defaults: UserDefaults? = nil,
        changeCountKey: String = "last_pasteboard_change_count",
        readsInitialValue: Bool = false
    ) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.changeCountKey = changeCountKey

        if let defaults, defaults.object(forKey: changeCountKey) != nil {
            self.lastChangeCount = defaults.integer(forKey: changeCountKey)
        } else {
            // Most tests and one-off readers should not pull existing clipboard
            // content on construction. App/keyboard activation paths opt in.
            self.lastChangeCount = readsInitialValue ? nil : pasteboard.changeCount
        }
    }

    /// Returns the new string if the pasteboard changed since the last call; nil otherwise.
    public func readIfChanged() -> String? {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return nil }
        markSeen(current)
        guard pasteboard.hasStrings else { return nil }
        return pasteboard.string
    }

    public func markCurrentChangeCountSeen() {
        markSeen(pasteboard.changeCount)
    }

    private func markSeen(_ changeCount: Int) {
        lastChangeCount = changeCount
        defaults?.set(changeCount, forKey: changeCountKey)
    }
}
