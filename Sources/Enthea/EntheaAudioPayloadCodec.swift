import Foundation

/// Binary layout for Swift → JS audio pushes (base64 over `evaluateJavaScript`).
/// Order is fixed so `bridge.js` can decode by offset: 512×uint8 bins, then
/// 2048×float32 L, then 2048×float32 R (little-endian).
enum EntheaAudioPayloadCodec {
    static let binCount = 512
    static let waveCount = 2048

    static var payloadByteCount: Int {
        binCount + waveCount * MemoryLayout<Float>.size * 2
    }

    static func encode(bins: [UInt8], left: [Float], right: [Float]) -> String {
        var data = Data(capacity: Self.payloadByteCount)

        if bins.count >= Self.binCount {
            data.append(contentsOf: bins.prefix(Self.binCount))
        } else {
            data.append(contentsOf: bins)
            data.append(contentsOf: [UInt8](repeating: 0, count: Self.binCount - bins.count))
        }

        Self.appendFloats(Self.padded(left, count: Self.waveCount), to: &data)
        Self.appendFloats(Self.padded(right, count: Self.waveCount), to: &data)

        return data.base64EncodedString()
    }

    static func decode(_ base64: String) -> (bins: [UInt8], left: [Float], right: [Float])? {
        guard let data = Data(base64Encoded: base64), data.count == Self.payloadByteCount else {
            return nil
        }

        let bins = [UInt8](data.prefix(Self.binCount))
        let leftStart = Self.binCount
        let rightStart = leftStart + Self.waveCount * MemoryLayout<Float>.size
        let left = Self.readFloats(data, start: leftStart, count: Self.waveCount)
        let right = Self.readFloats(data, start: rightStart, count: Self.waveCount)
        return (bins, left, right)
    }

    private static func padded(_ values: [Float], count: Int) -> [Float] {
        if values.count >= count {
            return Array(values.prefix(count))
        }
        return values + [Float](repeating: 0, count: count - values.count)
    }

    private static func appendFloats(_ values: [Float], to data: inout Data) {
        values.withUnsafeBufferPointer { buffer in
            let raw = UnsafeRawBufferPointer(buffer)
            data.append(contentsOf: raw)
        }
    }

    private static func readFloats(_ data: Data, start: Int, count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        let byteCount = count * MemoryLayout<Float>.size
        result.withUnsafeMutableBytes { dest in
            _ = data.copyBytes(to: dest, from: start ..< (start + byteCount))
        }
        return result
    }
}
