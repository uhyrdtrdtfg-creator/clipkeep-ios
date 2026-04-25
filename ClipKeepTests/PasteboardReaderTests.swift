import XCTest
@testable import ClipKeepCore

final class PasteboardReaderTests: XCTestCase {
    func testNoReadWhenCountUnchanged() {
        let mock = MockPasteboard(changeCount: 5, string: "secret")
        let reader = PasteboardReader(pasteboard: mock)
        // Count stays at 5 – should not surface anything.
        XCTAssertNil(reader.readIfChanged())
    }

    func testReadsWhenCountAdvances() {
        let mock = MockPasteboard(changeCount: 5, string: "hello")
        let reader = PasteboardReader(pasteboard: mock)
        mock.changeCount = 6
        XCTAssertEqual(reader.readIfChanged(), "hello")
    }

    func testSecondCallWithSameCountReturnsNil() {
        let mock = MockPasteboard(changeCount: 5, string: "hello")
        let reader = PasteboardReader(pasteboard: mock)
        mock.changeCount = 6
        _ = reader.readIfChanged()
        // Count unchanged after first read.
        XCTAssertNil(reader.readIfChanged())
    }

    func testCanReadInitialValueWhenRequested() {
        let mock = MockPasteboard(changeCount: 5, string: "hello")
        let reader = PasteboardReader(pasteboard: mock, readsInitialValue: true)

        XCTAssertEqual(reader.readIfChanged(), "hello")
        XCTAssertNil(reader.readIfChanged())
    }

    func testPersistsLastSeenChangeCount() throws {
        let suiteName = "pasteboard-reader.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mock = MockPasteboard(changeCount: 5, string: "hello")
        let reader = PasteboardReader(pasteboard: mock, defaults: defaults, readsInitialValue: true)
        XCTAssertEqual(reader.readIfChanged(), "hello")

        let nextReader = PasteboardReader(pasteboard: mock, defaults: defaults, readsInitialValue: true)
        XCTAssertNil(nextReader.readIfChanged())
    }

    func testDoesNotReadStringWhenNoStringTypeExists() {
        let mock = MockPasteboard(changeCount: 5, string: nil)
        mock.hasStrings = false
        let reader = PasteboardReader(pasteboard: mock, readsInitialValue: true)

        XCTAssertNil(reader.readIfChanged())
        XCTAssertEqual(mock.stringReadCount, 0)
    }
}

private final class MockPasteboard: PasteboardProtocol {
    var changeCount: Int
    var hasStrings: Bool
    var stringReadCount = 0
    private var backingString: String?

    var string: String? {
        stringReadCount += 1
        return backingString
    }

    init(changeCount: Int, string: String?) {
        self.changeCount = changeCount
        self.hasStrings = string != nil
        self.backingString = string
    }
}
