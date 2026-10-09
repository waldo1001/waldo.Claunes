import Foundation

/// One profile ("Claune"). Persisted in profiles.json.
public struct Claune: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    /// Hex color like "#2E7D32".
    public var colorHex: String
    /// One letter or emoji shown on the icon and in the menu bar.
    public var badge: String
    public var createdAt: Date
    /// Version of Claude Desktop the Claune's bundle was generated from (nil = never generated).
    public var generatedFromVersion: String?

    public init(id: UUID = UUID(), name: String, colorHex: String, badge: String? = nil,
                createdAt: Date = Date(), generatedFromVersion: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.badge = badge ?? Claune.defaultBadge(for: name)
        self.createdAt = createdAt
        self.generatedFromVersion = generatedFromVersion
    }

    public static func defaultBadge(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "C" }
        return String(first).uppercased()
    }

    /// Bundle identifier of the generated app. Based on the UUID, so renaming keeps
    /// macOS permissions (TCC) and preferences attached to the Claune.
    public var bundleIdentifier: String {
        "be.waldo.claunes.profile." + id.uuidString.lowercased()
    }

    /// Name of the app bundle in ~/Applications/Claunes. Filesystem-safe version of the name.
    public var appFileName: String {
        let bad = CharacterSet(charactersIn: "/:\\\u{0}")
        let cleaned = name.unicodeScalars.map { bad.contains($0) ? "-" : Character($0) }
        let s = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.isEmpty ? "Claune" : s) + ".app"
    }

    public static let palette: [String] = [
        "#CC785C", "#2E7D32", "#1565C0", "#6A1B9A", "#C62828", "#EF6C00", "#00838F", "#4E342E", "#37474F", "#AD1457",
    ]
}

/// The on-disk document.
public struct ProfilesDocument: Codable, Equatable {
    public var version: Int
    public var claunes: [Claune]
    /// Set once the first-run migration offer was shown (accepted or declined).
    public var migrationOfferShown: Bool

    public init(version: Int = 1, claunes: [Claune] = [], migrationOfferShown: Bool = false) {
        self.version = version
        self.claunes = claunes
        self.migrationOfferShown = migrationOfferShown
    }
}
