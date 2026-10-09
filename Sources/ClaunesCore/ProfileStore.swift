import Foundation

public enum ProfileStoreError: Error, LocalizedError {
    case duplicateName(String)
    case notFound(UUID)
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .duplicateName(let n): return "A Claune named \"\(n)\" already exists."
        case .notFound(let id): return "No Claune with id \(id)."
        case .emptyName: return "The name must not be empty."
        }
    }
}

/// Reads and writes profiles.json. Thread-confined to the caller; the app uses it on the main actor.
public final class ProfileStore {
    public let paths: ClaunesPaths
    public private(set) var document: ProfilesDocument

    public init(paths: ClaunesPaths) throws {
        self.paths = paths
        self.document = try ProfileStore.load(from: paths.profilesFile)
    }

    public var claunes: [Claune] { document.claunes }

    public func claune(id: UUID) -> Claune? { document.claunes.first { $0.id == id } }

    private static func load(from url: URL) throws -> ProfilesDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return ProfilesDocument() }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfilesDocument.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: paths.supportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try data.write(to: paths.profilesFile, options: .atomic)
    }

    public func reload() throws { document = try ProfileStore.load(from: paths.profilesFile) }

    @discardableResult
    public func add(name: String, colorHex: String? = nil, badge: String? = nil) throws -> Claune {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileStoreError.emptyName }
        guard !document.claunes.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw ProfileStoreError.duplicateName(trimmed)
        }
        let color = colorHex ?? Claune.palette[document.claunes.count % Claune.palette.count]
        let claune = Claune(name: trimmed, colorHex: color, badge: badge)
        document.claunes.append(claune)
        try save()
        return claune
    }

    public func update(_ claune: Claune) throws {
        guard let idx = document.claunes.firstIndex(where: { $0.id == claune.id }) else {
            throw ProfileStoreError.notFound(claune.id)
        }
        let trimmed = claune.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileStoreError.emptyName }
        if document.claunes.contains(where: { $0.id != claune.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw ProfileStoreError.duplicateName(trimmed)
        }
        var c = claune
        c.name = trimmed
        if c.badge.trimmingCharacters(in: .whitespaces).isEmpty { c.badge = Claune.defaultBadge(for: trimmed) }
        document.claunes[idx] = c
        try save()
    }

    public func remove(id: UUID) throws {
        guard document.claunes.contains(where: { $0.id == id }) else { throw ProfileStoreError.notFound(id) }
        document.claunes.removeAll { $0.id == id }
        try save()
    }

    public func setMigrationOfferShown() throws {
        document.migrationOfferShown = true
        try save()
    }
}
