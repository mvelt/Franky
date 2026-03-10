// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Shared uniform struct
// ─────────────────────────────────────────────────────────────────────────────
// Layout (14 × f32/i32 = 56 bytes, struct align = 4):
//   [0]  centerX         f32
//   [1]  centerY         f32
//   [2]  zoom            f32
//   [3]  colorOffset     f32
//   [4]  juliaCX         f32
//   [5]  juliaCY         f32
//   [6]  colorCycle      f32
//   [7]  aspectRatio     f32
//   [8]  maxIterations   i32
//   [9]  fractalType     i32  (0=Mandelbrot, 1=Julia)
//   [10] paletteIndex    i32  (0–7)
//   [11] viewWidth       f32
//   [12] viewHeight      f32
//   [13] _pad            i32

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
  _pad          : i32,
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Compute pass (fractal → storage texture)
// ─────────────────────────────────────────────────────────────────────────────

@group(0) @binding(0) var<uniform>      u         : FractalUniforms;
@group(0) @binding(1) var               outputTex : texture_storage_2d<rgba8unorm, write>;

// ── Cosine colour gradient (Inigo Quilez technique) ───────────────────────────

fn cosGrad(t: f32, a: vec3f, b: vec3f, c: vec3f, d: vec3f) -> vec3f {
  return clamp(a + b * cos(6.28318530718 * (c * t + d)), vec3f(0.0), vec3f(1.0));
}

fn paletteColor(t: f32, idx: i32) -> vec3f {
  if (idx == 0) { // Classic — cool blue → warm orange
    return cosGrad(t, vec3f(0.5), vec3f(0.5), vec3f(1.0), vec3f(0.0, 0.1, 0.2));
  } else if (idx == 1) { // Fire — black → red → orange → yellow
    return cosGrad(t,
      vec3f(0.5, 0.0, 0.0), vec3f(0.5, 0.35, 0.05),
      vec3f(1.0, 0.7, 0.4), vec3f(0.0, 0.1, 0.15));
  } else if (idx == 2) { // Ocean — deep blue → teal → white
    return cosGrad(t,
      vec3f(0.2, 0.5, 0.7), vec3f(0.2, 0.4, 0.3),
      vec3f(0.5, 0.8, 1.0), vec3f(0.5, 0.25, 0.0));
  } else if (idx == 3) { // Neon — vivid rainbow
    return cosGrad(t, vec3f(0.5), vec3f(0.5),
      vec3f(2.0, 1.0, 0.5), vec3f(0.5, 0.2, 0.25));
  } else if (idx == 4) { // Purple Haze
    return cosGrad(t,
      vec3f(0.4, 0.2, 0.5), vec3f(0.4, 0.2, 0.4),
      vec3f(0.8, 0.5, 1.0), vec3f(0.0, 0.2, 0.4));
  } else if (idx == 5) { // Sunset
    return cosGrad(t,
      vec3f(0.5, 0.3, 0.3), vec3f(0.5, 0.3, 0.2),
      vec3f(0.8, 0.6, 0.3), vec3f(0.0, 0.1, 0.5));
  } else if (idx == 6) { // Ice
    return cosGrad(t,
      vec3f(0.7, 0.9, 1.0), vec3f(0.3, 0.1, 0.0),
      vec3f(0.5, 0.5, 1.0), vec3f(0.0, 0.1, 0.2));
  } else if (idx == 7) { // Forest
    return cosGrad(t,
      vec3f(0.2, 0.4, 0.1), vec3f(0.2, 0.3, 0.2),
      vec3f(1.0, 0.7, 0.5), vec3f(0.2, 0.4, 0.6));
  }
  return vec3f(t); // greyscale fallback
}

