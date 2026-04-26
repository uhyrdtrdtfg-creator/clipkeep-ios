import Foundation

public enum AppGroup {
    // Replace {yourname} with your Apple Developer Team prefix.
    public static let identifier = "group.app.clipkeep.ios"

    public static var defaults: UserDefaults {
        // Fall back to .standard so the keyboard never crashes, but data won't be shared.
        UserDefaults(suiteName: identifier) ?? .standard
    }

    public static var containerURL: URL {
        let manager = FileManager.default
        if let url = manager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }

        let fallback = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let url = fallback.appendingPathComponent("ClipKeep", isDirectory: true)
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var assetsDirectory: URL {
        let url = containerURL.appendingPathComponent("ClipAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
