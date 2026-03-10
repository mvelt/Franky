import type { FractalState } from './main';

const LONG_PRESS_MS   = 400;
const DOUBLE_TAP_MS   = 400;
const DOUBLE_TAP_PX   = 40;   // max movement between two taps
const TAP_MOVE_PX     = 10;   // max movement to count as a tap (not a drag)

interface TouchInfo {
  id: number;
  startX: number; startY: number;
  curX: number;   curY: number;
  startTime: number;
}

export class GestureHandler {
  private canvas: HTMLCanvasElement;
  private state: FractalState;
  private onNeedsRender: () => void;

  private touches = new Map<number, TouchInfo>();
  private longPressTimer: ReturnType<typeof setTimeout> | null = null;
  private lastTap: { x: number; y: number; time: number; fingers: number } | null = null;
  private prevPinchDist = 0;
  private prevPinchMidX = 0;
  private prevPinchMidY = 0;

  constructor(canvas: HTMLCanvasElement, state: FractalState, onNeedsRender: () => void) {
    this.canvas = canvas;
    this.state  = state;
    this.onNeedsRender = onNeedsRender;
    this.attach();
  }

  private attach() {
    const c = this.canvas;
    c.addEventListener('touchstart',  this.onTouchStart,  { passive: false });
    c.addEventListener('touchmove',   this.onTouchMove,   { passive: false });
    c.addEventListener('touchend',    this.onTouchEnd,    { passive: false });
    c.addEventListener('touchcancel', this.onTouchCancel, { passive: false });
    // Desktop mouse support
    c.addEventListener('mousedown',   this.onMouseDown);
    c.addEventListener('mousemove',   this.onMouseMove);
    c.addEventListener('mouseup',     this.onMouseUp);
    c.addEventListener('wheel',       this.onWheel,       { passive: false });
  }

  // ── Touch events ─────────────────────────────────────────────────────────────

  private onTouchStart = (e: TouchEvent) => {
    e.preventDefault();
    const now = Date.now();

    for (const t of e.changedTouches) {
      this.touches.set(t.identifier, {
        id: t.identifier,
        startX: t.clientX, startY: t.clientY,
        curX:   t.clientX, curY:   t.clientY,
        startTime: now,
      });
    }

    // Start long-press timer (cancelled if finger moves or a second finger appears)
    if (this.touches.size === 1 && e.changedTouches.length === 1) {
      const t = e.changedTouches[0];
      this.longPressTimer = setTimeout(() => {
        this.state.isDraggingJuliaC = true;
        if (this.state.fractalType === 0) this.state.fractalType = 1; // switch to Julia
        this.updateJuliaCFromPoint(t.clientX, t.clientY);
        this.onNeedsRender();
      }, LONG_PRESS_MS);
    }
  };

  private onTouchMove = (e: TouchEvent) => {
    e.preventDefault();
    this.clearLongPress();

    for (const t of e.changedTouches) {
      const info = this.touches.get(t.identifier);
      if (info) { info.curX = t.clientX; info.curY = t.clientY; }
    }

    const active = [...this.touches.values()];

    if (active.length === 1 && !this.state.isDraggingJuliaC) {
      // Single-finger pan
      const t = e.changedTouches[0];
      const info = this.touches.get(t.identifier);
      if (!info) return;
      const dx = t.clientX - info.curX + (t.clientX - info.curX);
      // Use raw delta between consecutive move events
      // We need to track previous position; use info.curX before we update
      const prevX = info.curX - (t.clientX - info.curX);
      const prevY = info.curY - (t.clientY - info.curY);
      const deltaX = t.clientX - prevX;
      const deltaY = t.clientY - prevY;
      this.pan(deltaX, deltaY);

    } else if (active.length === 1 && this.state.isDraggingJuliaC) {
      const t = e.changedTouches[0];
      this.updateJuliaCFromPoint(t.clientX, t.clientY);

    } else if (active.length === 2) {
      const [a, b] = active;
      const dist = Math.hypot(b.curX - a.curX, b.curY - a.curY);
      const midX = (a.curX + b.curX) / 2;
      const midY = (a.curY + b.curY) / 2;

      if (this.prevPinchDist > 0) {
        const scale = dist / this.prevPinchDist;
        this.zoom(scale, midX, midY);
        this.pan(midX - this.prevPinchMidX, midY - this.prevPinchMidY);
      }

      this.prevPinchDist = dist;
      this.prevPinchMidX = midX;
      this.prevPinchMidY = midY;
    }

    // Update stored positions for next move event
    for (const t of e.changedTouches) {
      const info = this.touches.get(t.identifier);
      if (info) { info.curX = t.clientX; info.curY = t.clientY; }
    }

    this.onNeedsRender();
  };