@compute @workgroup_size(16, 16)
fn fractalKernel(@builtin(global_invocation_id) gid: vec3u) {
  let W = u32(u.viewWidth);
  let H = u32(u.viewHeight);
  if (gid.x >= W || gid.y >= H) { return; }

  // Map pixel → fractal coordinate
  let scale = 1.0 / (u.zoom * min(u.viewWidth, u.viewHeight));
  let cx    = u.centerX + (f32(gid.x) - u.viewWidth  * 0.5) * scale;
  let cy    = u.centerY + (f32(gid.y) - u.viewHeight * 0.5) * scale;

  var zx: f32;
  var zy: f32;
  var jx: f32;
  var jy: f32;

  if (u.fractalType == 0) {
    // ── Mandelbrot: z₀ = 0, c = pixel coord ─────────────────────────────────
    // Early bailout: main cardioid
    let q = (cx - 0.25) * (cx - 0.25) + cy * cy;
    if (q * (q + (cx - 0.25)) < 0.25 * cy * cy) {
      textureStore(outputTex, vec2i(i32(gid.x), i32(gid.y)), vec4f(0.0, 0.0, 0.0, 1.0));
      return;
    }
    // Period-2 bulb
    let bx = cx + 1.0;
    if (bx * bx + cy * cy < 0.0625) {
      textureStore(outputTex, vec2i(i32(gid.x), i32(gid.y)), vec4f(0.0, 0.0, 0.0, 1.0));
      return;
    }
    zx = 0.0; zy = 0.0;
    jx = cx;  jy = cy;
  } else {
    // ── Julia: z₀ = pixel coord, c = fixed param ─────────────────────────────
    zx = cx; zy = cy;
    jx = u.juliaCX; jy = u.juliaCY;
  }

  // ── Main iteration: z = z² + c ──────────────────────────────────────────────
  var iter: i32 = 0;
  var zx2: f32  = 0.0;
  var zy2: f32  = 0.0;
  var period: i32 = 0;
  var pzx: f32  = 0.0;
  var pzy: f32  = 0.0;

  loop {
    if (iter >= u.maxIterations) { break; }
    zx2 = zx * zx;
    zy2 = zy * zy;
    if (zx2 + zy2 > 4.0) { break; }

    let new_zy = 2.0 * zx * zy + jy;
    zx = zx2 - zy2 + jx;
    zy = new_zy;
    iter += 1;

    // Periodicity cycle detection (marks interior set points quickly)
    if (zx == pzx && zy == pzy) { iter = u.maxIterations; break; }
    period += 1;
    if (period >= 20) { period = 0; pzx = zx; pzy = zy; }
  }

  // ── Colouring ───────────────────────────────────────────────────────────────
  var color: vec4f;
  if (iter >= u.maxIterations) {
    color = vec4f(0.0, 0.0, 0.0, 1.0);
  } else {
    // Smooth (continuous) colouring: mu = iter + 1 − log₂(log₂|z|)
    let log_zn = log(zx2 + zy2) * 0.5;
    let nu     = log(log_zn / log(2.0)) / log(2.0);
    let smooth = f32(iter) + 1.0 - nu;
    var t = fract(smooth / u.colorCycle + u.colorOffset);
    if (t < 0.0) { t += 1.0; }
    let rgb = paletteColor(t, u.paletteIndex);
    color = vec4f(rgb, 1.0);
  }

  textureStore(outputTex, vec2i(i32(gid.x), i32(gid.y)), color);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Render pass (blit fractal texture → canvas)
// ─────────────────────────────────────────────────────────────────────────────

struct VertexOut {
  @builtin(position) pos : vec4f,
  @location(0)       uv  : vec2f,
}

@vertex
fn displayVertex(@builtin(vertex_index) vid: u32) -> VertexOut {
  // Fullscreen triangle strip, UV flipped vertically (Metal-style origin)
  var positions = array<vec2f, 4>(
    vec2f(-1.0, -1.0), vec2f( 1.0, -1.0),
    vec2f(-1.0,  1.0), vec2f( 1.0,  1.0)
  );
  var uvs = array<vec2f, 4>(
    vec2f(0.0, 1.0), vec2f(1.0, 1.0),
    vec2f(0.0, 0.0), vec2f(1.0, 0.0)
  );
  var out: VertexOut;
  out.pos = vec4f(positions[vid], 0.0, 1.0);
  out.uv  = uvs[vid];
  return out;
}

@group(0) @binding(0) var displaySampler : sampler;
@group(0) @binding(1) var displayTex     : texture_2d<f32>;

@fragment
fn displayFragment(in: VertexOut) -> @location(0) vec4f {
  return textureSample(displayTex, displaySampler, in.uv);
}
