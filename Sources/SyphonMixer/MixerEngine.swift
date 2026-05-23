import AppKit
import Metal
import MetalKit
import Syphon
import SyphonMixerCore

private struct MixerVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

private struct FragmentUniforms {
    var alpha: Float
}

private final class MixerInputChannel {
    var serverID: String?
    var label = "None"
    var sourceDescription: [String: Any]?
    var isEnabled = true
    var volume: Float = 1.0
    var scaleMode: ScaleMode = .fillCrop
    var client: SyphonMetalClient?
    var lastSize: MixerSize?
    var lastFrameTime = Date.distantPast

    func disconnect() {
        client?.stop()
        client = nil
        lastSize = nil
    }

    func clearSource() {
        disconnect()
        serverID = nil
        label = "None"
        sourceDescription = nil
    }

    deinit {
        clearSource()
    }
}

final class MixerEngine: NSObject, MTKViewDelegate {
    static let syphonInputCount = 4
    static let testPatternChannelIndex = syphonInputCount
    static let channelCount = syphonInputCount + 1
    static let outputServerName = "syphon-mixer Output"

    let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let channels: [MixerInputChannel] = {
        let channels = (0..<MixerEngine.channelCount).map { _ in MixerInputChannel() }
        let testChannel = channels[MixerEngine.testPatternChannelIndex]
        testChannel.label = "Test Pattern"
        testChannel.isEnabled = false
        testChannel.scaleMode = .stretch
        return channels
    }()
    private var outputTexture: MTLTexture?
    private var outputWidth: Int
    private var outputHeight: Int
    private var outputView: MTKView?
    private var channelPreviewIndices: [ObjectIdentifier: Int] = [:]
    private var syphonServer: SyphonMetalServer?
    private let testPatternWidth = 1920
    private let testPatternHeight = 1080
    private var testPatternTexture: MTLTexture?

    init(device: MTLDevice, outputWidth: Int = 1920, outputHeight: Int = 1080) throws {
        self.device = device
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight

        guard let queue = device.makeCommandQueue() else {
            throw MixerEngineError.metalUnavailable("Could not create a Metal command queue.")
        }
        commandQueue = queue

        let library = try device.makeLibrary(source: Self.metalShaderSource, options: nil)
        guard let vertexFunction = library.makeFunction(name: "mixer_vertex"),
              let fragmentFunction = library.makeFunction(name: "mixer_fragment") else {
            throw MixerEngineError.metalUnavailable("Could not load mixer shader functions.")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MixerEngineError.metalUnavailable("Could not create a sampler state.")
        }
        samplerState = sampler

        super.init()

        syphonServer = SyphonMetalServer(
            name: Self.outputServerName,
            device: device,
            options: [SyphonServerOptionFrameChannel: SyphonFrameChannelColor]
        )
    }

    deinit {
        syphonServer?.stop()
        channels.forEach { $0.clearSource() }
    }

    func makeOutputView(frame: NSRect) -> MTKView {
        let view = makeRenderView(frame: frame, framesPerSecond: 60)
        outputView = view
        return view
    }

    func makeChannelPreviewView(channel index: Int, frame: NSRect) -> MTKView {
        let view = makeRenderView(frame: frame, framesPerSecond: 30)
        channelPreviewIndices[ObjectIdentifier(view)] = index
        return view
    }

    private func makeRenderView(frame: NSRect, framesPerSecond: Int) -> MTKView {
        let view = MTKView(frame: frame, device: device)
        view.delegate = self
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        view.preferredFramesPerSecond = framesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        return view
    }

    func setSource(channel index: Int, source: SyphonServerInfo?) {
        guard channels.indices.contains(index), !isTestPatternChannel(index) else { return }
        let channel = channels[index]
        channel.disconnect()

        guard let source else {
            channel.clearSource()
            return
        }

        channel.serverID = source.id
        channel.label = source.displayName
        channel.sourceDescription = source.description
        connectChannelIfNeeded(channel)
    }

    func setVolume(channel index: Int, value: Float) {
        guard channels.indices.contains(index) else { return }
        channels[index].volume = min(max(value, 0.0), 1.0)
    }

    func setEnabled(channel index: Int, enabled: Bool) {
        guard channels.indices.contains(index) else { return }
        let channel = channels[index]
        guard channel.isEnabled != enabled else { return }
        channel.isEnabled = enabled
        if enabled {
            connectChannelIfNeeded(channel)
        } else {
            channel.disconnect()
        }
    }

    func setScaleMode(channel index: Int, mode: ScaleMode) {
        guard channels.indices.contains(index) else { return }
        channels[index].scaleMode = mode
    }

    func setOutputSize(width: Int, height: Int) {
        let safeWidth = min(max(width, 64), 8192)
        let safeHeight = min(max(height, 64), 8192)
        guard safeWidth != outputWidth || safeHeight != outputHeight else { return }
        outputWidth = safeWidth
        outputHeight = safeHeight
        outputTexture = nil
    }

