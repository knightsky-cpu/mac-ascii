import CoreVideo
import Metal
import MetalKit
import simd

private struct Uniforms {
    var viewportSize: SIMD2<Float>
    var sourceSize: SIMD2<Float>
    var cellSize: Float
    var styleMode: Int32
    var renderMode: Int32
    var luminanceBuckets: Int32
    var opacity: Float
    var brightness: Float
    var contrast: Float
    var gamma: Float
    var edgeStrength: Float
    var time: Float
}

final class Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let computePipelineState: MTLComputePipelineState?
    private let circuitBendPipelineState: MTLComputePipelineState?
    private let textureCache: CVMetalTextureCache
    private let dummyCellMapTexture: MTLTexture
    private let state: AppState
    private let displayScale: Float
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var glyphAtlas: GlyphAtlas?
    private var cellMapTexture: MTLTexture?
    private var bentOutputTexture: MTLTexture?
    private var didAttemptGlyphAtlas = false
    private var startedAt = CFAbsoluteTimeGetCurrent()
    private var didLogRenderState = false

    init?(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        state: AppState,
        displayScale: CGFloat
    ) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else {
            return nil
        }

        do {
            let library = try device.makeLibrary(source: ShaderSource.asciiOverlay, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_ascii")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            if let computeFunction = library.makeFunction(name: "compute_true_ascii_cell_map") {
                computePipelineState = try? device.makeComputePipelineState(function: computeFunction)
            } else {
                computePipelineState = nil
            }
            if let circuitFunction = library.makeFunction(name: "compute_circuit_bend") {
                circuitBendPipelineState = try? device.makeComputePipelineState(function: circuitFunction)
            } else {
                circuitBendPipelineState = nil
            }
        } catch {
            print("MacAscii: failed to build Metal pipeline \(error)")
            return nil
        }

        guard let dummyCellMapTexture = Self.makeCellMapTexture(device: device, width: 1, height: 1) else {
            return nil
        }
        var zero = SIMD4<UInt32>(0, 0, 0, 0)
        dummyCellMapTexture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &zero,
            bytesPerRow: MemoryLayout<SIMD4<UInt32>>.stride
        )

        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = cache
        self.dummyCellMapTexture = dummyCellMapTexture
        self.state = state
        self.displayScale = Float(displayScale)
        super.init()
    }

    func update(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        latestPixelBuffer = pixelBuffer
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let pixelBuffer = latestPixelBuffer
        lock.unlock()

        guard let pixelBuffer,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let sourceTexture = makeTexture(from: pixelBuffer) else {
            return
        }

        let renderState = state.sanitizedRenderState()
        if renderState.renderMode == 7 || renderState.renderMode == 8 {
            prepareGlyphAtlasIfNeeded()
        }

        let viewportSize = SIMD2(
            Float(view.drawableSize.width) / max(1.0, displayScale),
            Float(view.drawableSize.height) / max(1.0, displayScale)
        )
        let sourceSize = SIMD2(Float(sourceTexture.width), Float(sourceTexture.height))

        if !didLogRenderState {
            print(
                "MacAscii: render-state " +
                "drawable=\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height)) " +
                "viewport=\(Int(viewportSize.x))x\(Int(viewportSize.y)) " +
                "source=\(Int(sourceSize.x))x\(Int(sourceSize.y)) " +
                "display-scale=\(displayScale) " +
                "cell-size=\(renderState.cellSize) " +
                "style-mode=\(renderState.styleMode) " +
                "render-mode=\(renderState.renderMode) " +
                "luminance-buckets=\(renderState.luminanceBuckets) " +
                "opacity=\(renderState.opacity) " +
                "brightness=\(renderState.brightness) " +
                "contrast=\(renderState.contrast) " +
                "gamma=\(renderState.gamma) " +
                "edge-strength=\(renderState.edgeStrength)"
            )
            didLogRenderState = true
        }

        var shaderRenderMode = renderState.renderMode
        let activeGlyphAtlas: GlyphAtlas?
        let activeCellMap: MTLTexture?
        if renderState.renderMode == 7 || renderState.renderMode == 8 {
            activeGlyphAtlas = glyphAtlas
            activeCellMap = ensureCellMapTexture(
                width: max(1, Int(floor(viewportSize.x / max(1.0, renderState.cellSize)))),
                height: max(1, Int(floor(viewportSize.y / max(1.0, renderState.cellSize))))
            )
            if activeGlyphAtlas == nil || activeCellMap == nil || computePipelineState == nil {
                shaderRenderMode = 0
            }
        } else {
            activeGlyphAtlas = nil
            activeCellMap = nil
        }
        var activeSourceTexture = sourceTexture

        var uniforms = Uniforms(
            viewportSize: viewportSize,
            sourceSize: sourceSize,
            cellSize: renderState.cellSize,
            styleMode: renderState.styleMode,
            renderMode: shaderRenderMode,
            luminanceBuckets: renderState.luminanceBuckets,
            opacity: renderState.opacity,
            brightness: renderState.brightness,
            contrast: renderState.contrast,
            gamma: renderState.gamma,
            edgeStrength: renderState.edgeStrength,
            time: Float(CFAbsoluteTimeGetCurrent() - startedAt)
        )

        if (shaderRenderMode == 7 || shaderRenderMode == 8), let activeCellMap {
            encodeTrueAsciiCellMap(
                commandBuffer: commandBuffer,
                sourceTexture: sourceTexture,
                cellMapTexture: activeCellMap,
                uniforms: &uniforms
            )
        }

        if shaderRenderMode == 9,
           let bentTexture = ensureBentOutputTexture(width: sourceTexture.width, height: sourceTexture.height),
           circuitBendPipelineState != nil {
            encodeCircuitBend(
                commandBuffer: commandBuffer,
                sourceTexture: sourceTexture,
                outputTexture: bentTexture,
                uniforms: &uniforms
            )
            activeSourceTexture = bentTexture
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(activeSourceTexture, index: 0)
        encoder.setFragmentTexture(activeGlyphAtlas?.texture ?? activeSourceTexture, index: 1)
        encoder.setFragmentTexture(activeCellMap ?? dummyCellMapTexture, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }

    private func ensureCellMapTexture(width: Int, height: Int) -> MTLTexture? {
        if let cellMapTexture,
           cellMapTexture.width == width,
           cellMapTexture.height == height {
            return cellMapTexture
        }

        cellMapTexture = Self.makeCellMapTexture(device: device, width: width, height: height)
        return cellMapTexture
    }

    private func ensureBentOutputTexture(width: Int, height: Int) -> MTLTexture? {
        if let bentOutputTexture,
           bentOutputTexture.width == width,
           bentOutputTexture.height == height {
            return bentOutputTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        bentOutputTexture = device.makeTexture(descriptor: descriptor)
        return bentOutputTexture
    }

    private static func makeCellMapTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Uint,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: descriptor)
    }

    private func encodeTrueAsciiCellMap(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        cellMapTexture: MTLTexture,
        uniforms: inout Uniforms
    ) {
        guard let computePipelineState,
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(cellMapTexture, index: 1)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadsPerGrid = MTLSize(width: cellMapTexture.width, height: cellMapTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
    }

    private func encodeCircuitBend(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        outputTexture: MTLTexture,
        uniforms: inout Uniforms
    ) {
        guard let circuitBendPipelineState,
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        computeEncoder.setComputePipelineState(circuitBendPipelineState)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadsPerGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
    }

    private func prepareGlyphAtlasIfNeeded() {
        guard glyphAtlas == nil, !didAttemptGlyphAtlas else {
            return
        }

        didAttemptGlyphAtlas = true
        if let atlas = GlyphAtlas.make(device: device) {
            glyphAtlas = atlas
            print("MacAscii: true-ascii glyph atlas ready glyphs=\(atlas.glyphCount)")
        } else {
            print("MacAscii: true-ascii glyph atlas unavailable")
        }
    }
}
