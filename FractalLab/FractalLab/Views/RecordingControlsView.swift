import SwiftUI

// MARK: - RecordingControlsView

/// Transport bar at the bottom for recording and playback control.
struct RecordingControlsView: View {

    @ObservedObject var state: FractalState
    let recorder: SessionRecorder

    @State private var showExportMenu: Bool = false

    var body: some View {
        HStack(spacing: 16) {

            if state.isPlayingBack {
                // ── Playback transport ────────────────────────────────────
                playbackControls
            } else if state.isRecording {
                // ── Recording indicator ───────────────────────────────────
                recordingIndicator
            } else {
                // ── Idle state ────────────────────────────────────────────
                idleControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
        .shadow(radius: 8)
        .confirmationDialog("Export", isPresented: $showExportMenu) {
            Button("Save Frame to Photos") { recorder.saveCurrentFrame() }
            if state.recordedSession != nil {
                Button("Export Video") { recorder.exportVideo() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sub-views

    private var idleControls: some View {
        HStack(spacing: 16) {
            // Record button
            Button {
                recorder.startRecording()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Record")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
            }

            if state.recordedSession != nil {
                // Play button
                Button {
                    recorder.startPlayback()
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                }

                // Export button
                Button {
                    showExportMenu = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                }
            } else {
                // Save photo shortcut when no session recorded
                Button {
                    recorder.saveCurrentFrame()
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                }
            }
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 12) {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: state.isRecording)
                .onAppear { /* trigger animation */ }

            Text(recorder.recordingDurationFormatted)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white)

            Spacer()

            Button {
                recorder.stopRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .font(.subheadline)
                    .padding(8)
                    .background(Color.red.opacity(0.8), in: Circle())
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            // Reverse toggle
            Button {
                state.playbackReversed.toggle()
            } label: {
                Image(systemName: state.playbackReversed ? "forward.fill" : "backward.fill")
                    .foregroundStyle(state.playbackReversed ? .yellow : .white)
                    .font(.subheadline)
            }

            // Slower
            Button {
                state.playbackSpeed = max(0.25, state.playbackSpeed / 2.0)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }

            // Speed readout
            Text(speedLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 36)

            // Faster
            Button {
                state.playbackSpeed = min(4.0, state.playbackSpeed * 2.0)
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }

            Spacer()

            // Progress
            Text(recorder.playbackPositionFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))

            // Stop
            Button {
                recorder.stopPlayback()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .font(.subheadline)
                    .padding(8)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
        }
    }

    private var speedLabel: String {
        let s = state.playbackSpeed
        if s == 1.0 { return "1×" }
        if s < 1.0  { return String(format: "%.2g×", s) }
        return String(format: "%.4g×", s)
    }
}
