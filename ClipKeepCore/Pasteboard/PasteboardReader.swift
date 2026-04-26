import UIKit
import UniformTypeIdentifiers

public protocol PasteboardProtocol {
    var changeCount: Int { get }
    var hasStrings: Bool { get }
    var string: String? { get }
    var hasImages: Bool { get }
    var image: UIImage? { get }
    var hasURLs: Bool { get }
    var url: URL? { get }
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
        guard let clip = readClipIfChanged(), clip.kind == .text else { return nil }
        return clip.content
    }

    /// Returns the new pasteboard item if the pasteboard changed since the last call; nil otherwise.
    public func readClipIfChanged() -> CapturedClip? {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return nil }
        markSeen(current)

        if let imageClip = readImage() {
            return imageClip
        }

        if let fileClip = readFileURL() {
            return fileClip
        }

        guard pasteboard.hasStrings else { return nil }
        return pasteboard.string.map(CapturedClip.text)
    }

    public func markCurrentChangeCountSeen() {
        markSeen(pasteboard.changeCount)
    }

    private func markSeen(_ changeCount: Int) {
        lastChangeCount = changeCount
        defaults?.set(changeCount, forKey: changeCountKey)
    }

    private func readImage() -> CapturedClip? {
        guard pasteboard.hasImages,
              let image = pasteboard.image,
              let data = image.pngData() else { return nil }
        return CapturedClip(
            kind: .image,
            content: "图片",
            data: data,
            fileName: "Clipboard Image.png",
            typeIdentifier: UTType.png.identifier
        )
    }

    private func readFileURL() -> CapturedClip? {
        guard pasteboard.hasURLs, let url = pasteboard.url, url.isFileURL else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        return CapturedClip(
            kind: .file,
            content: url.lastPathComponent,
            data: data,
            fileName: url.lastPathComponent,
            typeIdentifier: type?.identifier
        )
    }

}
