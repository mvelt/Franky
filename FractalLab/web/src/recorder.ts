import type { FractalState } from './main';
import type { FractalRenderer } from './renderer';

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Keyframe model
// ─────────────────────────────────────────────────────────────────────────────

export interface FractalKeyframe {
  time: number;
  centerX: number; centerY: number;
  zoom: number;
  juliaCX: number; juliaCY: number;
  colorOffset: number;
  colorCycle: number;
  paletteIndex: number;    // discrete — snapped at t = 0.5
  maxIterations: number;   // discrete
  fractalType: number;     // discrete
}

function lerp(a: number, b: number, t: number) { return a + t * (b - a); }

/** Shortest arc between two colour offsets on the unit circle [0,1). */
function lerpColor(a: number, b: number, t: number) {
  let d = b - a;
  if (d >  0.5) d -= 1;
  if (d < -0.5) d += 1;
  let r = a + t * d;
  r = r % 1; if (r < 0) r += 1;
  return r;
}

function lerpKF(a: FractalKeyframe, b: FractalKeyframe, t: number): FractalKeyframe {
  return {
    time:         lerp(a.time, b.time, t),
    centerX:      lerp(a.centerX,  b.centerX,  t),
    centerY:      lerp(a.centerY,  b.centerY,  t),
    zoom:         lerp(a.zoom,     b.zoom,     t),
    juliaCX:      lerp(a.juliaCX,  b.juliaCX,  t),
    juliaCY:      lerp(a.juliaCY,  b.juliaCY,  t),
    colorOffset:  lerpColor(a.colorOffset, b.colorOffset, t),
    colorCycle:   lerp(a.colorCycle, b.colorCycle, t),
    // Discrete fields snap at midpoint
    paletteIndex:  t < 0.5 ? a.paletteIndex  : b.paletteIndex,
    maxIterations: t < 0.5 ? a.maxIterations : b.maxIterations,
    fractalType:   t < 0.5 ? a.fractalType   : b.fractalType,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – RecordedSession
// ─────────────────────────────────────────────────────────────────────────────

export class RecordedSession {
  readonly keyframes: FractalKeyframe[];
  readonly duration: number;

  constructor(keyframes: FractalKeyframe[]) {
    this.keyframes = keyframes;
    this.duration  = keyframes.at(-1)?.time ?? 0;
  }

  /** Interpolated keyframe at a given time (seconds). */
  frameAt(t: number): FractalKeyframe {
    const kf = this.keyframes;
    if (kf.length === 0) return kf[0];
    t = Math.max(0, Math.min(t, this.duration));

    // Binary search for surrounding pair
    let lo = 0, hi = kf.length - 1;
    while (lo < hi - 1) {
      const mid = (lo + hi) >> 1;
      if (kf[mid].time <= t) lo = mid; else hi = mid;
    }
    const a = kf[lo], b = kf[hi];
    if (a.time === b.time) return a;
    return lerpKF(a, b, (t - a.time) / (b.time - a.time));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – SessionRecorder
// ─────────────────────────────────────────────────────────────────────────────

export class SessionRecorder {
  private state: FractalState;
  private renderer: FractalRenderer;

  private captureInterval: ReturnType<typeof setInterval> | null = null;
  private recordStart = 0;
  private keyframes: FractalKeyframe[] = [];

  // Playback
  private playbackStart  = 0;   // performance.now() when playback began
  private playbackOffset = 0;   // session-time offset at start

  // Video recording
  private mediaRecorder: MediaRecorder | null = null;
  private videoChunks: BlobPart[] = [];

  // Callbacks (set by UI)
  onStateChange: (() => void) = () => {};

  constructor(state: FractalState, renderer: FractalRenderer) {
    this.state    = state;
    this.renderer = renderer;
  }

  // ── Recording ──────────────────────────────────────────────────────────────

  startRecording() {
    if (this.state.isRecording) return;
    this.keyframes = [];
    this.recordStart = performance.now();
    this.state.isRecording = true;
    this.captureKeyframe();

    this.captureInterval = setInterval(() => {
      this.captureKeyframe();
    }, 1000 / 30);

    this.onStateChange();
  }

  stopRecording() {
    if (!this.state.isRecording) return;
    clearInterval(this.captureInterval!);
    this.captureInterval = null;
    this.state.isRecording = false;

    if (this.keyframes.length > 1) {
      this.state.recordedSession = new RecordedSession([...this.keyframes]);
    }
    this.onStateChange();
  }

  private captureKeyframe() {
    const time = (performance.now() - this.recordStart) / 1000;
    this.keyframes.push({
      time,
      centerX:      this.state.centerX,
      centerY:      this.state.centerY,
      zoom:         this.state.zoom,
      juliaCX:      this.state.juliaCX,
      juliaCY:      this.state.juliaCY,
      colorOffset:  this.state.colorOffset,
      colorCycle:   this.state.colorCycle,
      paletteIndex: this.state.paletteIndex,
      maxIterations:this.state.maxIterations,
      fractalType:  this.state.fractalType,
    });
  }

  get recordingElapsed(): number {
    if (!this.state.isRecording) return 0;
    return (performance.now() - this.recordStart) / 1000;
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  startPlayback() {
    const session = this.state.recordedSession;
    if (!session || this.state.isPlayingBack) return;
    this.state.isPlayingBack = true;
    this.playbackOffset = this.state.playbackReversed ? session.duration : 0;
    this.playbackStart  = performance.now();
    this.onStateChange();
  }

  stopPlayback() {
    this.state.isPlayingBack = false;
    this.onStateChange();
  }

  /** Called every rAF tick while isPlayingBack. Returns false when playback ends. */
  tickPlayback(now: number): boolean {
    const session = this.state.recordedSession;
    if (!session) return false;

    const elapsed = (now - this.playbackStart) / 1000 * this.state.playbackSpeed;
    const t = this.state.playbackReversed
      ? this.playbackOffset - elapsed
      : this.playbackOffset + elapsed;

    const ended = this.state.playbackReversed ? t <= 0 : t >= session.duration;
    const clamped = Math.max(0, Math.min(t, session.duration));

    this.state.playbackPosition = clamped;
    const kf = session.frameAt(clamped);
    this.applyKeyframe(kf);

    if (ended) { this.stopPlayback(); return false; }
    return true;
  }

  private applyKeyframe(kf: FractalKeyframe) {
    this.state.centerX      = kf.centerX;
    this.state.centerY      = kf.centerY;
    this.state.zoom         = kf.zoom;
    this.state.juliaCX      = kf.juliaCX;
    this.state.juliaCY      = kf.juliaCY;
    this.state.colorOffset  = kf.colorOffset;
    this.state.colorCycle   = kf.colorCycle;
    this.state.paletteIndex = kf.paletteIndex;
    this.state.maxIterations = kf.maxIterations;
    this.state.fractalType  = kf.fractalType;
  }

  // ── Save PNG ───────────────────────────────────────────────────────────────

  async savePNG() {
    const blob = await this.renderer.snapshot();
    if (!blob) return;
    const url  = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href     = url;
    link.download = 'fractallab.png';
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  }

  // ── Video export ───────────────────────────────────────────────────────────
  // Captures the canvas stream while playing back the session.

  async exportVideo(canvas: HTMLCanvasElement): Promise<void> {
    const session = this.state.recordedSession;
    if (!session || this.state.isExportingVideo) return;

    const mimeType = MediaRecorder.isTypeSupported('video/mp4')
      ? 'video/mp4'
      : MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : 'video/webm';
    const ext = mimeType.startsWith('video/mp4') ? 'mp4' : 'webm';

    const stream = (canvas as HTMLCanvasElement & { captureStream(fps: number): MediaStream })
      .captureStream(30);
    this.mediaRecorder = new MediaRecorder(stream, { mimeType });
    this.videoChunks   = [];

    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) this.videoChunks.push(e.data);
    };

    // Save when MediaRecorder stops
    const done = new Promise<void>((resolve) => {
      this.mediaRecorder!.onstop = () => {
        const blob = new Blob(this.videoChunks, { type: mimeType });
        const url  = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href     = url;
        link.download = `fractallab.${ext}`;
        link.click();
        setTimeout(() => URL.revokeObjectURL(url), 10_000);
        resolve();
      };
    });

    this.state.isExportingVideo = true;
    this.mediaRecorder.start(100); // collect chunks every 100 ms

    // Rewind and play back the session (the render loop will call tickPlayback)
    this.state.playbackReversed = false;
    this.state.playbackSpeed    = 1.0;
    this.startPlayback();

    // Wait for playback to finish, then stop recorder
    const waitForEnd = () => {
      if (this.state.isPlayingBack) {
        requestAnimationFrame(waitForEnd);
      } else {
        this.mediaRecorder?.stop();
        this.state.isExportingVideo = false;
        this.onStateChange();
      }
    };
    requestAnimationFrame(waitForEnd);
    await done;
  }

  // ── Formatting helpers ─────────────────────────────────────────────────────

  formatTime(t: number): string {
    const m = Math.floor(t / 60);
    const s = Math.floor(t % 60);
    const f = Math.floor((t % 1) * 10);
    return `${m}:${String(s).padStart(2, '0')}.${f}`;
  }
}
