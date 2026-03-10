import SwiftUI
import Metal

// MARK: - ContentView

struct ContentView: View {

    // Core objects (long-lived, created once)
    @StateObject private var state    = FractalState()
    @State       private var renderer: FractalRenderer?
    @State       private var recorder: SessionRecorder?

    // Colour rotation timer
    @State private var colorTimer: Timer?

    // Toast messages
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            // ── Full-screen fractal ───────────────────────────────────────
            if let rend = renderer, let rec = recorder {
                FractalCanvasView(state: state, renderer: rend)
                    .ignoresSafeArea()

                // ── Overlays ──────────────────────────────────────────────
                VStack {
                    // Control panel (top-right)
                    HStack {
                        Spacer()
                        ControlPanelView(state: state) {
                            rec.saveCurrentFrame()
                            showToast("Saved to Photos")
                        }
                    }

                    Spacer()

                    // Julia drag hint
                    if state.isDraggingJuliaC {
                        Text("Drag to set Julia c")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity)
                    }

                    // Recording transport bar (bottom)
                    RecordingControlsView(state: state, recorder: rec)
                }

                // ── Export progress overlay ───────────────────────────────
                if state.isExporting {
                    exportProgressOverlay
                }

                // ── Toast ─────────────────────────────────────────────────
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(.bottom, 120)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

            } else {
                // ── Loading / no-Metal fallback ───────────────────────────
                Color.black.ignoresSafeArea()
                Text("Initialising Metal…")
                    .foregroundStyle(.white)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { setup() }
        .onChange(of: state.isRotatingColors) { _, rotating in
            if rotating { startColorTimer() } else { stopColorTimer() }
        }
        .onChange(of: state.isPlayingBack) { _, playing in
            // Let MTKView run continuously during playback for responsiveness
            // (renderer's onFrameRendered already calls setNeedsDisplay)
        }
    }

    // MARK: Export overlay

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: Double(state.exportProgress))
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                    .accentColor(.white)
                Text("Exporting \(Int(state.exportProgress * 100))%")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Setup

    private func setup() {
        guard renderer == nil else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ContentView: Metal not available")
            return
        }
        guard let rend = FractalRenderer(device: device) else {
            print("ContentView: FractalRenderer init failed")
            return
        }
        let rec = SessionRecorder(state: state, renderer: rend)
        renderer = rend
        recorder = rec
    }

    // MARK: Colour rotation timer

    private func startColorTimer() {
        colorTimer?.invalidate()
        colorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak state] _ in
            guard let state else { return }
            Task { @MainActor in
                var next = state.colorOffset + state.colorRotationSpeed / 60.0
                next = next.truncatingRemainder(dividingBy: 1.0)
                if next < 0 { next += 1.0 }
                state.colorOffset = next
            }
        }
    }

    private func stopColorTimer() {
        colorTimer?.invalidate()
        colorTimer = nil
    }

    // MARK: Toast helper

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring) { toastMessage = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.spring) { toastMessage = nil }
        }
    }
}