    func outputSizeLabel() -> String {
        "\(outputWidth)x\(outputHeight)"
    }

    func channelStatuses() -> [String] {
        channels.enumerated().map { index, channel in
            if isTestPatternChannel(index) {
                guard channel.isEnabled else {
                    return "TEST: off"
                }
                let size = channel.lastSize.map { "\(Int($0.width))x\(Int($0.height))" }
                    ?? "\(testPatternWidth)x\(testPatternHeight)"
                return "TEST: pattern, \(size)"
            }

            guard channel.isEnabled else {
                return "CH\(index + 1): off"
            }
            guard let client = channel.client else {
                return "CH\(index + 1): none"
            }
            let valid = client.isValid ? "valid" : "lost"
            let size = channel.lastSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "waiting"
            return "CH\(index + 1): \(valid), \(size)"
        }
    }

    private func isTestPatternChannel(_ index: Int) -> Bool {
        index == Self.testPatternChannelIndex
    }

    private func connectChannelIfNeeded(_ channel: MixerInputChannel) {
        guard channel.isEnabled,
              channel.client == nil,
              let description = channel.sourceDescription else {
            return
        }

        let client = SyphonMetalClient(
            serverDescription: description,
            device: device,
            options: nil,
            newFrameHandler: nil
        )
        if client.isValid {
            channel.client = client
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = size
    }

    func draw(in view: MTKView) {
        if view === outputView {
            drawOutput(in: view)
            return
        }

        if let channelIndex = channelPreviewIndices[ObjectIdentifier(view)] {
            drawChannelPreview(channel: channelIndex, in: view)
        }
    }

    private func drawOutput(in view: MTKView) {
        autoreleasepool {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let texture = ensureOutputTexture() else {
                return
            }

            encodeMixerPass(to: texture, commandBuffer: commandBuffer)
            encodeTexturePass(
                from: texture,
                view: view,
                drawable: drawable,
                commandBuffer: commandBuffer,
                mode: .stretch,
                alpha: 1.0
            )

            syphonServer?.publishFrameTexture(
                texture,
                on: commandBuffer,
                imageRegion: NSRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
                flipped: false
            )

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private func drawChannelPreview(channel index: Int, in view: MTKView) {
        autoreleasepool {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            if let texture = currentTextureForPreview(channel: index) {
                encodeTexturePass(
                    from: texture,
                    view: view,
                    drawable: drawable,
                    commandBuffer: commandBuffer,
                    mode: .fit,
                    alpha: 1.0
                )
            } else {
                encodeClearPass(view: view, commandBuffer: commandBuffer)
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private func currentTextureForPreview(channel index: Int) -> MTLTexture? {
        currentTexture(forChannel: index, requirePositiveVolume: false)
    }

    private func currentTexture(forChannel index: Int, requirePositiveVolume: Bool) -> MTLTexture? {
        guard channels.indices.contains(index) else { return nil }
        let channel = channels[index]
        guard channel.isEnabled else { return nil }
        if requirePositiveVolume, channel.volume <= 0.0 {
            return nil
        }

        if isTestPatternChannel(index) {
            guard let texture = makeTestPatternTexture() else { return nil }
            channel.lastSize = MixerSize(width: Double(texture.width), height: Double(texture.height))
            channel.lastFrameTime = Date()
            return texture
        }

        guard let client = channel.client,
              client.isValid,
              let texture = client.newFrameImage() else {
            return nil
        }
        channel.lastSize = MixerSize(width: Double(texture.width), height: Double(texture.height))
        channel.lastFrameTime = Date()
        return texture
    }

    private func makeTestPatternTexture() -> MTLTexture? {
        if let testPatternTexture {
            return testPatternTexture
        }

        let width = testPatternWidth
        let height = testPatternHeight
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bars: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (255, 255, 255),
            (255, 255, 0),
            (0, 255, 255),
            (0, 255, 0),
            (255, 0, 255),
            (255, 0, 0),
            (0, 0, 255),
            (0, 0, 0)
        ]

        for y in 0..<height {
            for x in 0..<width {
                let barIndex = min((x * bars.count) / width, bars.count - 1)
                var r = bars[barIndex].r
                var g = bars[barIndex].g
                var b = bars[barIndex].b

                if y >= height * 3 / 4 {
                    let ramp = UInt8((x * 255) / max(width - 1, 1))
                    r = ramp
                    g = ramp
                    b = ramp
                }

                if y >= height * 7 / 8 {
                    let white = ((x / 40) + (y / 40)).isMultiple(of: 2)
                    r = white ? 255 : 0
                    g = white ? 255 : 0
                    b = white ? 255 : 0
                }

                let isBorder = x < 6 || y < 6 || x >= width - 6 || y >= height - 6
                let isCenterLine = abs(x - width / 2) <= 2 || abs(y - height / 2) <= 2
                let isGrid = x.isMultiple(of: 120) || y.isMultiple(of: 120)
                if isBorder || isCenterLine {
                    r = 255
                    g = 255
                    b = 255
                } else if isGrid {
                    r = max(r / 2, 48)
                    g = max(g / 2, 48)
                    b = max(b / 2, 48)
                }

                let offset = (y * width + x) * 4
                bytes[offset] = b
                bytes[offset + 1] = g
                bytes[offset + 2] = r
                bytes[offset + 3] = 255
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: width * 4
            )
        }

        testPatternTexture = texture
        return texture
    }

    private func ensureOutputTexture() -> MTLTexture? {
        if let outputTexture,
           outputTexture.width == outputWidth,
           outputTexture.height == outputHeight {
            return outputTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: outputWidth,
            height: outputHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        outputTexture = device.makeTexture(descriptor: descriptor)
        return outputTexture
    }

    private func encodeMixerPass(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        let outputSize = MixerSize(width: Double(outputWidth), height: Double(outputHeight))
        for (index, channel) in channels.enumerated() {
            guard let sourceTexture = currentTexture(forChannel: index, requirePositiveVolume: true) else {
                continue
            }

            let sourceSize = MixerSize(width: Double(sourceTexture.width), height: Double(sourceTexture.height))
            let mode: ScaleMode = isTestPatternChannel(index) ? .stretch : channel.scaleMode
            let mapping = AspectLayout.mapping(source: sourceSize, output: outputSize, mode: mode)
            drawQuad(texture: sourceTexture, mapping: mapping, alpha: channel.volume, encoder: encoder)
        }

        encoder.endEncoding()
    }

    private func encodeTexturePass(
        from texture: MTLTexture,
        view: MTKView,
        drawable: CAMetalDrawable,
        commandBuffer: MTLCommandBuffer,
        mode: ScaleMode,
        alpha: Float
    ) {
        guard let passDescriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        let mapping = AspectLayout.mapping(
            source: MixerSize(width: Double(texture.width), height: Double(texture.height)),
            output: MixerSize(width: Double(drawable.texture.width), height: Double(drawable.texture.height)),
            mode: mode
        )
        drawQuad(texture: texture, mapping: mapping, alpha: alpha, encoder: encoder)
        encoder.endEncoding()
    }

    private func encodeClearPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let passDescriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.endEncoding()
    }

    private func drawQuad(texture: MTLTexture, mapping: TextureMapping, alpha: Float, encoder: MTLRenderCommandEncoder) {
        let destination = mapping.destination
        let uv = mapping.uv
        let left = Float(destination.x * 2.0 - 1.0)
        let right = Float((destination.x + destination.width) * 2.0 - 1.0)
        let top = Float(1.0 - destination.y * 2.0)
        let bottom = Float(1.0 - (destination.y + destination.height) * 2.0)
        let u0 = Float(uv.x)
        let u1 = Float(uv.x + uv.width)
        let v0 = Float(uv.y)
        let v1 = Float(uv.y + uv.height)

        let vertices = [
            MixerVertex(position: SIMD2<Float>(left, top), uv: SIMD2<Float>(u0, v0)),
            MixerVertex(position: SIMD2<Float>(left, bottom), uv: SIMD2<Float>(u0, v1)),
            MixerVertex(position: SIMD2<Float>(right, bottom), uv: SIMD2<Float>(u1, v1)),
            MixerVertex(position: SIMD2<Float>(left, top), uv: SIMD2<Float>(u0, v0)),
            MixerVertex(position: SIMD2<Float>(right, bottom), uv: SIMD2<Float>(u1, v1)),
            MixerVertex(position: SIMD2<Float>(right, top), uv: SIMD2<Float>(u1, v0))
        ]
        var uniforms = FragmentUniforms(alpha: alpha)

        vertices.withUnsafeBytes { vertexBytes in
            encoder.setVertexBytes(vertexBytes.baseAddress!, length: vertexBytes.count, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
    }

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct MixerVertex {
        float2 position;
        float2 uv;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct FragmentUniforms {
        float alpha;
    };

    vertex VertexOut mixer_vertex(const device MixerVertex *vertices [[buffer(0)]],
                                  uint vertexID [[vertex_id]]) {
        VertexOut out;
        out.position = float4(vertices[vertexID].position, 0.0, 1.0);
        out.uv = vertices[vertexID].uv;
        return out;
    }

    fragment float4 mixer_fragment(VertexOut in [[stage_in]],
                                   texture2d<float> sourceTexture [[texture(0)]],
                                   sampler sourceSampler [[sampler(0)]],
                                   constant FragmentUniforms &uniforms [[buffer(0)]]) {
        float4 color = sourceTexture.sample(sourceSampler, in.uv);
        return float4(color.rgb * uniforms.alpha, 1.0);
    }
    """
}

enum MixerEngineError: LocalizedError {
    case metalUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable(let message):
            return message
        }
    }
}
