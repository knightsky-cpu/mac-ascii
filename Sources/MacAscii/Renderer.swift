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
    private let textureCache: CVMetalTextureCache
    private let state: AppState
    private let displayScale: Float
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
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
        } catch {
            print("MacAscii: failed to build Metal pipeline \(error)")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = cache
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
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor),
              let sourceTexture = makeTexture(from: pixelBuffer) else {
            return
        }

        let renderState = state.sanitizedRenderState()
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

        var uniforms = Uniforms(
            viewportSize: viewportSize,
            sourceSize: sourceSize,
            cellSize: renderState.cellSize,
            styleMode: renderState.styleMode,
            renderMode: renderState.renderMode,
            luminanceBuckets: renderState.luminanceBuckets,
            opacity: renderState.opacity,
            brightness: renderState.brightness,
            contrast: renderState.contrast,
            gamma: renderState.gamma,
            edgeStrength: renderState.edgeStrength,
            time: Float(CFAbsoluteTimeGetCurrent() - startedAt)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
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
}
