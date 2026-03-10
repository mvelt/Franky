import SwiftUI
import MetalKit

// MARK: - MetalView

/// UIViewRepresentable wrapping MTKView.
/// Forwards gesture events to the parent view via callbacks.
struct MetalView: UIViewRepresentable {

    let renderer: FractalRenderer

    // Gesture callbacks — set by FractalCanvasView
    var onDoubleTap:       ((CGPoint) -> Void)?
    var onTwoFingerTap:    ((CGPoint) -> Void)?
    var onPinch:           ((CGFloat, CGPoint) -> Void)?
    var onPan:             ((CGSize) -> Void)?
    var onLongPressBegin:  ((CGPoint) -> Void)?
    var onLongPressMoved:  ((CGPoint) -> Void)?
    var onLongPressEnd:    (() -> Void)?

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate              = renderer
        view.colorPixelFormat      = .bgra8Unorm
        view.clearColor            = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly       = false      // allow texture reads for snapshots
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = true       // on-demand by default
        view.isPaused              = true       // manual control

        attachGestures(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: Gesture setup

    private func attachGestures(to view: UIView, coordinator: Coordinator) {
        // Double-tap (1 finger) → zoom in
        let doubleTap = UITapGestureRecognizer(
            target: coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTap)

        // Two-finger double-tap → zoom out
        let twoFingerTap = UITapGestureRecognizer(
            target: coordinator, action: #selector(Coordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTapsRequired = 2
        twoFingerTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoFingerTap)

        // Pinch → free zoom
        let pinch = UIPinchGestureRecognizer(
            target: coordinator, action: #selector(Coordinator.handlePinch))
        view.addGestureRecognizer(pinch)

        // Pan → translate
        let pan = UIPanGestureRecognizer(
            target: coordinator, action: #selector(Coordinator.handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        // Long press → Julia drag picker
        let longPress = UILongPressGestureRecognizer(
            target: coordinator, action: #selector(Coordinator.handleLongPress))
        longPress.minimumPressDuration = 0.4
        view.addGestureRecognizer(longPress)

        // Let pinch and pan work simultaneously
        coordinator.pinchGesture = pinch
        coordinator.panGesture   = pan
        pinch.delegate  = coordinator
        pan.delegate    = coordinator
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: MetalView
        var pinchGesture: UIPinchGestureRecognizer?
        var panGesture: UIPanGestureRecognizer?

        init(_ parent: MetalView) { self.parent = parent }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            parent.onDoubleTap?(g.location(in: g.view))
        }

        @objc func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
            parent.onTwoFingerTap?(g.location(in: g.view))
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .began || g.state == .changed {
                parent.onPinch?(g.scale, g.location(in: g.view))
                g.scale = 1.0
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            if g.state == .changed {
                let t = g.translation(in: g.view)
                parent.onPan?(CGSize(width: t.x, height: t.y))
                g.setTranslation(.zero, in: g.view)
            }
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:   parent.onLongPressBegin?(g.location(in: g.view))
            case .changed: parent.onLongPressMoved?(g.location(in: g.view))
            case .ended, .cancelled: parent.onLongPressEnd?()
            default: break
            }
        }

        // Allow pinch + pan simultaneously
        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            (g === pinchGesture && other === panGesture) ||
            (g === panGesture   && other === pinchGesture)
        }
    }
}
