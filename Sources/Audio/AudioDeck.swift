import AVFoundation

/// One deck of the two-deck graph (DJ mode spec Revision 2 § Audio graph):
///
///     player → timePitch → lowCut → fade → deckSum
///
/// ReplayGain stays on `player.volume`; the blend envelope lives on `fade` (two gain stages). At rate 1 with no cut,
/// both units are bypassed. Touched only on the owning player's audio queue, like the rest of the graph.
final class AudioDeck: @unchecked Sendable {
    static let lowCutFrequency: Float = 150

    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    let lowCut = AVAudioUnitEQ(numberOfBands: 1)
    let fade = AVAudioMixerNode()

    init() {
        let band = self.lowCut.bands[0]
        band.filterType = .highPass
        band.frequency = Self.lowCutFrequency
        band.bypass = false
        self.reset()
    }

    func attach(to engine: AVAudioEngine) {
        for node in [self.player, self.timePitch, self.lowCut, self.fade] as [AVAudioNode] {
            engine.attach(node)
        }
        engine.connect(self.player, to: self.timePitch, format: nil)
        engine.connect(self.timePitch, to: self.lowCut, format: nil)
        engine.connect(self.lowCut, to: self.fade, format: nil)
    }

    func setRate(_ rate: Float) {
        self.timePitch.rate = rate
        self.timePitch.bypass = rate == 1
    }

    func setLowCut(_ on: Bool) {
        self.lowCut.bypass = !on
    }

    /// Rate 1, no cut, full level.
    func reset() {
        self.setRate(1)
        self.setLowCut(false)
        self.fade.outputVolume = 1
    }
}
