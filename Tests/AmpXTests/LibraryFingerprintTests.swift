@testable import AmpX
import CryptoKit
import XCTest

final class LibraryFingerprintTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.directory)
    }

    func testEmptyFile() throws {
        try self.assertFingerprint(of: [])
    }

    func testSeventeenBytes() throws {
        try self.assertFingerprint(of: self.bytes(17))
    }

    func testExactly128KiB() throws {
        try self.assertFingerprint(of: self.bytes(131_072))
    }

    func testOverlappingHeadTail() throws {
        try self.assertFingerprint(of: self.bytes(102_400))
    }

    func testLargeFile() throws {
        try self.assertFingerprint(of: self.bytes(1_048_576))
    }

    func testChangedHeadChangesDigest() throws {
        var bytes = self.bytes(1_048_576)
        let original = try LibraryFingerprint.read(from: self.write(bytes))
        bytes[10] &+= 1
        XCTAssertNotEqual(try LibraryFingerprint.read(from: self.write(bytes)), original)
    }

    func testChangedTailChangesDigest() throws {
        var bytes = self.bytes(1_048_576)
        let original = try LibraryFingerprint.read(from: self.write(bytes))
        bytes[bytes.count - 10] &+= 1
        XCTAssertNotEqual(try LibraryFingerprint.read(from: self.write(bytes)), original)
    }

    func testMiddleChangeIsInvisible() throws {
        // Documents the spec's accepted limitation: only size + head/tail are sampled.
        var bytes = self.bytes(1_048_576)
        let original = try LibraryFingerprint.read(from: self.write(bytes))
        bytes[bytes.count / 2] &+= 1
        XCTAssertEqual(try LibraryFingerprint.read(from: self.write(bytes)), original)
    }

    func testDeterministic() throws {
        let url = try self.write(self.bytes(200_000))
        XCTAssertEqual(try LibraryFingerprint.read(from: url), try LibraryFingerprint.read(from: url))
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try LibraryFingerprint.read(from: self.directory.appendingPathComponent("missing.mp3")))
    }

    // MARK: - Helpers

    private func assertFingerprint(of bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try self.write(bytes)
        XCTAssertEqual(try LibraryFingerprint.read(from: url), Self.expected(bytes), file: file, line: line)
    }

    /// The spec's definition: SHA-256 over size (8-byte LE), first min(64 KiB, size) bytes, last min(64 KiB, size) bytes.
    private static func expected(_ bytes: [UInt8]) -> Data {
        var hasher = SHA256()
        withUnsafeBytes(of: UInt64(bytes.count).littleEndian) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(bytes.prefix(65536)))
        hasher.update(data: Data(bytes.suffix(65536)))
        return Data(hasher.finalize())
    }

    private func bytes(_ count: Int) -> [UInt8] {
        (0 ..< count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) }
    }

    private func write(_ bytes: [UInt8]) throws -> URL {
        let url = self.directory.appendingPathComponent("\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }
}
