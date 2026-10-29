@testable import AmpX
import AVFoundation
import XCTest

/// DJ mode spec Revision 2 § Audio graph: two decks summed into the unchanged effect chain.
final class AudioGraphDeckTests: XCTestCase {
    private func feeds(_ engine: AVAudioEngine, from source: AVAudioNode, into target: AVAudioNode) -> Bool {
        engine.outputConnectionPoints(for: source, outputBus: 0).contains { $0.node === target }
    }

    func testTwoDeckChainFeedsDeckSumIntoFirstEffect() throws {
        let engine = AVAudioEngine()
        let graph = AudioGraph.twoDeck(engine: engine)
        let eq = EQAudioEffect()
        graph.build(effects: [eq])
        XCTAssertEqual(graph.decks.count, 2)
        let deckSum = try XCTUnwrap(graph.deckSum)
        for deck in graph.decks {
            XCTAssertTrue(self.feeds(engine, from: deck.player, into: deck.timePitch))
            XCTAssertTrue(self.feeds(engine, from: deck.timePitch, into: deck.lowCut))
            XCTAssertTrue(self.feeds(engine, from: deck.lowCut, into: deck.fade))
            XCTAssertTrue(self.feeds(engine, from: deck.fade, into: deckSum))
        }
        XCTAssertTrue(self.feeds(engine, from: deckSum, into: eq.inputNode))
        XCTAssertFalse(self.feeds(engine, from: graph.source, into: eq.inputNode))
    }

    func testTwoDeckTapPointIsLastEffect() {
        let graph = AudioGraph.twoDeck(engine: AVAudioEngine())
        let eq = EQAudioEffect()
        graph.build(effects: [eq])
        XCTAssertTrue(graph.tapPoint === eq.outputNode)
    }

    func testTwoDeckEmptyChainTapIsDeckSum() throws {
        let engine = AVAudioEngine()
        let graph = AudioGraph.twoDeck(engine: engine)
        graph.build(effects: [])
        XCTAssertTrue(graph.tapPoint === (try XCTUnwrap(graph.deckSum)))
        XCTAssertTrue(self.feeds(engine, from: try XCTUnwrap(graph.deckSum), into: engine.mainMixerNode))
    }

    func testSourceFollowsLiveDeck() {
        let graph = AudioGraph.twoDeck(engine: AVAudioEngine())
        XCTAssertEqual(graph.liveDeckIndex, 0)
        XCTAssertTrue(graph.source === graph.decks[0].player)
        graph.setLiveDeck(1)
        XCTAssertTrue(graph.source === graph.decks[1].player)
        XCTAssertTrue(graph.idleDeck === graph.decks[0])
    }

    func testDeckResetRestoresUnityAndBypass() {
        let deck = AudioGraph.twoDeck(engine: AVAudioEngine()).decks[0]
        deck.setRate(1.04)
        deck.setLowCut(true)
        deck.fade.outputVolume = 0.2
        deck.reset()
        XCTAssertEqual(deck.timePitch.rate, 1)
        XCTAssertTrue(deck.timePitch.bypass)
        XCTAssertTrue(deck.lowCut.bypass)
        XCTAssertEqual(deck.fade.outputVolume, 1)
    }

    func testRateOneBypassesTimePitch() {
        let deck = AudioGraph.twoDeck(engine: AVAudioEngine()).decks[1]
        deck.setRate(1.03)
        XCTAssertFalse(deck.timePitch.bypass)
        XCTAssertEqual(deck.timePitch.rate, 1.03, accuracy: 1e-6)
        deck.setRate(1)
        XCTAssertTrue(deck.timePitch.bypass)
        deck.setLowCut(true)
        XCTAssertFalse(deck.lowCut.bypass)
        XCTAssertEqual(deck.lowCut.bands[0].filterType, .highPass)
        XCTAssertEqual(deck.lowCut.bands[0].frequency, 150)
    }
}
