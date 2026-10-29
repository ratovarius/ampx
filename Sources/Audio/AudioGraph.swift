import AVFoundation

/// Owns the `AVAudioEngine` and an ordered chain of ``AudioEffectUnit``s wired between an
/// upstream node and the engine's main mixer:
///
///     upstream → effects[0] → … → effects[n] → mainMixer → output
///
/// The upstream is either a single source player node, or, in two-deck mode (DJ mode
/// Automix), a `deckSum` mixer fed by two ``AudioDeck``s. Adding a DSP module to the
/// pipeline is ``insert(_:at:)`` — the chain rewires itself, so there is no hand-edited
/// node wiring as the pipeline grows.
///
/// The engine is not thread-safe: every method must be called on the owning player's
/// serial audio queue. `@unchecked Sendable` reflects that single-queue discipline.
final class AudioGraph: @unchecked Sendable {
    let engine: AVAudioEngine
    private let singleSource: AVAudioPlayerNode?
    /// The two decks in two-deck mode; empty for a single-source graph.
    let decks: [AudioDeck]
    /// Sums the decks in two-deck mode; nil for a single-source graph.
    let deckSum: AVAudioMixerNode?
    private(set) var liveDeckIndex = 0
    private(set) var effects: [AudioEffectUnit] = []

    /// The playing source: the given node, or the live deck's player in two-deck mode.
    var source: AVAudioPlayerNode {
        self.decks.isEmpty ? self.singleSource! : self.decks[self.liveDeckIndex].player
    }

    var liveDeck: AudioDeck? {
        self.decks.isEmpty ? nil : self.decks[self.liveDeckIndex]
    }

    var idleDeck: AudioDeck? {
        self.decks.isEmpty ? nil : self.decks[1 - self.liveDeckIndex]
    }

    /// The node feeding the effect chain.
    private var upstream: AVAudioNode {
        self.deckSum ?? self.source
    }

    /// Node the analysis tap (FFT / visualizer) reads from — last effect output (post-EQ),
    /// or the upstream when the chain is empty. Intentionally not `mainMixerNode` so the
    /// listening fader can live on the mixer without changing analysis.
    var tapPoint: AVAudioNode {
        self.effects.last?.outputNode ?? self.upstream
    }

    var isRunning: Bool {
        self.engine.isRunning
    }

    init(engine: AVAudioEngine = AVAudioEngine(), source: AVAudioPlayerNode = AVAudioPlayerNode()) {
        self.engine = engine
        self.singleSource = source
        self.decks = []
        self.deckSum = nil
        self.engine.attach(source)
    }

    private init(twoDeckEngine engine: AVAudioEngine) {
        self.engine = engine
        self.singleSource = nil
        self.decks = [AudioDeck(), AudioDeck()]
        let deckSum = AVAudioMixerNode()
        self.deckSum = deckSum
        engine.attach(deckSum)
        for (bus, deck) in self.decks.enumerated() {
            deck.attach(to: engine)
            engine.connect(deck.fade, to: deckSum, fromBus: 0, toBus: AVAudioNodeBus(bus), format: nil)
        }
    }

    /// Two decks summed into the effect chain (DJ mode spec Revision 2 § Audio graph).
    static func twoDeck(engine: AVAudioEngine = AVAudioEngine()) -> AudioGraph {
        AudioGraph(twoDeckEngine: engine)
    }

    /// Makes deck `index` the live one: `source` follows it.
    func setLiveDeck(_ index: Int) {
        guard self.decks.indices.contains(index) else { return }
        self.liveDeckIndex = index
    }

    /// Attaches and connects the given effects in order, replacing any existing chain.
    func build(effects: [AudioEffectUnit]) {
        self.effects = effects
        for effect in effects {
            effect.attach(to: self.engine)
        }
        self.reconnect()
    }

    /// Inserts an effect at `index` (clamped) and rewires the chain.
    func insert(_ effect: AudioEffectUnit, at index: Int) {
        let clamped = min(max(index, 0), self.effects.count)
        effect.attach(to: self.engine)
        self.effects.insert(effect, at: clamped)
        self.reconnect()
    }

    /// Appends an effect to the end of the chain (before the main mixer).
    func append(_ effect: AudioEffectUnit) {
        self.insert(effect, at: self.effects.count)
    }

    /// Removes the effect with the given identifier (if present) and rewires the chain.
    @discardableResult
    func removeEffect(identifier: String) -> AudioEffectUnit? {
        guard let index = self.effects.firstIndex(where: { $0.identifier == identifier }) else {
            return nil
        }
        let effect = self.effects.remove(at: index)
        self.engine.disconnectNodeOutput(effect.outputNode)
        self.engine.disconnectNodeInput(effect.inputNode)
        self.reconnect()
        return effect
    }

    func effect(identifier: String) -> AudioEffectUnit? {
        self.effects.first { $0.identifier == identifier }
    }

    func start() throws {
        try self.engine.start()
    }

    /// Tears down the external connections of the chain and re-wires
    /// upstream → effects → mainMixer in the current order.
    ///
    /// Disconnecting an effect's *input* side and the *output* side of the previous stage
    /// leaves each effect's internal wiring (e.g. the EQ's preamp→eq link made in
    /// `attach(to:)`) intact, so a rebuild never has to know an effect's internals.
    private func reconnect() {
        self.engine.disconnectNodeOutput(self.upstream)
        for effect in self.effects {
            self.engine.disconnectNodeOutput(effect.outputNode)
            self.engine.disconnectNodeInput(effect.inputNode)
        }

        var upstream: AVAudioNode = self.upstream
        for effect in self.effects {
            self.engine.connect(upstream, to: effect.inputNode, format: nil)
            upstream = effect.outputNode
        }
        self.engine.connect(upstream, to: self.engine.mainMixerNode, format: nil)
    }
}
