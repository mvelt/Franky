import Foundation
import Photos
import UIKit
import Combine

// MARK: - SessionRecorder

/// Manages keyframe capture during recording and frame-by-frame playback.
@MainActor
final class SessionRecorder: ObservableObject {

    // MARK: Dependencies
    let state: FractalState
    let renderer: FractalRenderer
    let exporter: VideoExporter

    // MARK: Recording state
    private var keyframes: [FractalKeyframe] = []
    private var recordingStartTime: Date?
    private var captureTimer: Timer?

    // MARK: Playback state
    private var playbackDisplayLink: CADisplayLink?
    private var playbackStartTime: Date?
    private var playbackBaseOffset: Double = 0   // time offset at last speed/direction change
    private var playbackBaseDate: Date?

    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var playbackPosition: TimeInterval = 0

    // MARK: Init

    init(state: FractalState, renderer: FractalRenderer) {
        self.state    = state
        self.renderer = renderer
        self.exporter = VideoExporter(renderer: renderer, state: state)
    }

    // MARK: Duration formatting

    var recordingDurationFormatted: String { formatDuration(recordingElapsed) }
    var playbackPositionFormatted: String {
        let total = state.recordedSession?.duration ?? 0
        return "\(formatDuration(playbackPosition)) / \(formatDuration(total))"
    }

    // MARK: Recording

    func startRecording() {
        guard !state.isRecording else { return }
        keyframes.removeAll()
        recordingElapsed   = 0
        recordingStartTime = Date()
        state.isRecording  = true
        captureKeyframe()

        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureKeyframe() }
        }
    }

    func stopRecording() {
        captureTimer?.invalidate()
        captureTimer = nil
        state.isRecording = false

        guard keyframes.count > 1 else { return }
        state.recordedSession = RecordedSession(keyframes: keyframes)
    }

    private func captureKeyframe() {
        guard let start = recordingStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        recordingElapsed = elapsed
        keyframes.append(state.keyframe(at: elapsed))
    }

    // MARK: Playback

    func startPlayback() {
        guard let session = state.recordedSession, !state.isPlayingBack else { return }
        state.isPlayingBack = true
        playbackBaseOffset  = state.playbackReversed ? session.duration : 0
        playbackBaseDate    = Date()

        let dl = CADisplayLink(target: DisplayLinkTarget { [weak self] in
            Task { @MainActor [weak self] in self?.tickPlayback() }
        }, selector: #selector(DisplayLinkTarget.tick))
        dl.add(to: .main, forMode: .common)
        playbackDisplayLink = dl
    }

    func stopPlayback() {
        playbackDisplayLink?.invalidate()
        playbackDisplayLink = nil
        state.isPlayingBack = false
        playbackPosition    = 0
    }

    private func tickPlayback() {
        guard
            let session  = state.recordedSession,
            let baseDate = playbackBaseDate
        else { return }

        let elapsed = Date().timeIntervalSince(baseDate) * Double(state.playbackSpeed)
        var t = playbackBaseOffset + (state.playbackReversed ? -elapsed : elapsed)

        if t >= session.duration {
            t = session.duration
            defer { stopPlayback() }
        } else if t <= 0 {
            t = 0
            defer { stopPlayback() }
        }

        playbackPosition = t

        if let kf = session.frame(at: t) {
            state.apply(kf)
        }
    }

    // MARK: Save frame to Photos

    func saveCurrentFrame() {
        guard
            let view = UIApplication.shared.firstKeyWindow?.rootViewController?.view,
            let renderer = Optional(renderer)
        else { return }

        let size = view.bounds.size
        guard let tex = renderer.renderOffscreen(
            width: Int(size.width * UIScreen.main.scale),
            height: Int(size.height * UIScreen.main.scale)
        ), let image = tex.toUIImage(device: renderer.device, queue: renderer.device.makeCommandQueue()!) else {
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }

    // MARK: Export video

    func exportVideo() {
        guard let session = state.recordedSession else { return }
        Task {
            await exporter.export(session: session)
        }
    }

    // MARK: Helpers

    private func formatDuration(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let frac = Int((t - Double(Int(t))) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }
}

// MARK: - DisplayLinkTarget (avoids retain cycles)

private final class DisplayLinkTarget {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func tick() { block() }
}

// MARK: - UIApplication helper

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
