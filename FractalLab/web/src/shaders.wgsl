// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Shared uniform struct
// ─────────────────────────────────────────────────────────────────────────────
// Layout (16 × f32/i32 = 64 bytes):
//   [0]  centerX f32  [1] centerY f32  [2] zoom f32  [3] colorOffset f32
//   [4]  juliaCX f32  [5] juliaCY f32  [6] colorCycle f32  [7] aspectRatio f32
//   [8]  maxIterations i32  [9] fractalType i32  [10] paletteIndex i32
//   [11] viewWidth f32  [12] viewHeight f32  [13-15] _pad i32 ×3
// 64 bytes = roundUp(16, 56): WGSL uniform structs must be a multiple of 16.

struct FractalUniforms {
  centerX       : f32,
  centerY       : f32,
  zoom          : f32,
  colorOffset   : f32,
  juliaCX       : f32,
  juliaCY       : f32,
  colorCycle    : f32,
  aspectRatio   : f32,
  maxIterations : i32,
  fractalType   : i32,
  paletteIndex  : i32,
  viewWidth     : f32,
  viewHeight    : f32,
  _pad0         : i32,
  _pad1         : i32,
  _pad2         : i32,
}

@group(0) @binding(0) var<uniform> u: FractalUniforms;

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Colour palettes
// ─────────────────────────────────────────────────────────────────────────────

fn cosGrad(t: f32, a: vec3f, b: vec3f, c: vec3f, d: vec3f) -> vec3f {
  return clamp(a + b * cos(6.28318530718 * (c * t + d)), vec3f(0.0), vec3f(1.0));
}

