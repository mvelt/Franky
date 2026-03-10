import shaderSource from './shaders.wgsl?raw';
import type { FractalState } from './main';

// Size of FractalUniforms struct in bytes.
// WGSL requires uniform structs to have SizeOf = roundUp(AlignOf, member_sum).
// AlignOf a struct in <uniform> is max(16, max_member_align) = 16.
// roundUp(16, 14 × 4 = 56) = 64. Safari/WebKit strictly enforces this.
const UNIFORM_SIZE = 64;

export class FractalRenderer {
  readonly device: GPUDevice;
  private context: GPUCanvasContext;
  private canvasFormat: GPUTextureFormat;
  private canvas: HTMLCanvasElement;

  private renderPipeline!: GPURenderPipeline;
  private uniformBuffer!: GPUBuffer;
  private renderBG!: GPUBindGroup;

  private constructor(device: GPUDevice, canvas: HTMLCanvasElement) {
    this.device = device;
    this.canvas = canvas;
    const ctx = canvas.getContext('webgpu');
    if (!ctx) throw new Error('webgpu context failed');
    this.context = ctx;
    this.canvasFormat = navigator.gpu.getPreferredCanvasFormat();
    this.context.configure({ device, format: this.canvasFormat, alphaMode: 'opaque' });
  }

  // ── Factory ────────────────────────────────────────────────────────────────

  static async create(canvas: HTMLCanvasElement): Promise<FractalRenderer | null> {
    if (!navigator.gpu) return null;
    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) return null;
    const device = await adapter.requestDevice();
    const r = new FractalRenderer(device, canvas);
    await r.buildPipelines();
    return r;
  }

  // ── Pipeline setup ──────────────────────────────────────────────────────────

  private async buildPipelines() {
    const module = this.device.createShaderModule({ code: shaderSource });

    // Uniform buffer (written every frame)
    this.uniformBuffer = this.device.createBuffer({
      size: UNIFORM_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    // Single bind group layout: uniform buffer visible to fragment stage
    const bgl = this.device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.FRAGMENT,
          buffer: { type: 'uniform' } },
      ],
    });

    this.renderBG = this.device.createBindGroup({
      layout: bgl,
      entries: [
        { binding: 0, resource: { buffer: this.uniformBuffer } },
      ],
    });

    // Render pipeline: VS generates fullscreen quad, FS computes fractal
    this.renderPipeline = this.device.createRenderPipeline({
      layout: this.device.createPipelineLayout({ bindGroupLayouts: [bgl] }),
      vertex:   { module, entryPoint: 'vs' },
      fragment: { module, entryPoint: 'fs',
                  targets: [{ format: this.canvasFormat }] },
      primitive: { topology: 'triangle-strip' },
    });
  }

  // ── Uniform update ──────────────────────────────────────────────────────────

  updateUniforms(state: FractalState, w: number, h: number) {
    const buf = new ArrayBuffer(UNIFORM_SIZE);
    const f32 = new Float32Array(buf);
    const i32 = new Int32Array(buf);
    f32[0]  = state.centerX;
    f32[1]  = state.centerY;
    f32[2]  = state.zoom;
    f32[3]  = state.colorOffset;
    f32[4]  = state.juliaCX;
    f32[5]  = state.juliaCY;
    f32[6]  = state.colorCycle;
    f32[7]  = w / h; // aspectRatio
    i32[8]  = state.maxIterations;
    i32[9]  = state.fractalType;
    i32[10] = state.paletteIndex;
    f32[11] = w;
    f32[12] = h;
    i32[13] = 0;
    this.device.queue.writeBuffer(this.uniformBuffer, 0, buf);
  }

  // ── Draw ────────────────────────────────────────────────────────────────────

  draw() {
    const enc = this.device.createCommandEncoder();
    const rp  = enc.beginRenderPass({
      colorAttachments: [{
        view:       this.context.getCurrentTexture().createView(),
        loadOp:     'clear',
        storeOp:    'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }],
    });
    rp.setPipeline(this.renderPipeline);
    rp.setBindGroup(0, this.renderBG);
    rp.draw(4);
    rp.end();
    this.device.queue.submit([enc.finish()]);
  }

  // ── Snapshot (canvas → PNG blob) ────────────────────────────────────────────

  async snapshot(): Promise<Blob | null> {
    return new Promise((resolve) => this.canvas.toBlob(resolve, 'image/png'));
  }
}
