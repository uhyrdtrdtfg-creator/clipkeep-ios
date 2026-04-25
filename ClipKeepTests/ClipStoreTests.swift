import XCTest
@testable import ClipKeepCore

final class ClipStoreTests: XCTestCase {
    private var store: ClipStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        store = ClipStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
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

    func testCapacityLimit() {
        store.setMaxCount(3)
        for i in 0..<5 { store.add("item \(i)") }
        XCTAssertEqual(store.load().count, 3)
    }

    func testIgnoresWhitespaceOnly() {
        store.add("   \n")
        XCTAssertTrue(store.load().isEmpty)
    }
}
