import './style.css';
import { FractalRenderer } from './renderer';
import { GestureHandler }  from './gestures';
import { SessionRecorder } from './recorder';
import { buildUI, updateUI, refreshUI, showToast } from './ui';
import type { RecordedSession } from './recorder';

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – State
// ─────────────────────────────────────────────────────────────────────────────

export interface FractalState {
  // View
  centerX: number;
  centerY: number;
  zoom: number;
  maxIterations: number;

  // Fractal type: 0 = Mandelbrot, 1 = Julia
  fractalType: number;
  juliaCX: number;
  juliaCY: number;
  juliaCPresetIndex: number;

  // Colour
  paletteIndex: number;
  colorOffset: number;
  colorCycle: number;
  colorRotationSpeed: number;
  isRotatingColors: boolean;

  // UI
  isDraggingJuliaC: boolean;

  // Recording
  isRecording: boolean;
  recordedSession: RecordedSession | null;

  // Playback
  isPlayingBack: boolean;
  playbackPosition: number;
  playbackSpeed: number;
  playbackReversed: boolean;

  // Export
  isExportingVideo: boolean;

  // Internal: dirty flag for render loop
  needsRender: boolean;
}

export function createDefaultState(): FractalState {
  return {
    centerX: -0.5, centerY: 0,
    zoom: 0.28,         // shows the full Mandelbrot set
    maxIterations: 256,

    fractalType: 0,
    juliaCX: -0.7, juliaCY: 0.27015,
    juliaCPresetIndex: 0,

    paletteIndex: 0,
    colorOffset: 0,
    colorCycle: 64,
    colorRotationSpeed: 0.3,
    isRotatingColors: false,

    isDraggingJuliaC: false,

    isRecording: false,
    recordedSession: null,

    isPlayingBack: false,
    playbackPosition: 0,
    playbackSpeed: 1,
    playbackReversed: false,

    isExportingVideo: false,
    needsRender: true,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Boot
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  const canvas = document.getElementById('fractal-canvas') as HTMLCanvasElement;

  // ── WebGPU availability check ────────────────────────────────────────────
  if (!navigator.gpu) {
    showError(
      'WebGPU Not Available',
      'FractalLab needs WebGPU.\n' +
      '• iPhone: update to iOS 17+ and open in Safari\n' +
      '• Desktop: use Chrome 113+, Edge 113+, or Safari 17+\n' +
      '• Enable WebGPU in Safari: Settings → Advanced → Experimental Features → WebGPU'
    );
    return;
  }

  const renderer = await FractalRenderer.create(canvas);
  if (!renderer) {
    showError('GPU Init Failed', 'Could not initialise a WebGPU device. Try reloading.');
    return;
  }

  const state    = createDefaultState();
  const recorder = new SessionRecorder(state, renderer);

  // ── Canvas sizing ────────────────────────────────────────────────────────
  function resizeCanvas() {
    const dpr = window.devicePixelRatio || 1;
    const w   = Math.floor(window.innerWidth  * dpr);
    const h   = Math.floor(window.innerHeight * dpr);
    canvas.width  = w;
    canvas.height = h;
    state.needsRender = true;
  }
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  // ── Build UI ─────────────────────────────────────────────────────────────
  const onStateChange = () => { state.needsRender = true; };

  recorder.onStateChange = () => {
    state.needsRender = true;
    refreshUI(state, recorder, canvas, onStateChange);
  };

  buildUI(state, recorder, canvas, onStateChange);

  // Register service worker
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => {/* non-critical */});
  }

  // ── Gestures ─────────────────────────────────────────────────────────────
  new GestureHandler(canvas, state, onStateChange);

  // ── Animation loop ───────────────────────────────────────────────────────
  let lastTime = 0;

  function frame(now: number) {
    requestAnimationFrame(frame);

    const dt = Math.min((now - lastTime) / 1000, 0.1); // cap at 100 ms
    lastTime = now;

    // Colour rotation
    if (state.isRotatingColors && !state.isPlayingBack) {
      state.colorOffset += state.colorRotationSpeed * dt;
      state.colorOffset = ((state.colorOffset % 1) + 1) % 1;
      state.needsRender = true;
    }

    // Playback tick
    if (state.isPlayingBack) {
      recorder.tickPlayback(now);
      state.needsRender = true;
    }

    // Render if dirty
    if (state.needsRender) {
      state.needsRender = false;
      renderer.updateUniforms(state, canvas.width, canvas.height);
      renderer.draw();
    }

    // Live UI updates (timer readouts etc.)
    updateUI(state, recorder);
  }

  requestAnimationFrame(frame);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Error display
// ─────────────────────────────────────────────────────────────────────────────

function showError(title: string, body: string) {
  const screen = document.getElementById('error-screen');
  if (!screen) return;
  screen.querySelector('h1')!.textContent = title;
  screen.querySelector('p')!.textContent  = body;
  screen.style.display = 'flex';
  document.getElementById('fractal-canvas')!.style.display = 'none';
  document.getElementById('ui-overlay')!.style.display = 'none';
}

main();
