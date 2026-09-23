@testable import AmpX
import AVFoundation
import XCTest

final class AudioGraphTests: XCTestCase {
    /// Minimal single-node passthrough effect (input == output) for wiring tests.
    private final class PassthroughEffect: AudioEffectUnit, @unchecked Sendable {
        let identifier: String
        let mixer = AVAudioMixerNode()
        var inputNode: AVAudioNode {
            self.mixer
        }

        var outputNode: AVAudioNode {
            self.mixer
        }

        init(identifier: String) {
            self.identifier = identifier
        }

        func attach(to engine: AVAudioEngine) {
            engine.attach(self.mixer)
        }
    }

    private func feeds(_ engine: AVAudioEngine, from source: AVAudioNode, into target: AVAudioNode) -> Bool {
        engine.outputConnectionPoints(for: source, outputBus: 0).contains { $0.node === target }
    }

    func testTapPointIsSourceWhenEffectChainEmpty() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        XCTAssertTrue(graph.effects.isEmpty)
        XCTAssertTrue(graph.tapPoint === graph.source)
        XCTAssertFalse(graph.tapPoint === engine.mainMixerNode)
    }

    func testTapPointIsLastEffectOutputWhenChainBuilt() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        let eq = EQAudioEffect()
        graph.build(effects: [eq])
        XCTAssertTrue(graph.tapPoint === eq.outputNode)
        XCTAssertFalse(graph.tapPoint === engine.mainMixerNode)
    }

    func testTapPointFollowsLastEffectAfterAppend() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        let eq = EQAudioEffect()
        let extra = PassthroughEffect(identifier: "test.passthrough")
        graph.build(effects: [eq])
        graph.append(extra)
        XCTAssertTrue(graph.tapPoint === extra.outputNode)
    }

    func testBuildConnectsSourceThroughEffectToMainMixer() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        let eq = EQAudioEffect()
        graph.build(effects: [eq])

        XCTAssertEqual(graph.effects.count, 1)
        XCTAssertTrue(self.feeds(engine, from: graph.source, into: eq.inputNode))
        XCTAssertTrue(self.feeds(engine, from: eq.outputNode, into: engine.mainMixerNode))
    }

    func testAppendRewiresChainInOrder() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        let eq = EQAudioEffect()
        let extra = PassthroughEffect(identifier: "test.passthrough")
        graph.build(effects: [eq])
        graph.append(extra)

        XCTAssertEqual(graph.effects.map(\.identifier), ["ampx.eq", "test.passthrough"])
        // source → eq → extra → mainMixer
        XCTAssertTrue(self.feeds(engine, from: graph.source, into: eq.inputNode))
        XCTAssertTrue(self.feeds(engine, from: eq.outputNode, into: extra.inputNode))
        XCTAssertTrue(self.feeds(engine, from: extra.outputNode, into: engine.mainMixerNode))
    }

    func testInsertAtFrontPutsEffectFirst() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        let eq = EQAudioEffect()
        let head = PassthroughEffect(identifier: "head")
        graph.build(effects: [eq])
        graph.insert(head, at: 0)

        XCTAssertEqual(graph.effects.map(\.identifier), ["head", "ampx.eq"])
        XCTAssertTrue(self.feeds(engine, from: graph.source, into: head.inputNode))
        XCTAssertTrue(self.feeds(engine, from: head.outputNode, into: eq.inputNode))
    }

    func testRemoveEffectReconnectsRemainingChain() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        let eq = EQAudioEffect()
        let extra = PassthroughEffect(identifier: "extra")
        graph.build(effects: [eq, extra])

        let removed = graph.removeEffect(identifier: "extra")
        XCTAssertEqual(removed?.identifier, "extra")
        XCTAssertEqual(graph.effects.map(\.identifier), ["ampx.eq"])
        // eq now feeds the main mixer directly again.
        XCTAssertTrue(self.feeds(engine, from: eq.outputNode, into: engine.mainMixerNode))
    }

    func testRemoveAllEffectsConnectsSourceToMainMixer() {
        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine)
        graph.build(effects: [EQAudioEffect()])

        graph.removeEffect(identifier: "ampx.eq")
        XCTAssertTrue(graph.effects.isEmpty)
        XCTAssertTrue(self.feeds(engine, from: graph.source, into: engine.mainMixerNode))
        XCTAssertTrue(graph.tapPoint === graph.source)
    }

    func testEffectLookupByIdentifier() {
        let graph = AudioGraph()
        let eq = EQAudioEffect()
        graph.build(effects: [eq])
        XCTAssertTrue(graph.effect(identifier: "ampx.eq") === eq)
        XCTAssertNil(graph.effect(identifier: "missing"))
    }

    func testRemoveUnknownEffectIsNoOp() {
        let graph = AudioGraph()
        graph.build(effects: [EQAudioEffect()])
        XCTAssertNil(graph.removeEffect(identifier: "nope"))
        XCTAssertEqual(graph.effects.count, 1)
    }
}
