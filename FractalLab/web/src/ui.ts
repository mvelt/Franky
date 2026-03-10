import { PALETTES, JULIA_PRESETS } from './palettes';
import type { FractalState } from './main';
import type { SessionRecorder } from './recorder';

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – UI builder
// ─────────────────────────────────────────────────────────────────────────────

export function buildUI(
  state: FractalState,
  recorder: SessionRecorder,
  canvas: HTMLCanvasElement,
  onStateChange: () => void,
) {
  const overlay = document.getElementById('ui-overlay')!;
  overlay.innerHTML = '';

  overlay.appendChild(buildControlPanel(state, recorder, canvas, onStateChange));
  overlay.appendChild(buildJuliaDragHint());
  overlay.appendChild(buildTransportBar(state, recorder, canvas, onStateChange));
  overlay.appendChild(buildToast());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Control panel
// ─────────────────────────────────────────────────────────────────────────────

function buildControlPanel(
  state: FractalState,
  recorder: SessionRecorder,
  canvas: HTMLCanvasElement,
  onStateChange: () => void,
) {
  const panel = document.createElement('div');
  panel.id = 'control-panel';

  // Toggle button
  const toggle = document.createElement('div');
  toggle.id = 'panel-toggle';
  const btn = document.createElement('button');
  btn.id = 'panel-toggle-btn';
  btn.textContent = '⚙';
  toggle.appendChild(btn);
  panel.appendChild(toggle);

  // Body
  const body = document.createElement('div');
  body.id = 'panel-body';
  const inner = document.createElement('div');
  inner.id = 'panel-inner';
  inner.className = 'glass';
  body.appendChild(inner);
  panel.appendChild(body);

  btn.addEventListener('click', () => body.classList.toggle('open'));
  // Open by default
  body.classList.add('open');

  // ── Fractal type ──────────────────────────────────────────────────────────
  inner.appendChild(sectionLabel('Fractal Type'));
  const typeRow = document.createElement('div');
  typeRow.className = 'pill-row';

  const types = [['Mandelbrot', 0], ['Julia', 1]] as const;
  types.forEach(([name, val]) => {
    const p = pill(name, state.fractalType === val);
    p.addEventListener('click', () => {
      state.fractalType = val;
      onStateChange();
      refreshUI(state, recorder, canvas, onStateChange);
    });
    typeRow.appendChild(p);
  });
  inner.appendChild(typeRow);

  // ── Julia section (shown when type === 1) ─────────────────────────────────
  const juliaSection = document.createElement('div');
  juliaSection.id = 'julia-section';
  juliaSection.style.display = state.fractalType === 1 ? '' : 'none';

  juliaSection.appendChild(sectionLabel('Julia Preset'));
  const presetsRow = document.createElement('div');
  presetsRow.id = 'julia-presets';
  JULIA_PRESETS.forEach((preset, i) => {
    const p = pill(preset.name, false);
    p.style.fontSize = '10px';
    p.addEventListener('click', () => {
      state.juliaCX = preset.cx;
      state.juliaCY = preset.cy;
      state.juliaCPresetIndex = i;
      onStateChange();
      refreshUI(state, recorder, canvas, onStateChange);
    });
    presetsRow.appendChild(p);
  });
  juliaSection.appendChild(presetsRow);

  const juliaReadout = document.createElement('div');
  juliaReadout.id = 'julia-readout';
  juliaReadout.className = 'section-label';
  juliaReadout.style.marginTop = '4px';
  juliaSection.appendChild(juliaReadout);

  const dragHint = document.createElement('div');
  dragHint.className = 'section-label';
  dragHint.textContent = 'Long-press canvas to drag c';
  dragHint.style.opacity = '0.5';
  juliaSection.appendChild(dragHint);

  inner.appendChild(juliaSection);
  inner.appendChild(divider());

  // ── Palette ───────────────────────────────────────────────────────────────
  inner.appendChild(sectionLabel('Colour Palette'));
  const grid = document.createElement('div');
  grid.id = 'palette-grid';

  PALETTES.forEach((pal, i) => {
    const sw = document.createElement('div');
    sw.className = `palette-swatch${state.paletteIndex === i ? ' active' : ''}`;
    const bar = document.createElement('div');
    bar.className = 'swatch-bar';
    bar.style.background =
      `linear-gradient(to right, ${pal.previewColors.join(',')})`;
    const name = document.createElement('div');
    name.className = 'swatch-name';
    name.textContent = pal.name;
    sw.appendChild(bar);
    sw.appendChild(name);
    sw.addEventListener('click', () => {
      state.paletteIndex = i;
      onStateChange();
      refreshUI(state, recorder, canvas, onStateChange);
    });
    grid.appendChild(sw);
  });
  inner.appendChild(grid);
  inner.appendChild(divider());

  // ── Colour rotation ───────────────────────────────────────────────────────
  inner.appendChild(sectionLabel('Colour Rotation'));
  const rotRow = document.createElement('div');
  rotRow.className = 'icon-btn-row';

  const btnRev  = iconBtn('◀◀');
  const btnPlay = iconBtn('▶');
  const btnFwd  = iconBtn('▶▶');

  btnRev.addEventListener('click', () => {
    state.colorRotationSpeed = -Math.abs(state.colorRotationSpeed);
    state.isRotatingColors = true;
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });
  btnPlay.addEventListener('click', () => {
    state.isRotatingColors = !state.isRotatingColors;
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });
  btnFwd.addEventListener('click', () => {
    state.colorRotationSpeed = Math.abs(state.colorRotationSpeed);
    state.isRotatingColors = true;
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });

  rotRow.append(btnRev, btnPlay, btnFwd);
  inner.appendChild(rotRow);

  const speedRow = sliderRow(
    '🐢', '🐇',
    Math.abs(state.colorRotationSpeed), 0.02, 2.0, 0.01,
    (v) => {
      state.colorRotationSpeed = Math.sign(state.colorRotationSpeed || 1) * v;
      onStateChange();
    }
  );
  inner.appendChild(speedRow);

  const densityRow = sliderRow(
    'Dense', 'Sparse',
    state.colorCycle, 8, 256, 1,
    (v) => { state.colorCycle = v; onStateChange(); }
  );
  inner.appendChild(densityRow);
  inner.appendChild(divider());

  // ── Max iterations ────────────────────────────────────────────────────────
  const iterLabel = document.createElement('div');
  iterLabel.id = 'iter-label';
  iterLabel.className = 'section-label';
  iterLabel.textContent = `Max Iterations: ${state.maxIterations}`;
  inner.appendChild(iterLabel);

  const iterRow = sliderRow('64', '2000', state.maxIterations, 64, 2000, 32, (v) => {
    state.maxIterations = Math.round(v);
    onStateChange();
    (document.getElementById('iter-label') as HTMLElement).textContent =
      `Max Iterations: ${state.maxIterations}`;
  });
  inner.appendChild(iterRow);
  inner.appendChild(divider());

  // ── Actions ───────────────────────────────────────────────────────────────
  const actRow = document.createElement('div');
  actRow.className = 'icon-btn-row';

  const saveBtn  = iconBtn('📷 Save PNG');
  const resetBtn = iconBtn('↺ Reset');

  saveBtn.addEventListener('click', async () => {
    await recorder.savePNG();
    showToast('Saving to Photos…');
  });
  resetBtn.addEventListener('click', () => {
    Object.assign(state, defaultState());
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });

  actRow.append(saveBtn, resetBtn);
  inner.appendChild(actRow);

  return panel;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Julia drag hint
// ─────────────────────────────────────────────────────────────────────────────

function buildJuliaDragHint() {
  const el = document.createElement('div');
  el.id = 'julia-drag-hint';
  el.textContent = 'Drag to set Julia c';
  return el;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Transport bar
// ─────────────────────────────────────────────────────────────────────────────

function buildTransportBar(
  state: FractalState,
  recorder: SessionRecorder,
  canvas: HTMLCanvasElement,
  onStateChange: () => void,
) {
  const bar = document.createElement('div');
  bar.id = 'transport-bar';
  bar.className = 'glass';

  if (state.isRecording) {
    buildRecordingBar(bar, state, recorder, onStateChange);
  } else if (state.isPlayingBack || state.isExportingVideo) {
    buildPlaybackBar(bar, state, recorder, canvas, onStateChange);
  } else {
    buildIdleBar(bar, state, recorder, canvas, onStateChange);
  }

  return bar;
}

function buildIdleBar(
  bar: HTMLElement,
  state: FractalState,
  recorder: SessionRecorder,
  canvas: HTMLCanvasElement,
  onStateChange: () => void,
) {
  const recBtn = transportBtn('⏺', 'danger');
  recBtn.title = 'Start recording';
  recBtn.addEventListener('click', () => {
    recorder.startRecording();
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });
  bar.appendChild(recBtn);

  if (state.recordedSession) {
    const playBtn = transportBtn('▶');
    playBtn.title = 'Play back session';
    playBtn.addEventListener('click', () => {
      recorder.startPlayback();
      onStateChange();
      refreshUI(state, recorder, canvas, onStateChange);
    });
    bar.appendChild(playBtn);

    const saveVidBtn = transportBtn('🎬');
    saveVidBtn.title = 'Export video';
    saveVidBtn.addEventListener('click', async () => {
      await recorder.exportVideo(canvas);
      refreshUI(state, recorder, canvas, onStateChange);
    });
    bar.appendChild(saveVidBtn);
  }

  const saveImgBtn = transportBtn('📷');
  saveImgBtn.title = 'Save PNG';
  saveImgBtn.addEventListener('click', async () => {
    await recorder.savePNG();
    showToast('Image saved');
  });
  bar.appendChild(saveImgBtn);
}

function buildRecordingBar(
  bar: HTMLElement,
  state: FractalState,
  recorder: SessionRecorder,
  onStateChange: () => void,
) {
  const dot = document.createElement('div');
  dot.id = 'rec-dot';
  bar.appendChild(dot);

  const timeEl = document.createElement('span');
  timeEl.id = 'transport-time';
  timeEl.textContent = '0:00.0';
  bar.appendChild(timeEl);

  const stopBtn = transportBtn('⏹', 'danger');
  stopBtn.title = 'Stop recording';
  stopBtn.addEventListener('click', () => {
    recorder.stopRecording();
    onStateChange();
    // Rebuild UI (no canvas available here but can be passed in via closure)
  });
  bar.appendChild(stopBtn);
}

function buildPlaybackBar(
  bar: HTMLElement,
  state: FractalState,
  recorder: SessionRecorder,
  canvas: HTMLCanvasElement,
  onStateChange: () => void,
) {
  const revBtn = transportBtn(state.playbackReversed ? '⏩' : '⏪');
  revBtn.title = 'Toggle direction';
  revBtn.addEventListener('click', () => {
    state.playbackReversed = !state.playbackReversed;
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });
  bar.appendChild(revBtn);

  const slowerBtn = transportBtn('−');
  slowerBtn.title = 'Slower';
  slowerBtn.addEventListener('click', () => {
    state.playbackSpeed = Math.max(0.25, state.playbackSpeed / 2);
    onStateChange();
    const el = bar.querySelector('#playback-speed');
    if (el) el.textContent = formatSpeed(state.playbackSpeed);
  });
  bar.appendChild(slowerBtn);

  const speedEl = document.createElement('span');
  speedEl.id = 'playback-speed';
  speedEl.id = 'transport-time';
  speedEl.textContent = formatSpeed(state.playbackSpeed);
  bar.appendChild(speedEl);

  const fasterBtn = transportBtn('+');
  fasterBtn.title = 'Faster';
  fasterBtn.addEventListener('click', () => {
    state.playbackSpeed = Math.min(4, state.playbackSpeed * 2);
    onStateChange();
    const el = bar.querySelector('#transport-time');
    if (el) el.textContent = formatSpeed(state.playbackSpeed);
  });
  bar.appendChild(fasterBtn);

  const posEl = document.createElement('span');
  posEl.className = 'section-label';
  posEl.id = 'playback-pos';
  posEl.style.minWidth = '80px';
  posEl.style.textAlign = 'center';
  bar.appendChild(posEl);

  const stopBtn = transportBtn('⏹');
  stopBtn.title = 'Stop playback';
  stopBtn.addEventListener('click', () => {
    recorder.stopPlayback();
    onStateChange();
    refreshUI(state, recorder, canvas, onStateChange);
  });
  bar.appendChild(stopBtn);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Live update (called every rAF)
// ─────────────────────────────────────────────────────────────────────────────

export function updateUI(state: FractalState, recorder: SessionRecorder) {
  // Recording timer
  if (state.isRecording) {
    const el = document.getElementById('transport-time');
    if (el) el.textContent = recorder.formatTime(recorder.recordingElapsed);
  }

  // Playback position
  if (state.isPlayingBack) {
    const el = document.getElementById('playback-pos');
    const session = state.recordedSession;
    if (el && session) {
      el.textContent =
        `${recorder.formatTime(state.playbackPosition)} / ${recorder.formatTime(session.duration)}`;
    }
  }

  // Julia drag hint
  const hint = document.getElementById('julia-drag-hint');
  if (hint) hint.classList.toggle('visible', state.isDraggingJuliaC);

  // Julia c readout
  if (state.fractalType === 1) {
    const el = document.getElementById('julia-readout');
    if (el) {
      el.textContent =
        `c = ${state.juliaCX.toFixed(4)} ${state.juliaCY >= 0 ? '+' : ''}${state.juliaCY.toFixed(4)}i`;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Full UI refresh (when state changes structurally)
// ─────────────────────────────────────────────────────────────────────────────

export function refreshUI(
  state: FractalState,
  recorder: SessionRecorder,
  canvas: HTMLCanvasElement,
  onStateChange: () => void,
) {
  buildUI(state, recorder, canvas, onStateChange);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Toast
// ─────────────────────────────────────────────────────────────────────────────

function buildToast() {
  const el = document.createElement('div');
  el.id = 'toast';
  return el;
}

let toastTimeout: ReturnType<typeof setTimeout> | null = null;

export function showToast(msg: string) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.classList.add('visible');
  if (toastTimeout) clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => el.classList.remove('visible'), 2500);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Element helpers
// ─────────────────────────────────────────────────────────────────────────────

function sectionLabel(text: string) {
  const el = document.createElement('div');
  el.className = 'section-label';
  el.textContent = text;
  return el;
}

function divider() {
  const el = document.createElement('div');
  el.className = 'divider';
  return el;
}

function pill(text: string, active: boolean) {
  const el = document.createElement('button');
  el.className = `pill${active ? ' active' : ''}`;
  el.textContent = text;
  return el;
}

function iconBtn(text: string) {
  const el = document.createElement('button');
  el.className = 'icon-btn';
  el.textContent = text;
  return el;
}

function transportBtn(icon: string, cls?: string) {
  const el = document.createElement('button');
  el.className = `transport-btn${cls ? ' ' + cls : ''}`;
  el.textContent = icon;
  return el;
}

function sliderRow(
  minLabel: string,
  maxLabel: string,
  value: number,
  min: number,
  max: number,
  step: number,
  onChange: (v: number) => void,
) {
  const row = document.createElement('div');
  row.className = 'slider-row';

  const minEl = document.createElement('span');
  minEl.textContent = minLabel;

  const slider = document.createElement('input');
  slider.type  = 'range';
  slider.min   = String(min);
  slider.max   = String(max);
  slider.step  = String(step);
  slider.value = String(value);
  slider.addEventListener('input', () => onChange(parseFloat(slider.value)));

  const maxEl = document.createElement('span');
  maxEl.textContent = maxLabel;

  row.append(minEl, slider, maxEl);
  return row;
}

function formatSpeed(s: number): string {
  if (s === 1) return '1×';
  if (s < 1)   return `${s.toFixed(2)}×`;
  return `${s}×`;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Default state (imported here to avoid circular dep with main.ts)
// ─────────────────────────────────────────────────────────────────────────────

import { createDefaultState } from './main';
function defaultState() { return createDefaultState(); }