fn paletteColor(t: f32, idx: i32) -> vec3f {
  if (idx == 0) {
    return cosGrad(t, vec3f(0.5), vec3f(0.5), vec3f(1.0), vec3f(0.0, 0.1, 0.2));
  } else if (idx == 1) {
    return cosGrad(t, vec3f(0.5,0.0,0.0), vec3f(0.5,0.35,0.05),
                      vec3f(1.0,0.7,0.4),  vec3f(0.0,0.1,0.15));
  } else if (idx == 2) {
    return cosGrad(t, vec3f(0.2,0.5,0.7), vec3f(0.2,0.4,0.3),
                      vec3f(0.5,0.8,1.0),  vec3f(0.5,0.25,0.0));
  } else if (idx == 3) {
    return cosGrad(t, vec3f(0.5), vec3f(0.5),
                      vec3f(2.0,1.0,0.5),  vec3f(0.5,0.2,0.25));
  } else if (idx == 4) {
    return cosGrad(t, vec3f(0.4,0.2,0.5), vec3f(0.4,0.2,0.4),
                      vec3f(0.8,0.5,1.0),  vec3f(0.0,0.2,0.4));
  } else if (idx == 5) {
    return cosGrad(t, vec3f(0.5,0.3,0.3), vec3f(0.5,0.3,0.2),
                      vec3f(0.8,0.6,0.3),  vec3f(0.0,0.1,0.5));
  } else if (idx == 6) {
    return cosGrad(t, vec3f(0.7,0.9,1.0), vec3f(0.3,0.1,0.0),
                      vec3f(0.5,0.5,1.0),  vec3f(0.0,0.1,0.2));
  } else if (idx == 7) {
    return cosGrad(t, vec3f(0.2,0.4,0.1), vec3f(0.2,0.3,0.2),
                      vec3f(1.0,0.7,0.5),  vec3f(0.2,0.4,0.6));
  }
  return vec3f(t);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Vertex shader (fullscreen triangle-strip)
// ─────────────────────────────────────────────────────────────────────────────

// VS outputs both clip-space position and NDC UV for the fragment stage.
// The UV is passed as an explicit inter-stage varying so the fragment shader
// does not need to rely on @builtin(position), which has known bugs in
// Safari 17 on iOS (the value can be incorrect on some Metal hardware).
struct VertexOut {
  @builtin(position) pos : vec4f,
  @location(0)       uv  : vec2f,   // NDC coords: x ∈ [-1,1], y ∈ [-1,1] (y-up)
}

@vertex
fn vs(@builtin(vertex_index) vid: u32) -> VertexOut {
  var positions = array<vec2f, 4>(
    vec2f(-1.0, -1.0), vec2f( 1.0, -1.0),
    vec2f(-1.0,  1.0), vec2f( 1.0,  1.0)
  );
  let p = positions[vid];
  var out: VertexOut;
  out.pos = vec4f(p, 0.0, 1.0);
  out.uv  = p;
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Fragment shader
// ─────────────────────────────────────────────────────────────────────────────

// Separate input struct for the fragment stage: only the location-0 UV varying.
// Avoids bringing @builtin(position) into FS scope entirely.
struct FragIn {
  @location(0) uv: vec2f,
}

@fragment
fn fs(in: FragIn) -> @location(0) vec4f {
  // Map NDC UV to fractal-plane coordinates.
  // NDC y is +1 at the top of the screen; framebuffer y is 0 at the top.
  // This matches the original pixel-based formula:
  //   cx = centerX + (px - viewWidth/2)  * scale   where px = (uv.x+1)/2 * viewWidth
  //   cy = centerY + (py - viewHeight/2) * scale   where py = (1-uv.y)/2 * viewHeight
  let scale = 1.0 / (u.zoom * min(u.viewWidth, u.viewHeight));
  let cx    = u.centerX + in.uv.x * 0.5 * u.viewWidth  * scale;
  let cy    = u.centerY - in.uv.y * 0.5 * u.viewHeight * scale;

  var zx: f32;
  var zy: f32;
  var jx: f32;
  var jy: f32;

  if (u.fractalType == 0) {
    // Mandelbrot: early bailout for main cardioid and period-2 bulb
    let q = (cx - 0.25) * (cx - 0.25) + cy * cy;
    if (q * (q + (cx - 0.25)) < 0.25 * cy * cy) {
      return vec4f(0.0, 0.0, 0.0, 1.0);
    }
    let bx = cx + 1.0;
    if (bx * bx + cy * cy < 0.0625) {
      return vec4f(0.0, 0.0, 0.0, 1.0);
    }
    zx = 0.0; zy = 0.0;
    jx = cx;  jy = cy;
  } else {
    // Julia: z0 = pixel, c = fixed
    zx = cx; zy = cy;
    jx = u.juliaCX; jy = u.juliaCY;
  }

  // Iteration loop. Use a standard for-loop rather than WGSL's loop{} to
  // avoid MSL translation issues in Safari's WGSL compiler.
  var iter: i32   = 0;
  var zx2:  f32   = 0.0;
  var zy2:  f32   = 0.0;
  var period: i32 = 0;
  var pzx:  f32   = 0.0;
  var pzy:  f32   = 0.0;

  for (var i: i32 = 0; i < u.maxIterations; i++) {
    zx2 = zx * zx;
    zy2 = zy * zy;
    if (zx2 + zy2 > 4.0) { break; }
    let new_zy = 2.0 * zx * zy + jy;
    zx   = zx2 - zy2 + jx;
    zy   = new_zy;
    iter = i + 1;
    if (zx == pzx && zy == pzy) { iter = u.maxIterations; break; }
    period += 1;
    if (period >= 20) { period = 0; pzx = zx; pzy = zy; }
  }

  if (iter >= u.maxIterations) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }

  let log_zn = log(zx2 + zy2) * 0.5;
  let nu     = log(log_zn / log(2.0)) / log(2.0);
  let smooth = f32(iter) + 1.0 - nu;
  var t = fract(smooth / u.colorCycle + u.colorOffset);
  if (t < 0.0) { t += 1.0; }
  let rgb = paletteColor(t, u.paletteIndex);
  return vec4f(rgb, 1.0);
}
