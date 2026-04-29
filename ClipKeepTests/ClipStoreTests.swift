import XCTest
@testable import ClipKeepCore

final class ClipStoreTests: XCTestCase {
    private var store: ClipStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var assetsDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "test.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        assetsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipstore-tests-\(UUID().uuidString)", isDirectory: true)
        store = ClipStore(defaults: defaults, assetsDirectory: assetsDirectory)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: assetsDirectory)
        try super.tearDownWithError()
    }

    func testAddAndLoad() {
        store.add("hello")
        let items = store.load()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content, "hello")
    }

    func testDeduplicate() {
        store.add("hello")
        store.add("hello")
        XCTAssertEqual(store.load().count, 1)
    }

    func testDeleteById() {
        store.add("a")
        store.add("b")
        let id = store.load()[0].id
        store.delete(id: id)
        XCTAssertEqual(store.load().count, 1)
    }

    func testTogglePin() {
        store.add("pinme")
        let id = store.load()[0].id
        store.togglePin(id: id)
        XCTAssertTrue(store.load()[0].isPinned)
        store.togglePin(id: id)
        XCTAssertFalse(store.load()[0].isPinned)
    }

    func testClearUnpinnedKeepsPinned() {
        store.add("keep")
        let id = store.load()[0].id
        store.togglePin(id: id)
        store.add("remove")
        store.clearUnpinned()
        let items = store.load()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content, "keep")
    }

    func testPinnedItemsStayInRecencyOrder() {
        store.add("older")
        let olderID = store.load()[0].id
        Thread.sleep(forTimeInterval: 0.02)
        store.add("newer")

        store.togglePin(id: olderID)

        let items = store.load()
        XCTAssertEqual(items.map(\.content), ["newer", "older"])
        XCTAssertTrue(items[1].isPinned)
    }

    func testCapacityLimit() {
        store.setMaxCount(3)
        for i in 0..<5 { store.add("item \(i)") }
        XCTAssertEqual(store.load().count, 3)
    }

    func testIgnoresWhitespaceOnly() {
        store.add("   \n")
        XCTAssertTrue(store.load().isEmpty)
    }

    func testAddImageAsset() throws {
        let data = Data([0, 1, 2, 3])
        store.add(CapturedClip(
            kind: .image,
            content: "图片",
            data: data,
            fileName: "sample.png",
            typeIdentifier: "public.png"
        ))

        let item = try XCTUnwrap(store.load().first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.byteCount, data.count)
        let url = try XCTUnwrap(store.assetURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteRemovesAsset() throws {
        store.add(CapturedClip(
            kind: .file,
            content: "sample.txt",
            data: Data("hello".utf8),
            fileName: "sample.txt",
            typeIdentifier: "public.plain-text"
        ))

        let item = try XCTUnwrap(store.load().first)
        let url = try XCTUnwrap(store.assetURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        store.delete(id: item.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
