@testable import AmpX
import XCTest

final class EntheaAudioPayloadCodecTests: XCTestCase {
    func testEncodedBlobRoundTripsBinsAndWaveforms() {
        var bins = [UInt8](repeating: 0, count: EntheaAudioPayloadCodec.binCount)
        bins[0] = 255
        bins[100] = 128
        bins[511] = 1

        var left = [Float](repeating: 0, count: EntheaAudioPayloadCodec.waveCount)
        var right = [Float](repeating: 0, count: EntheaAudioPayloadCodec.waveCount)
        left[0] = -1
        left[2047] = 0.5
        right[10] = 0.25
        right[1000] = -0.75

        let blob = EntheaAudioPayloadCodec.encode(bins: bins, left: left, right: right)
        guard let decoded = EntheaAudioPayloadCodec.decode(blob) else {
            return XCTFail("decode failed")
        }

        XCTAssertEqual(decoded.bins, bins)
        XCTAssertEqual(decoded.left.count, EntheaAudioPayloadCodec.waveCount)
        XCTAssertEqual(decoded.right.count, EntheaAudioPayloadCodec.waveCount)
        XCTAssertEqual(decoded.left[0], -1, accuracy: 0.0001)
        XCTAssertEqual(decoded.left[2047], 0.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.right[10], 0.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.right[1000], -0.75, accuracy: 0.0001)
    }

    func testEncodedBlobLayoutIsStable() throws {
        var bins = [UInt8](repeating: 0, count: EntheaAudioPayloadCodec.binCount)
        bins[0] = 42
        let left = [Float](repeating: 1.5, count: EntheaAudioPayloadCodec.waveCount)
        let right = [Float](repeating: -2.5, count: EntheaAudioPayloadCodec.waveCount)

        let data = try XCTUnwrap(Data(base64Encoded: EntheaAudioPayloadCodec.encode(bins: bins, left: left, right: right)))
        XCTAssertEqual(data.count, EntheaAudioPayloadCodec.binCount + EntheaAudioPayloadCodec.waveCount * 8)
        XCTAssertEqual(data[0], 42)

        let leftStart = EntheaAudioPayloadCodec.binCount
        var left0: Float = 0
        _ = withUnsafeMutableBytes(of: &left0) { dest in
            data.copyBytes(to: dest, from: leftStart ..< (leftStart + 4))
        }
        XCTAssertEqual(left0, 1.5, accuracy: 0.0001)

        let rightStart = leftStart + EntheaAudioPayloadCodec.waveCount * 4
        var right0: Float = 0
        _ = withUnsafeMutableBytes(of: &right0) { dest in
            data.copyBytes(to: dest, from: rightStart ..< (rightStart + 4))
        }
        XCTAssertEqual(right0, -2.5, accuracy: 0.0001)
    }

    func testEncodePadsAndTruncatesToFixedSizes() throws {
        let blob = EntheaAudioPayloadCodec.encode(
            bins: [1, 2, 3],
            left: [0.1],
            right: Array(repeating: 0.2, count: 3000)
        )
        let decoded = try XCTUnwrap(EntheaAudioPayloadCodec.decode(blob))
        XCTAssertEqual(decoded.bins.count, 512)
        XCTAssertEqual(decoded.bins[0], 1)
        XCTAssertEqual(decoded.bins[2], 3)
        XCTAssertEqual(decoded.bins[3], 0)
        XCTAssertEqual(decoded.left.count, 2048)
        XCTAssertEqual(decoded.right.count, 2048)
        XCTAssertEqual(decoded.left[0], 0.1, accuracy: 0.0001)
        XCTAssertEqual(decoded.right[0], 0.2, accuracy: 0.0001)
    }
}