  private onTouchEnd = (e: TouchEvent) => {
    e.preventDefault();
    this.clearLongPress();
    const now = Date.now();

    if (this.state.isDraggingJuliaC) {
      this.state.isDraggingJuliaC = false;
      for (const t of e.changedTouches) this.touches.delete(t.identifier);
      this.resetPinch();
      this.onNeedsRender();
      return;
    }

    const fingerCount = this.touches.size;

    for (const t of e.changedTouches) {
      const info = this.touches.get(t.identifier);
      if (info) {
        const elapsed = now - info.startTime;
        const moved   = Math.hypot(t.clientX - info.startX, t.clientY - info.startY);
        const isTap   = elapsed < 500 && moved < TAP_MOVE_PX;

        if (isTap) {
          this.handleTap(t.clientX, t.clientY, fingerCount, now);
        }
      }
      this.touches.delete(t.identifier);
    }

    if (this.touches.size < 2) this.resetPinch();
  };

  private onTouchCancel = (e: TouchEvent) => {
    this.clearLongPress();
    this.state.isDraggingJuliaC = false;
    for (const t of e.changedTouches) this.touches.delete(t.identifier);
    this.resetPinch();
  };

  // ── Mouse events (desktop) ───────────────────────────────────────────────────

  private mouseDown = false;
  private lastMouseX = 0;
  private lastMouseY = 0;
  private mouseDownTime = 0;

  private onMouseDown = (e: MouseEvent) => {
    this.mouseDown = true;
    this.lastMouseX = e.clientX;
    this.lastMouseY = e.clientY;
    this.mouseDownTime = Date.now();
  };

  private onMouseMove = (e: MouseEvent) => {
    if (!this.mouseDown) return;
    this.pan(e.clientX - this.lastMouseX, e.clientY - this.lastMouseY);
    this.lastMouseX = e.clientX;
    this.lastMouseY = e.clientY;
    this.onNeedsRender();
  };

  private onMouseUp = (e: MouseEvent) => {
    const elapsed = Date.now() - this.mouseDownTime;
    const moved   = Math.hypot(e.clientX - this.lastMouseX, e.clientY - this.lastMouseY);
    if (elapsed < 300 && moved < TAP_MOVE_PX) {
      this.handleTap(e.clientX, e.clientY, 1, Date.now());
    }
    this.mouseDown = false;
  };

  private onWheel = (e: WheelEvent) => {
    e.preventDefault();
    const scale = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    this.zoom(scale, e.clientX, e.clientY);
    this.onNeedsRender();
  };

  // ── Tap / double-tap detection ───────────────────────────────────────────────

  private handleTap(x: number, y: number, fingers: number, now: number) {
    const last = this.lastTap;
    const isDouble =
      last &&
      (now - last.time) < DOUBLE_TAP_MS &&
      Math.hypot(x - last.x, y - last.y) < DOUBLE_TAP_PX;

    if (isDouble && last) {
      if (fingers === 1 || last.fingers === 1) {
        // Double-tap 1 finger → zoom in
        this.zoomStep(2, x, y);
      } else {
        // Double-tap 2 fingers → zoom out
        this.zoomStep(0.5, x, y);
      }
      this.lastTap = null;
    } else {
      this.lastTap = { x, y, time: now, fingers };
    }
  }

  // ── Fractal operations ───────────────────────────────────────────────────────

  private pan(dx: number, dy: number) {
    const minDim = Math.min(this.canvas.width, this.canvas.height);
    const scale  = 1 / (this.state.zoom * minDim);
    const dpr    = window.devicePixelRatio || 1;
    this.state.centerX -= (dx * dpr) * scale;
    this.state.centerY -= (dy * dpr) * scale;
  }

  private zoom(scale: number, screenX: number, screenY: number) {
    const dpr    = window.devicePixelRatio || 1;
    const minDim = Math.min(this.canvas.width, this.canvas.height);
    const s      = 1 / (this.state.zoom * minDim);
    const fx = this.state.centerX + (screenX * dpr - this.canvas.width  / 2) * s;
    const fy = this.state.centerY + (screenY * dpr - this.canvas.height / 2) * s;
    const newZoom = Math.max(0.05, this.state.zoom * scale);
    this.state.centerX = fx - (screenX * dpr - this.canvas.width  / 2) / (newZoom * minDim);
    this.state.centerY = fy - (screenY * dpr - this.canvas.height / 2) / (newZoom * minDim);
    this.state.zoom = newZoom;
    this.adaptIterations();
  }

  private zoomStep(factor: number, screenX: number, screenY: number) {
    this.zoom(factor, screenX, screenY);
    this.onNeedsRender();
  }

  private updateJuliaCFromPoint(screenX: number, screenY: number) {
    const dpr    = window.devicePixelRatio || 1;
    const minDim = Math.min(this.canvas.width, this.canvas.height);
    const scale  = 1 / (this.state.zoom * minDim);
    this.state.juliaCX = this.state.centerX + (screenX * dpr - this.canvas.width  / 2) * scale;
    this.state.juliaCY = this.state.centerY + (screenY * dpr - this.canvas.height / 2) * scale;
  }

  private adaptIterations() {
    const depth = Math.max(0, Math.log2(this.state.zoom / 0.3));
    this.state.maxIterations = Math.min(2000, 256 + Math.floor(depth) * 32);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  private clearLongPress() {
    if (this.longPressTimer !== null) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = null;
    }
  }

  private resetPinch() {
    this.prevPinchDist = 0;
    this.prevPinchMidX = 0;
    this.prevPinchMidY = 0;
  }
}
