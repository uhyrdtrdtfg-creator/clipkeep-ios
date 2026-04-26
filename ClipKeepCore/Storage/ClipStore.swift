import Foundation
import UIKit
import UniformTypeIdentifiers

public final class ClipStore: @unchecked Sendable {
    public static let shared = ClipStore()

    private let defaults: UserDefaults
    private let assetsDirectory: URL
    private let fileManager: FileManager
    private let key = "clip_items"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxAssetBytes = 25 * 1024 * 1024

    // Callbacks are dispatched on the main queue.
    public var onChange: (() -> Void)?

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        assetsDirectory: URL = AppGroup.assetsDirectory,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.assetsDirectory = assetsDirectory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
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
        add(.text(content))
    }

    /// Insert or update a captured pasteboard item. Returns true when the store was mutated.
    @discardableResult
    public func add(_ captured: CapturedClip) -> Bool {
        switch captured.kind {
        case .text:
            return addText(captured.content)
        case .image, .file:
            return addAsset(captured)
        }
    }

    public func delete(id: UUID) {
        var items = load()
        let removed = items.filter { $0.id == id }
        items.removeAll { $0.id == id }
        save(items)
        removeAssets(for: removed)
    }

    public func togglePin(id: UUID) {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        if !items[idx].isPinned { items[idx].pinnedCategory = nil }
        save(items)
    }

    /// Pin an item into a specific category (creates pin if not already pinned).
    public func pin(id: UUID, category: String?) {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned = true
        items[idx].pinnedCategory = category
        save(items)
    }

    /// Move a pinned item to a different category.
    public func setCategory(id: UUID, category: String?) {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinnedCategory = category
        save(items)
    }

    /// All distinct category names that have at least one pinned item.
    public func allPinnedCategories() -> [String] {
        load()
            .filter { $0.isPinned }
            .compactMap { $0.pinnedCategory }
            .reduce(into: [String]()) { result, cat in
                if !result.contains(cat) { result.append(cat) }
            }
    }

    public func clearAll() {
        let removed = load()
        save([])
        removeAssets(for: removed)
    }

    public func clearUnpinned() {
        let loaded = load()
        let items = loaded.filter { $0.isPinned }
        save(items)
        removeAssets(for: loaded.filter { !$0.isPinned })
    }

    public func copyToPasteboard(_ item: ClipItem, pasteboard: UIPasteboard = .general) -> Bool {
        switch item.kind {
        case .text:
            pasteboard.string = item.content
            return true
        case .image:
            guard let url = assetURL(for: item),
                  let data = try? Data(contentsOf: url) else { return false }
            if let image = UIImage(data: data) {
                pasteboard.image = image
            } else {
                pasteboard.setData(data, forPasteboardType: item.typeIdentifier ?? UTType.png.identifier)
            }
            return true
        case .file:
            guard let url = assetURL(for: item) else { return false }
            if let provider = NSItemProvider(contentsOf: url) {
                pasteboard.setItemProviders([provider], localOnly: false, expirationDate: nil)
                return true
            }
            guard let data = try? Data(contentsOf: url) else { return false }
            pasteboard.setData(data, forPasteboardType: item.typeIdentifier ?? UTType.data.identifier)
            return true
        }
    }

    public func assetURL(for item: ClipItem) -> URL? {
        guard let relativePath = item.relativePath else { return nil }
        return assetURL(relativePath: relativePath)
    }

    public func thumbnailURL(for item: ClipItem) -> URL? {
        guard let relativePath = item.thumbnailRelativePath else { return nil }
        return assetURL(relativePath: relativePath)
    }

    public func assetURL(relativePath: String) -> URL? {
        guard !relativePath.contains("/") else { return nil }
        return assetsDirectory.appendingPathComponent(relativePath)
    }

    // MARK: - Capacity

    private var maxCount: Int {
        defaults.integer(forKey: "max_clip_count").nonzero ?? 200
    }

    public func setMaxCount(_ count: Int) {
        defaults.set(count, forKey: "max_clip_count")
        var items = load()
        let removed = trim(&items)
        save(items)
        removeAssets(for: removed)
    }

    public func getMaxCount() -> Int { maxCount }

    // MARK: - Helpers

    private func addText(_ content: String) -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var items = load()
        let hash = ClipItem.hash(content)

        if let idx = items.firstIndex(where: { $0.contentHash == hash }) {
            items[idx].touch()
            save(items)
            return true
        }

        let item = ClipItem(content: content)
        items.insert(item, at: 0)
        let removed = trim(&items)
        save(items)
        removeAssets(for: removed)
        return true
    }

    private func addAsset(_ captured: CapturedClip) -> Bool {
        guard let data = captured.data, !data.isEmpty, data.count <= maxAssetBytes else { return false }

        var items = load()
        let hash = ClipItem.hash(data)

        if let idx = items.firstIndex(where: { $0.kind == captured.kind && $0.contentHash == hash }) {
            items[idx].touch()
            save(items)
            return true
        }

        guard let relativePath = saveAsset(data, fileExtension: preferredExtension(for: captured)) else {
            return false
        }

        let thumbnailPath = makeThumbnailData(from: data, typeIdentifier: captured.typeIdentifier)
            .flatMap { saveAsset($0, fileExtension: "jpg") }

        let item = ClipItem(
            kind: captured.kind,
            content: captured.content,
            contentHash: hash,
            fileName: captured.fileName,
            typeIdentifier: captured.typeIdentifier,
            byteCount: data.count,
            relativePath: relativePath,
            thumbnailRelativePath: thumbnailPath
        )
        items.insert(item, at: 0)
        let removed = trim(&items)
        save(items)
        removeAssets(for: removed)
        return true
    }

    @discardableResult
    private func trim(_ items: inout [ClipItem]) -> [ClipItem] {
        let original = items
        let pinned = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }
        let limit = max(0, maxCount - pinned.count)
        if unpinned.count > limit {
            unpinned = Array(unpinned.prefix(limit))
        }
        items = pinned + unpinned
        let keptIDs = Set(items.map(\.id))
        return original.filter { !keptIDs.contains($0.id) }
    }

    private func save(_ items: [ClipItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: key)
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    private func saveAsset(_ data: Data, fileExtension: String) -> String? {
        let safeExtension = fileExtension.trimmingCharacters(in: .alphanumerics.inverted)
        let name = "\(UUID().uuidString).\(safeExtension.isEmpty ? "bin" : safeExtension)"
        let url = assetsDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    private func removeAssets(for items: [ClipItem]) {
        for item in items {
            [item.relativePath, item.thumbnailRelativePath]
                .compactMap { $0 }
                .compactMap(assetURL(relativePath:))
                .forEach { try? fileManager.removeItem(at: $0) }
        }
    }

    private func preferredExtension(for captured: CapturedClip) -> String {
        if let fileName = captured.fileName {
            let ext = URL(fileURLWithPath: fileName).pathExtension
            if !ext.isEmpty { return ext }
        }
        if let typeIdentifier = captured.typeIdentifier,
           let ext = UTType(typeIdentifier)?.preferredFilenameExtension {
            return ext
        }
        return captured.kind == .image ? "png" : "bin"
    }

    private func makeThumbnailData(from data: Data, typeIdentifier: String?) -> Data? {
        if let typeIdentifier,
           let type = UTType(typeIdentifier),
           !type.conforms(to: .image) {
            return nil
        }
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 220
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxSide / longestSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.jpegData(compressionQuality: 0.78)
    }
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}
