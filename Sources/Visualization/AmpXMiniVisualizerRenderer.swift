import MetalKit
import os

private let miniMetalLogger = Logger(subsystem: "com.ampx.macos", category: "MiniVisualizer")

/// Externally driven renderer. The host owns the MTKView's paused state and frame clock.
/// Each admitted submission owns its buffers/history until GPU completion; busy frames are dropped.
@MainActor
final class AmpXMiniVisualizerRenderer {
    struct Statistics: Sendable {
        let submittedFrames: UInt64
        let completedFrames: UInt64
        let droppedFrames: UInt64
        let failedFrames: UInt64
        let cpuEncodingP95Milliseconds: Double
        let gpuP95Milliseconds: Double
        let gpuTimingSamples: UInt64
    }

    /// Rolling 120-frame timings; reading a snapshot does the percentile work, never GPU callbacks.
    /// CPU timings exclude drawable acquisition/capture texture allocation and synchronous capture waits.
    var statistics: Statistics {
        let state = self.timings.withLock { $0 }
        return Statistics(
            submittedFrames: state.submitted, completedFrames: state.completed,
            droppedFrames: state.dropped, failedFrames: state.failed,
            cpuEncodingP95Milliseconds: Self.percentile(state.cpu, count: state.submitted),
            gpuP95Milliseconds: Self.percentile(state.gpu, count: state.gpuSamples),
            gpuTimingSamples: state.gpuSamples
        )
    }

    enum CaptureError: Error, LocalizedError {
        case invalidDimensions
        case resourceAllocation
        case inFlightLimit
        case commandEncoding
        case gpuFailure(String)

        var errorDescription: String? {
            switch self {
            case .invalidDimensions: "Mini visualizer capture dimensions must be between 1 and 16384 pixels."
            case .resourceAllocation: "Metal could not allocate mini visualizer capture resources."
            case .inFlightLimit: "All mini visualizer frame buffers are in flight; retry capture after GPU completion."
            case .commandEncoding: "Metal could not encode the mini visualizer capture."
            case let .gpuFailure(message): "Mini visualizer GPU capture failed: \(message)"
            }
        }
    }

    private static let bandCount = 32
    private static let waveformCapacity = 512
    private static let historyRows = 128
    private static let particleCount = 512
    private static let payloadCount = bandCount * 3 + waveformCapacity

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelines: [Pass: MTLRenderPipelineState]
    private let emptyHistory: MTLTexture
    private let slots: [FrameSlot]
    private let timings = OSAllocatedUnfairLock(initialState: TimingState())

    private struct TimingState: Sendable {
        var submitted: UInt64 = 0
        var completed: UInt64 = 0
        var dropped: UInt64 = 0
        var failed: UInt64 = 0
        var gpuSamples: UInt64 = 0
        var cpu = [Double](repeating: 0, count: 120)
        var gpu = [Double](repeating: 0, count: 120)
    }

    private enum Pass: CaseIterable {
        case field, particles

        var vertex: String {
            self == .field ? "miniVisualizerVertex" : "miniParticleVertex"
        }

        var fragment: String {
            self == .field ? "miniVisualizerFragment" : "miniParticleFragment"
        }
    }

    /// Keep this layout in sync with MiniUniforms in MiniVisualizerShaders.metal.
    private struct Uniforms {
        var dimensions: SIMD4<Float> // pixel width, pixel height, elapsed seconds, particle opacity
        var mode: SIMD4<UInt32> // style, waveform count, reserved, reserved
        var meters: SIMD4<Float> // L/R RMS, L/R sample peak
        var background: SIMD4<Float>
        var low: SIMD4<Float>
        var middle: SIMD4<Float>
        var high: SIMD4<Float>
        var trace: SIMD4<Float>
        var peak: SIMD4<Float>
        var dimCell: SIMD4<Float>
        var historyLow: SIMD4<Float>
        var historyHigh: SIMD4<Float>
        var ramp: SIMD4<Float> // low hold end, middle stop, high stop, level-colored peaks
    }

