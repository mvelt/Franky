# FractalLab

A GPU-accelerated fractal explorer for iPhone, built with Swift, SwiftUI, and Metal.

---

## Features

| Feature | Details |
|---|---|
| **Fractals** | Mandelbrot set and Julia set |
| **Infinite zoom** | Gesture-driven zoom to ~10⁶× (float-precision limit) |
| **8 colour palettes** | Classic, Fire, Ocean, Neon, Purple Haze, Sunset, Ice, Forest |
| **Colour rotation** | Continuous animation — forward/backward, variable speed |
| **Julia picker** | 8 famous presets, or long-press the canvas to drag `c` in real time |
| **Session recording** | Record exploration at 30 fps, play back at 0.25×–4× (forward/reverse) |
| **Save to Photos** | Export the current frame as a high-res image |
| **Video export** | Render recorded session to H.264 MP4, saved to Photos |

---

## Getting Started

### Prerequisites

| Tool | Install |
|---|---|
| Xcode 15.4+ | [Mac App Store](https://apps.apple.com/app/xcode/id497799835) |
| xcodegen | `brew install xcodegen` |
| iOS 17 device or simulator | — |

### Build

```bash
cd FractalLab
xcodegen generate        # creates FractalLab.xcodeproj
open FractalLab.xcodeproj
```

Then select your device / simulator in Xcode and press **Run** (⌘R).

> **Note:** Metal compute shaders run on real devices and the simulator (Xcode 14+). Performance is much better on device.

---

## Gestures

| Gesture | Action |
|---|---|
| **Double-tap** (1 finger) | Zoom in 2× at that point |
| **Double-tap** (2 fingers) | Zoom out 2× at that point |
| **Pinch** | Free zoom in / out |
| **Pan** (1 finger) | Move the view |
| **Long-press** | Switch to Julia mode; drag to set the `c` parameter live |

---

## Controls (top-right panel)

Tap the **☰** icon to expand/collapse the control panel.

- **Fractal** — switch Mandelbrot ↔ Julia
- **Julia Preset** — choose from 8 famous Julia sets
- **Palette** — swatch bar; tap to change
- **Colour Rotation** — ▶ play, ⏹ stop, ◀◀ reverse; sliders for speed and colour density
- **Max Iterations** — slider from 64 to 2000 (higher = more detail, slower)
- **Save Photo** — saves current frame to Photos
- **Reset** — returns to default Mandelbrot view

---

## Recording & Export (bottom bar)

| Button | Action |
|---|---|
| ● **Record** | Start capturing keyframes at 30 fps |
| ■ **Stop** | Finish recording |
| ▶ **Play** | Play back the session |
| ◀◀ / ▶▶ | Reverse / forward playback |
| − / + | Halve / double playback speed |
| ↑ (share icon) | Save frame to Photos or export MP4 video |

---

## Architecture

```
FractalLab/
├── Metal/
│   ├── ShaderTypes.h           # C struct shared with Swift (bridging header)
│   └── FractalShaders.metal    # fractalKernel (compute) + display pass
├── Rendering/
│   ├── FractalRenderer.swift   # MTKViewDelegate; compute + render pipelines
│   └── MetalView.swift         # UIViewRepresentable(MTKView) + gesture forwarding
├── Models/
│   ├── FractalState.swift      # ObservableObject — single source of truth
│   ├── ColorPalette.swift      # 8 palettes + 8 Julia presets
│   ├── FractalType.swift       # Mandelbrot / Julia enum
│   └── SessionRecording.swift  # Keyframe model + interpolation
├── Views/
│   ├── FractalCanvasView.swift # Full-screen Metal canvas + gesture wiring
│   ├── ControlPanelView.swift  # Collapsible HUD
│   └── RecordingControlsView.swift # Transport bar
├── Recording/
│   ├── SessionRecorder.swift   # Capture timer + CADisplayLink playback
│   └── VideoExporter.swift     # AVAssetWriter → H.264 MP4
└── App/
    ├── FractalLabApp.swift
    └── ContentView.swift       # Root: binds state ↔ renderer ↔ UI
```

### Rendering pipeline (per frame)

```
FractalState → FractalParams struct
     ↓
fractalKernel (Metal compute)  →  MTLTexture (RGBA)
     ↓
displayVertex / displayFragment (render pass)  →  MTKView drawable
```

---

## Zoom depth & precision

The Metal shader uses 32-bit floats. Artifacts appear around **10⁶× zoom** in detailed regions. For deeper exploration, a future version could use perturbation theory or 64-bit doubles (Apple Silicon / A15+).

---

## Licence

MIT — free to use and modify.
