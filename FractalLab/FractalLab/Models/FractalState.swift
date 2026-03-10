import Foundation
import Combine
import Metal

// MARK: - FractalState

/// Single source of truth for the entire app.
/// Mutated by gesture handlers and UI controls; read by FractalRenderer.
final class FractalState: ObservableObject {

    // MARK: View position
    @Published var centerX: Float = -0.5
    @Published var centerY: Float =  0.0
    @Published var zoom: Float    = 200.0          // pixels per fractal unit × min(w,h)

    // MARK: Fractal type
    @Published var fractalType: FractalType = .mandelbrot
    @Published var juliaCX: Float =  -0.7
    @Published var juliaCY: Float =   0.27015
    @Published var juliaCPresetIndex: Int = 0

    // MARK: Colour
    @Published var paletteIndex: Int    = 0
    @Published var colorOffset: Float   = 0.0      // [0, 1)
    @Published var colorCycleLength: Float = 64.0  // smooth-iter divisor
    @Published var colorRotationSpeed: Float = 0.3 // offset per second
    @Published var isRotatingColors: Bool = false

    // MARK: Render quality
    @Published var maxIterations: Int32 = 256

    // MARK: UI overlay
    @Published var showControls: Bool = true
    @Published var showJuliaPicker: Bool = false   // preset list
    @Published var isDraggingJuliaC: Bool = false  // long-press drag mode

    // MARK: Recording / playback
    @Published var isRecording: Bool = false
    @Published var isPlayingBack: Bool = false
    @Published var playbackSpeed: Float = 1.0      // 0.25 … 4.0
    @Published var playbackReversed: Bool = false
    @Published var recordedSession: RecordedSession? = nil

    // MARK: Export
    @Published var isExporting: Bool = false
    @Published var exportProgress: Float = 0.0

    // MARK: Derived

    /// Build the FractalParams struct for the shader.
    func makeParams(viewWidth: Float, viewHeight: Float) -> FractalParams {
        var p = FractalParams()
        p.centerX        = centerX
        p.centerY        = centerY
        p.zoom           = zoom
        p.juliaCX        = juliaCX
        p.juliaCY        = juliaCY
        p.colorOffset    = colorOffset
        p.colorCycleLength = colorCycleLength
        p.aspectRatio    = viewWidth / max(viewHeight, 1)
        p.maxIterations  = maxIterations
        p.fractalType    = fractalType.rawValue
        p.paletteIndex   = Int32(paletteIndex)
        p.viewWidth      = viewWidth
        p.viewHeight     = viewHeight
        p.padding        = 0
        return p
    }

    // MARK: Zoom helpers

    /// Zoom in 2× centred on a screen-space point.
    func zoomIn(at screenPoint: CGPoint, viewSize: CGSize) {
        let scale = 1.0 / (zoom * min(Float(viewSize.width), Float(viewSize.height)))
        let fx = centerX + Float(screenPoint.x - viewSize.width  / 2) * scale
        let fy = centerY + Float(screenPoint.y - viewSize.height / 2) * scale
        withAnimation(.none) {
            centerX = fx
            centerY = fy
            zoom   *= 2.0
        }
        adaptIterations()
    }

    /// Zoom out 2× centred on a screen-space point.
    func zoomOut(at screenPoint: CGPoint, viewSize: CGSize) {
        let scale = 1.0 / (zoom * min(Float(viewSize.width), Float(viewSize.height)))
        let fx = centerX + Float(screenPoint.x - viewSize.width  / 2) * scale
        let fy = centerY + Float(screenPoint.y - viewSize.height / 2) * scale
        withAnimation(.none) {
            centerX = fx
            centerY = fy
            zoom   = max(50.0, zoom / 2.0)
        }
        adaptIterations()
    }

    /// Apply a pinch scale factor centred on a screen point.
    func applyPinch(scale: Float, at screenPoint: CGPoint, viewSize: CGSize) {
        let s = 1.0 / (zoom * min(Float(viewSize.width), Float(viewSize.height)))
        let fx = centerX + Float(screenPoint.x - viewSize.width  / 2) * s
        let fy = centerY + Float(screenPoint.y - viewSize.height / 2) * s
        let newZoom = max(50.0, zoom * scale)
        centerX = fx - Float(screenPoint.x - viewSize.width  / 2) / (newZoom * min(Float(viewSize.width), Float(viewSize.height)))
        centerY = fy - Float(screenPoint.y - viewSize.height / 2) / (newZoom * min(Float(viewSize.width), Float(viewSize.height)))
        zoom = newZoom
    }

    /// Pan by a screen-space delta.
    func pan(dx: Float, dy: Float, viewSize: CGSize) {
        let scale = 1.0 / (zoom * min(Float(viewSize.width), Float(viewSize.height)))
        centerX -= dx * scale
        centerY -= dy * scale
    }

    /// Update juliaC from a screen-space drag point.
    func updateJuliaCFromScreen(_ point: CGPoint, viewSize: CGSize) {
        let scale = 1.0 / (zoom * min(Float(viewSize.width), Float(viewSize.height)))
        juliaCX = centerX + Float(point.x - viewSize.width  / 2) * scale
        juliaCY = centerY + Float(point.y - viewSize.height / 2) * scale
    }

    // MARK: Iteration adaptation

    private func adaptIterations() {
        let depth = log2(zoom / 200.0)  // octaves of zoom from default
        maxIterations = min(2000, 256 + Int32(depth) * 32)
    }

    // MARK: Keyframe snapshot

    func keyframe(at time: Double) -> FractalKeyframe {
        FractalKeyframe(
            time: time,
            centerX: centerX, centerY: centerY,
            zoom: zoom,
            juliaCX: juliaCX, juliaCY: juliaCY,
            colorOffset: colorOffset,
            colorCycleLength: colorCycleLength,
            paletteIndex: paletteIndex,
            maxIterations: maxIterations,
            fractalType: fractalType
        )
    }

    /// Apply an interpolated keyframe to state.
    func apply(_ kf: FractalKeyframe) {
        centerX          = kf.centerX
        centerY          = kf.centerY
        zoom             = kf.zoom
        juliaCX          = kf.juliaCX
        juliaCY          = kf.juliaCY
        colorOffset      = kf.colorOffset
        colorCycleLength = kf.colorCycleLength
        paletteIndex     = kf.paletteIndex
        maxIterations    = kf.maxIterations
        fractalType      = kf.fractalType
    }

    // MARK: Reset

    func resetToDefaults() {
        centerX     = -0.5
        centerY     =  0.0
        zoom        =  200.0
        fractalType = .mandelbrot
        juliaCX     = -0.7
        juliaCY     =  0.27015
        paletteIndex       = 0
        colorOffset        = 0.0
        colorCycleLength   = 64.0
        colorRotationSpeed = 0.3
        isRotatingColors   = false
        maxIterations      = 256
    }
}