    @MainActor
    private final class FrameSlot {
        let available = DispatchSemaphore(value: 1)
        let uniforms: MTLBuffer
        let signal: MTLBuffer
        var history: MTLTexture?
        var historyUpload: MTLBuffer?

        init?(device: MTLDevice) {
            guard let uniforms = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared),
                  let signal = device.makeBuffer(length: payloadCount * MemoryLayout<Float>.stride, options: .storageModeShared)
            else { return nil }
            self.uniforms = uniforms
            self.signal = signal
            uniforms.label = "Mini visualizer uniforms"
            signal.label = "Mini visualizer prepared signal"
        }
    }

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            miniMetalLogger.error("Mini visualizer unavailable: no Metal device, queue, or default shader library.")
            return nil
        }
        do {
            var pipelines: [Pass: MTLRenderPipelineState] = [:]
            for pass in Pass.allCases {
                guard let vertex = library.makeFunction(name: pass.vertex),
                      let fragment = library.makeFunction(name: pass.fragment)
                else {
                    miniMetalLogger.error("Mini visualizer shader missing: \(pass.fragment, privacy: .public)")
                    return nil
                }
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "Mini visualizer \(pass.fragment)"
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                let attachment = descriptor.colorAttachments[0]
                attachment?.pixelFormat = .bgra8Unorm
                if pass == .particles {
                    // Premultiplied source-over. The field pass always writes an opaque background.
                    attachment?.isBlendingEnabled = true
                    attachment?.sourceRGBBlendFactor = .one
                    attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    attachment?.sourceAlphaBlendFactor = .one
                    attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                pipelines[pass] = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            var slots: [FrameSlot] = []
            for _ in 0 ..< 3 {
                guard let slot = FrameSlot(device: device) else { throw CaptureError.resourceAllocation }
                slots.append(slot)
            }
            guard let emptyHistory = Self.makeHistory(device: device, width: 1, height: 1) else {
                throw CaptureError.resourceAllocation
            }
            var zero: Float = 0
            emptyHistory.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: &zero,
                bytesPerRow: MemoryLayout<Float>.stride
            )
            self.device = device
            self.queue = queue
            self.pipelines = pipelines
            self.slots = slots
            self.emptyHistory = emptyHistory
        } catch {
            miniMetalLogger.error("Mini visualizer initialization failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Expects a single-sample BGRA8Unorm view on this renderer's device, driven manually.
    /// No delegate, autonomous draw loop, GPU wait, or unbounded pending work is installed here.
    func render(
        _ frame: AmpXMiniVisualizerFrame,
        style: AmpXMiniVisualizerStyle,
        palette: AmpXMiniVisualizerPalette,
        in view: MTKView
    ) {
        guard view.device?.registryID == self.device.registryID,
              view.colorPixelFormat == .bgra8Unorm, view.sampleCount == 1,
              view.drawableSize.width > 0, view.drawableSize.height > 0
        else { return }
        guard let slot = self.acquireSlot() else { return }
        autoreleasepool {
            var submitted = false
            defer {
                if !submitted {
                    slot.available.signal()
                }
            }
            // Admission precedes drawable acquisition; a saturated GPU never acquires another drawable.
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let command = self.queue.makeCommandBuffer()
            else { return }
            do {
                let start = DispatchTime.now().uptimeNanoseconds
                try self.prepare(
                    slot,
                    frame: frame,
                    style: style,
                    palette: palette,
                    width: drawable.texture.width,
                    height: drawable.texture.height
                )
                try self.encode(command, descriptor: descriptor, slot: slot, style: style)
                command.present(drawable)
                self.submit(command, releasing: slot.available, startedAt: start)
                submitted = true
            } catch {
                miniMetalLogger.error("Mini visualizer frame failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Explicit synchronous capture. Uses the same resources, shader passes and encoding as the view.
    /// A returned texture is complete and CPU-readable; failures never return an uninitialized image.
    func renderOffscreen(
        _ frame: AmpXMiniVisualizerFrame,
        style: AmpXMiniVisualizerStyle,
        palette: AmpXMiniVisualizerPalette,
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        guard (1 ... 16384).contains(width), (1 ... 16384).contains(height) else { throw CaptureError.invalidDimensions }
        guard let slot = self.acquireSlot() else { throw CaptureError.inFlightLimit }
        var submitted = false
        defer {
            if !submitted {
                slot.available.signal()
            }
        }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        textureDescriptor.storageMode = self.device.hasUnifiedMemory ? .shared : .managed
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = self.device.makeTexture(descriptor: textureDescriptor),
              let command = self.queue.makeCommandBuffer()
        else { throw CaptureError.resourceAllocation }
        texture.label = "Mini visualizer capture"
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        let start = DispatchTime.now().uptimeNanoseconds
        try self.prepare(slot, frame: frame, style: style, palette: palette, width: width, height: height)
        try self.encode(command, descriptor: descriptor, slot: slot, style: style)
        if texture.storageMode == .managed {
            guard let blit = command.makeBlitCommandEncoder() else { throw CaptureError.commandEncoding }
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        self.submit(command, releasing: slot.available, startedAt: start)
        submitted = true
        command.waitUntilCompleted()
        guard command.status == .completed else {
            throw CaptureError.gpuFailure(command.error?.localizedDescription ?? "command did not complete")
        }
        return texture
    }

    private func acquireSlot() -> FrameSlot? {
        let slot = self.slots.first { $0.available.wait(timeout: .now()) == .success }
        if slot == nil {
            self.timings.withLock { $0.dropped &+= 1 }
        }
        return slot
    }

    private func submit(_ command: MTLCommandBuffer, releasing semaphore: DispatchSemaphore, startedAt start: UInt64) {
        command.label = "Mini visualizer frame"
        let timings = self.timings
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        timings.withLock { state in
            state.cpu[Int(state.submitted % 120)] = milliseconds
            state.submitted &+= 1
        }
        // Only thread-safe storage crosses the callback boundary, never main-actor renderer/view state.
        command.addCompletedHandler { buffer in
            let gpuMilliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            let failed = buffer.status == .error
            timings.withLock { state in
                state.completed &+= 1
                if failed {
                    state.failed &+= 1
                }
                if gpuMilliseconds.isFinite, gpuMilliseconds > 0 {
                    state.gpu[Int(state.gpuSamples % 120)] = gpuMilliseconds
                    state.gpuSamples &+= 1
                }
            }
            if buffer.status == .error {
                miniMetalLogger.error("Mini visualizer GPU error: \(buffer.error?.localizedDescription ?? "unknown", privacy: .public)")
            }
            semaphore.signal()
        }
        command.commit()
    }

    private static func percentile(_ samples: [Double], count: UInt64) -> Double {
        let count = Int(min(count, UInt64(samples.count)))
        guard count > 0 else { return 0 }
        return samples.prefix(count).sorted()[min(count - 1, Int(ceil(Double(count) * 0.95)) - 1)]
    }

    private func encode(
        _ command: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor,
        slot: FrameSlot, style: AmpXMiniVisualizerStyle
    ) throws {
        guard let field = self.pipelines[.field], let particles = self.pipelines[.particles] else {
            throw CaptureError.commandEncoding
        }
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw CaptureError.commandEncoding
        }
        encoder.label = "Mini visualizer effects"
        encoder.setRenderPipelineState(field)
        encoder.setFragmentBuffer(slot.uniforms, offset: 0, index: 0)
        encoder.setFragmentBuffer(slot.signal, offset: 0, index: 1)
        encoder.setFragmentTexture(style == .waterfall ? slot.history : self.emptyHistory, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if style == .particleWaveform {
            encoder.setRenderPipelineState(particles)
            encoder.setVertexBuffer(slot.uniforms, offset: 0, index: 0)
            encoder.setVertexBuffer(slot.signal, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: Self.particleCount)
        }
        encoder.endEncoding()
    }

    private func prepare(
        _ slot: FrameSlot, frame: AmpXMiniVisualizerFrame,
        style: AmpXMiniVisualizerStyle, palette: AmpXMiniVisualizerPalette,
        width: Int, height: Int
    ) throws {
        let waveCount = min(frame.waveform.count, Self.waveformCapacity)
        var uniforms = Self.uniforms(palette: palette)
        uniforms.dimensions = SIMD4(
            Float(width),
            Float(height),
            frame.elapsed.isFinite ? frame.elapsed : 0,
            Self.normalized(frame.particleOpacity)
        )
        uniforms.mode = SIMD4(style.shaderIndex, UInt32(waveCount), 0, 0)
        uniforms.meters = SIMD4(
            Self.normalized(frame.meterLevels.x),
            Self.normalized(frame.meterLevels.y),
            Self.normalized(frame.meterPeaks.x),
            Self.normalized(frame.meterPeaks.y)
        )
        withUnsafeBytes(of: &uniforms) { bytes in
            if let base = bytes.baseAddress {
                slot.uniforms.contents().copyMemory(from: base, byteCount: bytes.count)
            }
        }
        let signal = slot.signal.contents().bindMemory(to: Float.self, capacity: Self.payloadCount)
        Self.copy(frame.spectrum, into: signal, count: Self.bandCount)
        Self.copy(frame.peaks, into: signal.advanced(by: Self.bandCount), count: Self.bandCount)
        Self.copy(frame.trails, into: signal.advanced(by: Self.bandCount * 2), count: Self.bandCount)
        Self.copy(frame.waveform, into: signal.advanced(by: Self.bandCount * 3), count: Self.waveformCapacity, bipolar: true)
        if style == .waterfall {
            try self.prepareHistory(slot, values: frame.history)
        }
    }

    private func prepareHistory(_ slot: FrameSlot, values: [Float]) throws {
        let count = Self.bandCount * Self.historyRows
        if slot.history == nil {
            slot.history = Self.makeHistory(device: self.device, width: Self.bandCount, height: Self.historyRows)
        }
        if slot.historyUpload == nil {
            slot.historyUpload = self.device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared)
        }
        guard let texture = slot.history, let upload = slot.historyUpload else { throw CaptureError.resourceAllocation }
        // Exact fixed-size oldest-first frame contract. Truncate oversized input and zero missing cells.
        let pointer = upload.contents().bindMemory(to: Float.self, capacity: count)
        Self.copy(values, into: pointer, count: count)
        texture.replace(
            region: MTLRegionMake2D(0, 0, Self.bandCount, Self.historyRows),
            mipmapLevel: 0,
            withBytes: pointer,
            bytesPerRow: Self.bandCount * MemoryLayout<Float>.stride
        )
    }

    private static func makeHistory(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Mini visualizer bounded history"
        return texture
    }

    private static func normalized(_ value: Float, bipolar: Bool = false) -> Float {
        value.isFinite ? min(1, max(bipolar ? -1 : 0, value)) : 0
    }

    private static func copy(_ source: [Float], into pointer: UnsafeMutablePointer<Float>, count: Int, bipolar: Bool = false) {
        for index in 0 ..< count {
            pointer[index] = index < source.count ? self.normalized(source[index], bipolar: bipolar) : 0
        }
    }

    /// Explicit palette uniforms: the shader never infers palette from a style index or recolors signal data.
    private static func uniforms(palette: AmpXMiniVisualizerPalette) -> Uniforms {
        Uniforms(
            dimensions: .zero, mode: .zero, meters: .zero,
            background: palette.backgroundColor,
            low: palette.lowColor, middle: palette.midColor, high: palette.highColor,
            trace: palette.traceColor, peak: palette.peakColor, dimCell: palette.dimCellColor,
            historyLow: palette.historyColor, historyHigh: palette.highColor,
            ramp: palette.rampParameters
        )
    }
}
