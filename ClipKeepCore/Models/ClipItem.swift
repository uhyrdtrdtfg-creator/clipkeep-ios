import Foundation
import CryptoKit

public enum ClipKind: String, Codable, Sendable {
    case text
    case image
    case file
}

public struct CapturedClip: Equatable, Sendable {
    public let kind: ClipKind
    public let content: String
    public let data: Data?
    public let fileName: String?
    public let typeIdentifier: String?

    public init(
        kind: ClipKind,
        content: String,
        data: Data? = nil,
        fileName: String? = nil,
        typeIdentifier: String? = nil
    ) {
        self.kind = kind
        self.content = content
        self.data = data
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
    }

    public static func text(_ string: String) -> CapturedClip {
        CapturedClip(kind: .text, content: string)
    }
}

public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: ClipKind
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var pinnedCategory: String?   // nil = 未分类收藏
    public var recognizedText: String?   // cached OCR result for image items
    public let contentHash: String
    public var fileName: String?
    public var typeIdentifier: String?
    public var byteCount: Int?
    public var relativePath: String?
    public var thumbnailRelativePath: String?

    public init(content: String, date: Date = .now) {
        self.id = UUID()
        self.kind = .text
        self.content = content
        self.createdAt = date
        self.updatedAt = date
        self.isPinned = false
        self.pinnedCategory = nil
        self.contentHash = Self.hash(content)
    }

    public init(
        kind: ClipKind,
        content: String,
        contentHash: String,
        date: Date = .now,
        fileName: String? = nil,
        typeIdentifier: String? = nil,
        byteCount: Int? = nil,
        relativePath: String? = nil,
        thumbnailRelativePath: String? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.content = content
        self.createdAt = date
        self.updatedAt = date
        self.isPinned = false
        self.pinnedCategory = nil
        self.contentHash = contentHash
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.relativePath = relativePath
        self.thumbnailRelativePath = thumbnailRelativePath
    }

    // Refresh timestamp when the same content is copied again.
    public mutating func touch(at date: Date = .now) {
        updatedAt = date
    }

    public var title: String {
        switch kind {
        case .text:
            return content
        case .image:
            return fileName ?? "图片"
        case .file:
            return fileName ?? content
        }
    }

    public var searchableText: String {
        // Include recognizedText so OCR-scanned images become searchable by their content.
        [content, fileName, typeIdentifier, recognizedText]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    public static func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        return hash(data)
    }

    public static func hash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

private extension ClipItem {
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case content
        case createdAt
        case updatedAt
        case isPinned
        case pinnedCategory
        case recognizedText
        case contentHash
        case fileName
        case typeIdentifier
        case byteCount
        case relativePath
        case thumbnailRelativePath
    }
}

public extension ClipItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(ClipKind.self, forKey: .kind) ?? .text
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        pinnedCategory = try container.decodeIfPresent(String.self, forKey: .pinnedCategory)
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        typeIdentifier = try container.decodeIfPresent(String.self, forKey: .typeIdentifier)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        thumbnailRelativePath = try container.decodeIfPresent(String.self, forKey: .thumbnailRelativePath)
    }
}
