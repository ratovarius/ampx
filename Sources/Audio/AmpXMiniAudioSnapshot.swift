import Foundation

/// A coherent audio window for one point on the mini visualizer's playout timeline.
struct AmpXMiniAudioSnapshot: Sendable {
    var sequence: UInt64 = 0
    var generation: UInt64 = 0
    var time: Double = 0
    var sampleRate: Double = 44100
    var spectrum: [Float] = Array(repeating: 0, count: 32)
    var waveformLeft: [Float] = []
    var waveformRight: [Float] = []
    var rms: SIMD2<Float> = .zero
    var peak: SIMD2<Float> = .zero
    var isPlaying: Bool = false
}
