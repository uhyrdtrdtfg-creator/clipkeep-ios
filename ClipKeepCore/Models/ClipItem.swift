import Foundation
import CryptoKit

public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public let contentHash: String

    public init(content: String, date: Date = .now) {
        self.id = UUID()
        self.content = content
        self.createdAt = date
        self.updatedAt = date
        self.isPinned = false
        self.contentHash = Self.hash(content)
    }

    // Refresh timestamp when the same content is copied again.
    public mutating func touch(at date: Date = .now) {
        updatedAt = date
    }

    static func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
