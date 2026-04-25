import Foundation

public enum AppGroup {
    // Replace {yourname} with your Apple Developer Team prefix.
    public static let identifier = "group.app.clipkeep.ios"

    public static var defaults: UserDefaults {
        // Fall back to .standard so the keyboard never crashes, but data won't be shared.
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
