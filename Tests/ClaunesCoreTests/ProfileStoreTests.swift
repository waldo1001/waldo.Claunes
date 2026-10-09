import XCTest
@testable import ClaunesCore

final class ProfileStoreTests: XCTestCase {
    var root: URL!
    var paths: ClaunesPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claunes-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = ClaunesPaths(supportDir: root.appendingPathComponent("support"), applicationsDir: root.appendingPathComponent("apps"),
                             claudeApp: root.appendingPathComponent("Claude.app"), originalClaudeData: root.appendingPathComponent("orig"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testAddPersistsAndReloads() throws {
        let store = try ProfileStore(paths: paths)
        let c = try store.add(name: "Work")
        XCTAssertEqual(c.badge, "W")
        XCTAssertEqual(c.colorHex, Claune.palette[0])
        let again = try ProfileStore(paths: paths)
        XCTAssertEqual(again.claunes.map(\.id), [c.id])
        XCTAssertEqual(again.claunes.first?.name, "Work")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.profilesFile.path))
    }

    func testDuplicateNameIsRejectedCaseInsensitively() throws {
        let store = try ProfileStore(paths: paths)
        _ = try store.add(name: "Work")
        XCTAssertThrowsError(try store.add(name: "work"))
        XCTAssertThrowsError(try store.add(name: "   "))
    }

    func testUpdateAndRemove() throws {
        let store = try ProfileStore(paths: paths)
        var c = try store.add(name: "Work")
        c.name = "Personal"; c.colorHex = "#123456"; c.badge = ""
        try store.update(c)
        XCTAssertEqual(store.claunes.first?.name, "Personal")
        XCTAssertEqual(store.claunes.first?.badge, "P", "empty badge falls back to the initial")
        try store.remove(id: c.id)
        XCTAssertTrue(store.claunes.isEmpty)
        XCTAssertThrowsError(try store.remove(id: c.id))
    }

    func testBundleIdentifierIsStableAcrossRename() throws {
        var c = Claune(name: "Work", colorHex: "#000000")
        let before = c.bundleIdentifier
        c.name = "Other"
        XCTAssertEqual(c.bundleIdentifier, before)
        XCTAssertTrue(before.hasPrefix("be.waldo.claunes.profile."))
    }

    func testAppFileNameIsFilesystemSafe() {
        XCTAssertEqual(Claune(name: "A/B:C", colorHex: "#000000").appFileName, "A-B-C.app")
        XCTAssertEqual(Claune(name: "  ", colorHex: "#000000").appFileName, "Claune.app")
        XCTAssertEqual(Claune(name: "Work 🚀", colorHex: "#000000").badge, "W")
    }

    func testDataDirIsPerClauneUnderSupportDir() {
        let c = Claune(name: "Work", colorHex: "#000000")
        XCTAssertEqual(paths.dataDir(for: c).path, paths.supportDir.appendingPathComponent(c.id.uuidString.lowercased()).path)
    }
}
