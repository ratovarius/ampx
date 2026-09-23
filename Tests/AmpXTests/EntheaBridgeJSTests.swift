@testable import AmpX
import JavaScriptCore
import XCTest

final class EntheaBridgeJSTests: XCTestCase {
    func testSetTimelineNullResetsAudioSourceToWinamp() throws {
        let ctx = try Self.makeBridgeContext()
        ctx.evaluateScript("winampAudio.setTimeline({dur:120,drops:[8],sections:[{t:0,energy:1}]})")
        XCTAssertEqual(Self.string(ctx, "S.audio.source"), "file")

        ctx.evaluateScript("winampAudio.setTimeline(null)")
        XCTAssertEqual(
            Self.string(ctx, "S.audio.source"),
            "winamp",
            "clearing the timeline must restore the host analyser path"
        )
        XCTAssertEqual(Self.string(ctx, "String(S.timeline)"), "null")
    }

    func testPushRevertsAudioSourceToWinampWhenTimelineIsGone() throws {
        let ctx = try Self.makeBridgeContext()
        let blob = EntheaAudioPayloadCodec.encode(bins: [], left: [], right: [])
        ctx.evaluateScript("winampAudio.push('\(blob)',44100,true)")
        XCTAssertEqual(Self.string(ctx, "S.audio.source"), "winamp")
        XCTAssertEqual(Self.string(ctx, "String(!!AUDIO._winampShim)"), "true")

        ctx.evaluateScript("winampAudio.setTimeline({dur:120,drops:[8],sections:[]})")
        XCTAssertEqual(Self.string(ctx, "S.audio.source"), "file")

        // Leave source on "file" while dropping the map — the state a host
        // audio push must repair even if setTimeline(null) forgot to.
        ctx.evaluateScript("S.timeline = null")
        ctx.evaluateScript("winampAudio.push('\(blob)',44100,true)")
        XCTAssertEqual(
            Self.string(ctx, "S.audio.source"),
            "winamp",
            "push must revert to winamp when no native timeline is loaded"
        )
    }

    func testSetRenderPausedRestoresAudioOnWhenResuming() throws {
        let ctx = try Self.makeBridgeContext()
        let blob = EntheaAudioPayloadCodec.encode(bins: [], left: [], right: [])
        ctx.evaluateScript("winampAudio.push('\(blob)',44100,true)")
        XCTAssertEqual(Self.string(ctx, "String(!!S.audio.on)"), "true")

        ctx.evaluateScript("winampEnthea.setRenderPaused(true)")
        XCTAssertEqual(
            Self.string(ctx, "String(!!S.audio.on)"),
            "false",
            "pause must disable ENTHEA audio analysis"
        )

        ctx.evaluateScript("winampEnthea.setRenderPaused(false)")
        XCTAssertEqual(
            Self.string(ctx, "String(!!S.audio.on)"),
            "true",
            "resume must restore audio.on before the next push so updateAudio does not early-return"
        )
    }

    private static func string(_ ctx: JSContext, _ expr: String) -> String {
        ctx.evaluateScript(expr)?.toString() ?? ""
    }

    private static func makeBridgeContext() throws -> JSContext {
        let ctx = JSContext()!
        ctx.evaluateScript(
            """
            var window = this;
            window.addEventListener = function () {};
            var document = {
              body: { classList: { add: function () {} } },
              getElementById: function () { return null; }
            };
            var AUDIO = {};
            var S = { audio: { on: false, source: "mic" }, flicker: false, timeline: null };
            """
        )
        if ctx.objectForKeyedSubscript("atob")?.isUndefined != false {
            let atob: @convention(block) (String) -> String = { b64 in
                guard let data = Data(base64Encoded: b64) else { return "" }
                return String(data: data, encoding: .isoLatin1) ?? ""
            }
            ctx.setObject(atob, forKeyedSubscript: "atob" as NSString)
        }

        let source = try String(contentsOf: Self.bridgeURL(), encoding: .utf8)
        ctx.evaluateScript(source)
        if let exception = ctx.exception {
            throw BridgeLoadError("bridge.js threw: \(exception)")
        }
        return ctx
    }

    private static func bridgeURL() throws -> URL {
        if let bundled = EntheaBundleLoader.directoryURL(in: .main)?
            .appendingPathComponent("bridge.js"),
            FileManager.default.fileExists(atPath: bundled.path)
        {
            return bundled
        }
        let fromSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Enthea/bridge.js")
        guard FileManager.default.fileExists(atPath: fromSource.path) else {
            throw BridgeLoadError("bridge.js not found")
        }
        return fromSource
    }
}

private struct BridgeLoadError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}
