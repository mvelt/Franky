import SwiftUI
import MetalKit

// MARK: - FractalCanvasView

/// Full-screen Metal canvas with all gesture handling.
/// Sits behind the control overlay in ContentView.
struct FractalCanvasView: View {

    @ObservedObject var state: FractalState
    let renderer: FractalRenderer

    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            MetalView(renderer: renderer,
                      onDoubleTap:      { pt in handleDoubleTap(at: pt) },
                      onTwoFingerTap:   { pt in handleTwoFingerTap(at: pt) },
                      onPinch:          { scale, pt in handlePinch(scale: scale, at: pt) },
                      onPan:            { delta in handlePan(delta: delta) },
                      onLongPressBegin: { pt in handleLongPressBegin(at: pt) },
                      onLongPressMoved: { pt in handleLongPressMoved(at: pt) },
                      onLongPressEnd:   { handleLongPressEnd() })
                .ignoresSafeArea()
                .onAppear {
                    viewSize = geo.size
                    syncRenderer()
                }
                .onChange(of: geo.size) { _, newSize in
                    viewSize = newSize
                }
                .onChange(of: state.centerX)         { _, _ in syncRenderer() }
                .onChange(of: state.centerY)         { _, _ in syncRenderer() }
                .onChange(of: state.zoom)            { _, _ in syncRenderer() }
                .onChange(of: state.fractalType)     { _, _ in syncRenderer() }
                .onChange(of: state.juliaCX)         { _, _ in syncRenderer() }
                .onChange(of: state.juliaCY)         { _, _ in syncRenderer() }
                .onChange(of: state.colorOffset)     { _, _ in syncRenderer() }
                .onChange(of: state.colorCycleLength){ _, _ in syncRenderer() }
                .onChange(of: state.paletteIndex)    { _, _ in syncRenderer() }
                .onChange(of: state.maxIterations)   { _, _ in syncRenderer() }
        }
    }

    // MARK: Sync renderer params

    private func syncRenderer() {
        renderer.params = state.makeParams(
            viewWidth:  Float(viewSize.width),
            viewHeight: Float(viewSize.height)
        )
    }

    // MARK: Gesture handlers

    private func handleDoubleTap(at point: CGPoint) {
        state.zoomIn(at: point, viewSize: viewSize)
    }

    private func handleTwoFingerTap(at point: CGPoint) {
        state.zoomOut(at: point, viewSize: viewSize)
    }

    private func handlePinch(scale: CGFloat, at point: CGPoint) {
        state.applyPinch(scale: Float(scale), at: point, viewSize: viewSize)
    }

    private func handlePan(delta: CGSize) {
        state.pan(dx: Float(delta.width), dy: Float(delta.height), viewSize: viewSize)
    }

    /// Long-press on Mandelbrot switches to Julia and starts drag picking c.
    private func handleLongPressBegin(at point: CGPoint) {
        if state.fractalType == .mandelbrot {
            state.fractalType = .julia
        }
        state.isDraggingJuliaC = true
        state.updateJuliaCFromScreen(point, viewSize: viewSize)
    }

    private func handleLongPressMoved(at point: CGPoint) {
        if state.isDraggingJuliaC {
            state.updateJuliaCFromScreen(point, viewSize: viewSize)
        }
    }

    private func handleLongPressEnd() {
        state.isDraggingJuliaC = false
    }
}
