import CryptoKit
import Foundation

/// Content fingerprint used to confirm renames (spec: `contentFingerprint`).
/// SHA-256 over the file size as 8-byte little-endian, the first `min(64 KiB, size)` bytes and the last
/// `min(64 KiB, size)` bytes. Small files hash overlapping bytes twice; that is part of the definition.
enum LibraryFingerprint {
    static let sampleLength = 65536

    static func read(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let sample = Int(min(size, UInt64(self.sampleLength)))

        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        try hasher.update(data: self.read(handle, at: 0, count: sample))
        try hasher.update(data: self.read(handle, at: size - UInt64(sample), count: sample))
        return Data(hasher.finalize())
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}
