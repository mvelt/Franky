import AVFoundation
import Photos
import UIKit
import Metal

// MARK: - VideoExporter

/// Renders a RecordedSession to an H.264 MP4 file and saves it to the Photo Library.
@MainActor
final class VideoExporter {

    let renderer: FractalRenderer
    let state: FractalState

    private let fps: Int32 = 30

    init(renderer: FractalRenderer, state: FractalState) {
        self.renderer = renderer
        self.state    = state
    }

    // MARK: Export entry point

    func export(session: RecordedSession) async {
        guard !state.isExporting else { return }
        state.isExporting     = true
        state.exportProgress  = 0

        let exportSize = exportResolution()

        do {
            let url = try await renderToFile(session: session, size: exportSize)
            await saveToPhotos(url: url)
        } catch {
            print("VideoExporter: export failed: \(error)")
        }

        state.isExporting    = false
        state.exportProgress = 0
    }

    // MARK: Render pipeline

    private func renderToFile(session: RecordedSession, size: CGSize) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FractalLab_\(Int(Date().timeIntervalSince1970)).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:     8_000_000,
                AVVideoProfileLevelKey:       AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:           Int(size.width),
            kCVPixelBufferHeightKey as String:          Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(Double(fps) * session.duration)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for frameIndex in 0..<totalFrames {
            let t = Double(frameIndex) / Double(fps)

            if let kf = session.frame(at: t) {
                // Apply keyframe to a temporary copy of params (not state)
                var p = renderer.params
                p.centerX         = kf.centerX
                p.centerY         = kf.centerY
                p.zoom            = kf.zoom
                p.juliaCX         = kf.juliaCX
                p.juliaCY         = kf.juliaCY
                p.colorOffset     = kf.colorOffset
                p.colorCycleLength = kf.colorCycleLength
                p.paletteIndex    = Int32(kf.paletteIndex)
                p.maxIterations   = kf.maxIterations
                p.fractalType     = kf.fractalType.rawValue
                p.viewWidth       = Float(size.width)
                p.viewHeight      = Float(size.height)

                // Temporarily swap renderer params, render, restore
                let saved = renderer.params
                renderer.params = p
                let tex = renderer.renderOffscreen(width: Int(size.width), height: Int(size.height))
                renderer.params = saved

                if let tex, let pixelBuffer = tex.toPixelBuffer(pool: adaptor.pixelBufferPool) {
                    // Wait until input is ready
                    while !input.isReadyForMoreMediaData {
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                    let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                }
            }

            // Update progress on main actor
            let progress = Float(frameIndex + 1) / Float(max(1, totalFrames))
            state.exportProgress = progress
        }

        input.markAsFinished()

        return try await withCheckedThrowingContinuation { cont in
            writer.finishWriting {
                if let error = writer.error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: url)
                }
            }
        }
    }

    // MARK: Save to Photos

    private func saveToPhotos(url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            print("VideoExporter: saved to Photos")
        } catch {
            print("VideoExporter: Photos save error: \(error)")
        }
    }

    // MARK: Helpers

    private func exportResolution() -> CGSize {
        // Default to 1080p; honour device screen if it's larger
        let screen = UIScreen.main.nativeBounds.size
        let w = max(1080, Int(screen.width))
        let h = max(1920, Int(screen.height))
        return CGSize(width: w, height: h)
    }
}

// MARK: - MTLTexture → CVPixelBuffer

extension MTLTexture {
    func toPixelBuffer(pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool {
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess
            else { return nil }
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String:  width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            guard CVPixelBufferCreate(nil, width, height,
                                      kCVPixelFormatType_32BGRA,
                                      attrs as CFDictionary,
                                      &pixelBuffer) == kCVReturnSuccess
            else { return nil }
        }

        guard let pxBuf = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pxBuf, [])

        guard let base = CVPixelBufferGetBaseAddress(pxBuf) else {
            CVPixelBufferUnlockBaseAddress(pxBuf, [])
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pxBuf)

        // Use a shared-storage buffer to copy texture data out
        guard let device = (self as? MTLTexture)?.device ?? MTLCreateSystemDefaultDevice() else {
            CVPixelBufferUnlockBaseAddress(pxBuf, [])
            return nil
        }
        guard
            let queue  = device.makeCommandQueue(),
            let tmpBuf = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
            let cmd    = queue.makeCommandBuffer(),
            let enc    = cmd.makeBlitCommandEncoder()
        else {
            CVPixelBufferUnlockBaseAddress(pxBuf, [])
            return nil
        }

        enc.copy(
            from: self,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: tmpBuf, destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * height
        )
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        memcpy(base, tmpBuf.contents(), bytesPerRow * height)
        CVPixelBufferUnlockBaseAddress(pxBuf, [])
        return pxBuf
    }
}
