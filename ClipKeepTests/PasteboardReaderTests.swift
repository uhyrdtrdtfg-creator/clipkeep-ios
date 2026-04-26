import XCTest
import UIKit
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

    func testReadsImageBeforeString() throws {
        let image = try makeTestImage()
        let mock = MockPasteboard(changeCount: 5, string: "fallback")
        mock.hasImages = true
        mock.image = image
        let reader = PasteboardReader(pasteboard: mock, readsInitialValue: true)

        let clip = reader.readClipIfChanged()
        XCTAssertEqual(clip?.kind, .image)
        XCTAssertNotNil(clip?.data)
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

private func makeTestImage() throws -> UIImage {
    let data = Data([255, 0, 0, 255])
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let cgImage = try XCTUnwrap(CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
    return UIImage(cgImage: cgImage)
}

private final class MockPasteboard: PasteboardProtocol {
    var changeCount: Int
    var hasStrings: Bool
    var hasImages = false
    var image: UIImage?
    var hasURLs = false
    var url: URL?
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
