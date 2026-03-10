import shaderSource from './shaders.wgsl?raw';
import type { FractalState } from './main';

// Size of FractalUniforms struct in bytes (14 × 4-byte fields)
const UNIFORM_SIZE = 56;

export class FractalRenderer {
  readonly device: GPUDevice;
  private context: GPUCanvasContext;
  private canvasFormat: GPUTextureFormat;

  private computePipeline!: GPUComputePipeline;
  private renderPipeline!: GPURenderPipeline;
  private uniformBuffer!: GPUBuffer;
  private sampler!: GPUSampler;

  // Rebuilt when canvas resizes
  private fractalTexture!: GPUTexture;
  private computeBG!: GPUBindGroup;
  private renderBG!: GPUBindGroup;
  private texW = 0;
  private texH = 0;

  private constructor(device: GPUDevice, canvas: HTMLCanvasElement) {
    this.device = device;
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

    // Sampler for the display pass
    this.sampler = this.device.createSampler({ magFilter: 'nearest', minFilter: 'nearest' });

    // Compute pipeline
    const computeBGL = this.device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE,
          storageTexture: { access: 'write-only', format: 'rgba8unorm', viewDimension: '2d' } },
      ],
    });
    this.computePipeline = this.device.createComputePipeline({
      layout: this.device.createPipelineLayout({ bindGroupLayouts: [computeBGL] }),
      compute: { module, entryPoint: 'fractalKernel' },
    });

    // Render pipeline
    const renderBGL = this.device.createBindGroupLayout({
      entries: [
        { binding: 0, visibility: GPUShaderStage.FRAGMENT, sampler: {} },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: {} },
      ],
    });
    this.renderPipeline = this.device.createRenderPipeline({
      layout: this.device.createPipelineLayout({ bindGroupLayouts: [renderBGL] }),
      vertex:   { module, entryPoint: 'displayVertex' },
      fragment: { module, entryPoint: 'displayFragment',
                  targets: [{ format: this.canvasFormat }] },
      primitive: { topology: 'triangle-strip' },
    });
  }

  // ── Resize ──────────────────────────────────────────────────────────────────

  resize(w: number, h: number) {
    if (w === this.texW && h === this.texH) return;
    this.texW = w;
    this.texH = h;
    this.fractalTexture?.destroy();

    this.fractalTexture = this.device.createTexture({
      size: [w, h],
      format: 'rgba8unorm',
      usage: GPUTextureUsage.STORAGE_BINDING |
             GPUTextureUsage.TEXTURE_BINDING  |
             GPUTextureUsage.COPY_SRC,
    });

    const computeBGL = this.computePipeline.getBindGroupLayout(0);
    this.computeBG = this.device.createBindGroup({
      layout: computeBGL,
      entries: [
        { binding: 0, resource: { buffer: this.uniformBuffer } },
        { binding: 1, resource: this.fractalTexture.createView() },
      ],
    });

    const renderBGL = this.renderPipeline.getBindGroupLayout(0);
    this.renderBG = this.device.createBindGroup({
      layout: renderBGL,
      entries: [
        { binding: 0, resource: this.sampler },
        { binding: 1, resource: this.fractalTexture.createView() },
      ],
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
    if (!this.fractalTexture) return;
    const enc  = this.device.createCommandEncoder();

    // Compute: render fractal → fractalTexture
    const cp = enc.beginComputePass();
    cp.setPipeline(this.computePipeline);
    cp.setBindGroup(0, this.computeBG);
    cp.dispatchWorkgroups(Math.ceil(this.texW / 16), Math.ceil(this.texH / 16));
    cp.end();

    // Render: blit fractalTexture → drawable
    const rp = enc.beginRenderPass({
      colorAttachments: [{
        view: this.context.getCurrentTexture().createView(),
        loadOp: 'clear', storeOp: 'store',
        clearValue: { r: 0, g: 0, b: 0, a: 1 },
      }],
    });
    rp.setPipeline(this.renderPipeline);
    rp.setBindGroup(0, this.renderBG);
    rp.draw(4);
    rp.end();

    this.device.queue.submit([enc.finish()]);
  }

  // ── Snapshot (current fractalTexture → PNG blob) ────────────────────────────

  async snapshot(): Promise<Blob | null> {
    if (!this.fractalTexture) return null;
    const bytesPerRow = Math.ceil(this.texW * 4 / 256) * 256; // align to 256
    const readBuf = this.device.createBuffer({
      size: bytesPerRow * this.texH,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
    });

    const enc = this.device.createCommandEncoder();
    enc.copyTextureToBuffer(
      { texture: this.fractalTexture },
      { buffer: readBuf, bytesPerRow, rowsPerImage: this.texH },
      [this.texW, this.texH]
    );
    this.device.queue.submit([enc.finish()]);
    await readBuf.mapAsync(GPUMapMode.READ);

    const rawData = new Uint8Array(readBuf.getMappedRange());
    const offscreen = new OffscreenCanvas(this.texW, this.texH);
    const ctx = offscreen.getContext('2d')!;
    const imgData = ctx.createImageData(this.texW, this.texH);

    // Copy row by row (readBuf may have padding per row)
    for (let y = 0; y < this.texH; y++) {
      const src = rawData.subarray(y * bytesPerRow, y * bytesPerRow + this.texW * 4);
      imgData.data.set(src, y * this.texW * 4);
    }
    ctx.putImageData(imgData, 0, 0);
    readBuf.unmap();
    readBuf.destroy();

    return offscreen.convertToBlob({ type: 'image/png' });
  }
}
