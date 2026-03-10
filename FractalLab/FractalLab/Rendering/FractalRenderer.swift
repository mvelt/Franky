import Metal
import MetalKit
import simd

// MARK: - FractalRenderer

/// MTKViewDelegate that owns the Metal pipeline.
/// Renders the fractal to an MTLTexture via a compute shader, then blits
/// that texture to the drawable using a render pipeline.
final class FractalRenderer: NSObject, MTKViewDelegate {

    // MARK: Metal objects
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var computePipeline: MTLComputePipelineState!
    private var renderPipeline: MTLRenderPipelineState!

    // MARK: Fractal texture
    private var fractalTexture: MTLTexture?
    private var textureSize: MTLSize = MTLSize(width: 0, height: 0, depth: 1)

    // MARK: Parameters (written by FractalState, read during draw)
    var params = FractalParams()

    // MARK: Callbacks
    /// Called when a frame is fully rendered — used for recording.
    var onFrameRendered: ((MTLTexture) -> Void)?

    // MARK: Init

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        guard buildPipelines() else { return nil }
    }

    // MARK: Pipeline setup

    private func buildPipelines() -> Bool {
        guard let library = device.makeDefaultLibrary() else {
            print("FractalRenderer: Failed to load default Metal library")
            return false
        }

        // Compute pipeline
        guard let computeFn = library.makeFunction(name: "fractalKernel") else {
            print("FractalRenderer: fractalKernel not found")
            return false
        }
        do {
            computePipeline = try device.makeComputePipelineState(function: computeFn)
        } catch {
            print("FractalRenderer: compute pipeline error: \(error)")
            return false
        }

        // Render pipeline (display pass)
        guard
            let vertFn = library.makeFunction(name: "displayVertex"),
            let fragFn = library.makeFunction(name: "displayFragment")
        else {
            print("FractalRenderer: display shaders not found")
            return false
        }
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction   = vertFn
        rpd.fragmentFunction = fragFn
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: rpd)
        } catch {
            print("FractalRenderer: render pipeline error: \(error)")
            return false
        }
        return true
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildTexture(width: Int(size.width), height: Int(size.height))
        params.viewWidth  = Float(size.width)
        params.viewHeight = Float(size.height)
    }

    func draw(in view: MTKView) {
        guard
            let texture  = fractalTexture,
            let drawable = view.currentDrawable,
            let rpd      = view.currentRenderPassDescriptor,
            let cmdBuf   = commandQueue.makeCommandBuffer()
        else { return }

        // ── Compute pass: render fractal → texture ───────────────────────────
        if let enc = cmdBuf.makeComputeCommandEncoder() {
            enc.setComputePipelineState(computePipeline)
            enc.setTexture(texture, index: 0)
            enc.setBytes(&params, length: MemoryLayout<FractalParams>.stride, index: 0)

            let w = computePipeline.threadExecutionWidth
            let h = computePipeline.maxTotalThreadsPerThreadgroup / w
            let tpg  = MTLSize(width: w, height: h, depth: 1)
            let tpGrid = MTLSize(
                width:  (textureSize.width  + w - 1) / w,
                height: (textureSize.height + h - 1) / h,
                depth:  1
            )
            enc.dispatchThreadgroups(tpGrid, threadsPerThreadgroup: tpg)
            enc.endEncoding()
        }

        // ── Render pass: blit texture → drawable ────────────────────────────
        if let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(renderPipeline)
            enc.setFragmentTexture(texture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }

        cmdBuf.addCompletedHandler { [weak self] _ in
            if let tex = self?.fractalTexture {
                self?.onFrameRendered?(tex)
            }
        }

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: Texture management

    private func rebuildTexture(width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .private
        fractalTexture = device.makeTexture(descriptor: desc)
        textureSize    = MTLSize(width: width, height: height, depth: 1)
    }

    // MARK: Off-screen render (for recording / export)

    /// Renders the current params into a new texture of the given size.
    func renderOffscreen(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .private
        guard
            let tex     = device.makeTexture(descriptor: desc),
            let cmdBuf  = commandQueue.makeCommandBuffer(),
            let enc     = cmdBuf.makeComputeCommandEncoder()
        else { return nil }

        var p = params
        p.viewWidth  = Float(width)
        p.viewHeight = Float(height)

        enc.setComputePipelineState(computePipeline)
        enc.setTexture(tex, index: 0)
        enc.setBytes(&p, length: MemoryLayout<FractalParams>.stride, index: 0)

        let w    = computePipeline.threadExecutionWidth
        let h    = computePipeline.maxTotalThreadsPerThreadgroup / w
        let tpg  = MTLSize(width: w, height: h, depth: 1)
        let tpGrid = MTLSize(
            width:  (width  + w - 1) / w,
            height: (height + h - 1) / h,
            depth:  1
        )
        enc.dispatchThreadgroups(tpGrid, threadsPerThreadgroup: tpg)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        return tex
    }

    // MARK: Snapshot (current drawable → UIImage)

    func currentImage(from view: MTKView) -> UIImage? {
        guard let tex = fractalTexture else { return nil }
        return tex.toUIImage(device: device, queue: commandQueue)
    }
}

// MARK: - MTLTexture → UIImage helper

extension MTLTexture {
    func toUIImage(device: MTLDevice, queue: MTLCommandQueue) -> UIImage? {
        let bytesPerPixel = 4
        let bytesPerRow   = width * bytesPerPixel
        let totalBytes    = bytesPerRow * height

        guard
            let buf = device.makeBuffer(length: totalBytes, options: .storageModeShared),
            let cmd = queue.makeCommandBuffer(),
            let enc = cmd.makeBlitCommandEncoder()
        else { return nil }

        enc.copy(
            from: self,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: buf, destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: totalBytes
        )
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: buf.contents(),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImg = ctx.makeImage() else { return nil }

        return UIImage(cgImage: cgImg)
    }
}
